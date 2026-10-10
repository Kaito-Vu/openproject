//-- copyright
// OpenProject is an open source project management software.
// Copyright (C) the OpenProject GmbH
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License version 3.
//
// OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
// Copyright (C) 2006-2013 Jean-Philippe Lang
// Copyright (C) 2010-2013 the ChiliProject Team
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
//
// See COPYRIGHT and LICENSE files for more details.
//++

import { HttpErrorResponse } from '@angular/common/http';
import {
  catchError, finalize, of, Subscription, switchMap,
} from 'rxjs';
import {
  Component, computed, DOCUMENT, ElementRef, HostListener, Input, OnDestroy, OnInit, inject, signal, viewChild,
} from '@angular/core';
import { toObservable, toSignal } from '@angular/core/rxjs-interop';
import { FormsModule } from '@angular/forms';
import {
  ColumnsIconComponent, CopyIconComponent, DownloadIconComponent, PlayIconComponent, PlusIconComponent, StackIconComponent,
  TrashIconComponent,
} from '@openproject/octicons-angular';
import { populateInputsFromDataset } from 'core-app/shared/components/dataset-inputs';
import { I18nService } from 'core-app/core/i18n/i18n.service';
import { TimezoneService } from 'core-app/core/datetime/timezone.service';
import { ToastService } from 'core-app/shared/components/toaster/toast.service';
import {
  addCondition, canGroup, Condition, emptyTree, group, Group, layout, LayoutRow, Op, Path, pruneIncomplete, removeAt, rows,
  setOp, ungroup, updateCondition, withKeys,
} from './work-item-query-tree';
import {
  apiErrors, errorText, linkId, QueryMode, resolveProjectId, WorkItemQuery, WorkItemQueryPayload, WorkItemQueryService,
} from './work-item-query.service';
import { downloadCsv, safeFileName, toCsv } from './work-item-csv';
import { copyText } from './work-item-copy-text';
import {
  COLUMN_CATALOG, columnLabelKey, DEFAULT_COLUMNS, toggleColumn,
} from './work-item-columns';
import {
  ResultRow, timezoneFormat, toResultRows, WorkItemResultsComponent,
} from './work-item-results.component';
import { WorkItemConditionRowComponent } from './work-item-condition-row.component';
import { WorkItemFilterSchemaService } from './work-item-filter-schema.service';
import { FieldSchema, needsValues } from './work-item-filter-schema';

// Rows loaded per run (and exported as CSV).
const PAGE_SIZE = 500;

// Everything the user edits; the baseline (as loaded, saved or started) is one of these.
interface EditorState {
  name:string; mode:QueryMode; acrossProjects:boolean; columns:string[]; isPublic:boolean; tree:Group;
}

// Blank clauses and client keys do not count as changes.
const comparable = (s:EditorState):string => JSON.stringify({ ...s, name: s.name.trim(), tree: pruneIncomplete(s.tree) });

@Component({
  selector: 'op-work-item-query-editor',
  standalone: true,
  imports: [
    FormsModule, WorkItemResultsComponent, WorkItemConditionRowComponent,
    ColumnsIconComponent, CopyIconComponent, DownloadIconComponent, PlayIconComponent, PlusIconComponent, StackIconComponent,
    TrashIconComponent,
  ],
  templateUrl: './work-item-query-editor.component.html',
  styleUrls: ['./work-item-queries.shared.css', './work-item-query-editor.component.css'],
})
export class WorkItemQueryEditorComponent implements OnInit, OnDestroy {
  @Input() projectId:number|null = null;

  @Input() queryId:number|null = null;

  // UI paths built by Rails (route helpers, so they include the relative URL root).
  @Input() listUrl = '';

  @Input() editorUrl = '';

  readonly elementRef = inject<ElementRef<HTMLElement>>(ElementRef);

  private service = inject(WorkItemQueryService);

  private schema = inject(WorkItemFilterSchemaService);

  private I18n = inject(I18nService);

  private toast = inject(ToastService);

  private timezone = inject(TimezoneService);

  private document = inject(DOCUMENT);

  private nameInput = viewChild<ElementRef<HTMLInputElement>>('nameInput');

  readonly text = {
    queries: this.I18n.t('js.work_item_queries.title'),
    newQuery: this.I18n.t('js.work_item_queries.new_query'),
    columns: this.I18n.t('js.label_columns'),
    group: this.I18n.t('js.label_group'),
    field: this.I18n.t('js.work_item_queries.filter.field'),
    operator: this.I18n.t('js.work_item_queries.filter.operator'),
    value: this.I18n.t('js.work_item_queries.filter.value'),
    addNewClause: this.I18n.t('js.work_item_queries.editor.add_new_clause'),
    and: this.I18n.t('js.work_item_queries.editor.and'),
    andOr: this.I18n.t('js.work_item_queries.editor.and_or'),
    breadcrumb: this.I18n.t('js.work_item_queries.editor.breadcrumb'),
    clauseGroup: this.I18n.t('js.work_item_queries.editor.clause_group'),
    columnOptions: this.I18n.t('js.work_item_queries.editor.column_options'),
    confirmRevert: this.I18n.t('js.work_item_queries.editor.confirm_revert'),
    copied: this.I18n.t('js.work_item_queries.editor.copied'),
    copyFailed: this.I18n.t('js.work_item_queries.editor.copy_failed'),
    copyUrl: this.I18n.t('js.work_item_queries.editor.copy_url'),
    emptyNoResultsText: this.I18n.t('js.work_item_queries.editor.empty_no_results_text'),
    emptyNoResultsTitle: this.I18n.t('js.work_item_queries.editor.empty_no_results_title'),
    emptyNotRunText: this.I18n.t('js.work_item_queries.editor.empty_not_run_text'),
    emptyNotRunTitle: this.I18n.t('js.work_item_queries.editor.empty_not_run_title'),
    exportCsv: this.I18n.t('js.work_item_queries.editor.export_csv'),
    exportCsvTitle: this.I18n.t('js.work_item_queries.editor.export_csv_title', { max: PAGE_SIZE }),
    filtersHint: this.I18n.t('js.work_item_queries.editor.filters_hint'),
    filtersTitle: this.I18n.t('js.work_item_queries.editor.filters_title'),
    incompleteClauses: this.I18n.t('js.work_item_queries.errors.incomplete_clauses'),
    loadingQuery: this.I18n.t('js.work_item_queries.editor.loading_query'),
    modeFlat: this.I18n.t('js.work_item_queries.editor.mode_flat'),
    modeLabel: this.I18n.t('js.work_item_queries.editor.mode_label'),
    modeTree: this.I18n.t('js.work_item_queries.editor.mode_tree'),
    nameLabel: this.I18n.t('js.work_item_queries.editor.name_label'),
    namePlaceholder: this.I18n.t('js.work_item_queries.editor.name_placeholder'),
    nameRequired: this.I18n.t('js.work_item_queries.errors.name_required'),
    noOwnProject: this.I18n.t('js.work_item_queries.editor.no_own_project'),
    or: this.I18n.t('js.work_item_queries.editor.or'),
    publicDenied: this.I18n.t('js.work_item_queries.editor.public_denied'),
    queryAcrossProjects: this.I18n.t('js.work_item_queries.editor.query_across_projects'),
    results: this.I18n.t('js.work_item_queries.editor.results'),
    resultsStale: this.I18n.t('js.work_item_queries.editor.results_stale'),
    revert: this.I18n.t('js.work_item_queries.editor.revert'),
    run: this.I18n.t('js.work_item_queries.editor.run'),
    running: this.I18n.t('js.work_item_queries.editor.running'),
    save: this.I18n.t('js.work_item_queries.editor.save'),
    saving: this.I18n.t('js.work_item_queries.editor.saving'),
    settingsLabel: this.I18n.t('js.work_item_queries.editor.settings_label'),
    sharedWithEveryone: this.I18n.t('js.work_item_queries.editor.shared_with_everyone'),
    ungroup: this.I18n.t('js.work_item_queries.editor.ungroup'),
    unsavedChanges: this.I18n.t('js.work_item_queries.editor.unsaved_changes'),
    where: this.I18n.t('js.work_item_queries.editor.where'),
    addBelow: (name:string) => this.I18n.t('js.work_item_queries.editor.add_below_named', { name }),
    opBefore: (name:string) => this.I18n.t('js.work_item_queries.editor.operator_named', { name }),
    remove: (name:string) => this.I18n.t('js.work_item_queries.editor.remove_named', { name }),
    select: (name:string) => this.I18n.t('js.work_item_queries.editor.select_named', { name }),
    ungroupNamed: (name:string) => this.I18n.t('js.work_item_queries.editor.ungroup_named', { name }),
    showingFirst: (shown:number, total:number) => this.I18n.t('js.work_item_queries.editor.showing_first', { shown, total }),
    workItemsCount: (count:number) => this.I18n.t('js.work_item_queries.editor.work_items_count', { count }),
  };

  // Signals: the app is zoneless, so state changed in HTTP callbacks must notify the view itself.
  readonly tree = signal<Group>(emptyTree());

  readonly mode = signal<QueryMode>('flat');

  readonly acrossProjects = signal(false);

  readonly columns = signal<string[]>(DEFAULT_COLUMNS);

  readonly showColumns = signal(false);

  readonly catalog = COLUMN_CATALOG.map((c) => ({ id: c.id, label: this.I18n.t(c.labelKey) }));

  readonly isPublic = signal(false);

  // Set when the API refused to share with everyone (422 on `public`: missing manage_public_queries).
  readonly publicDenied = signal(false);

  readonly name = signal('');

  readonly nameInvalid = signal(false);

  // 'loading'/'failed' only apply to an existing query (?id=); the form is shown once 'ready'.
  readonly status = signal<'loading'|'ready'|'failed'>('ready');

  readonly currentId = signal<number|null>(null);

  // Project of the saved query being edited (null for a new or a global query).
  private readonly savedProjectId = signal<number|null>(null);

  readonly baseline = signal<EditorState|null>(null);

  readonly results = signal<ResultRow[]>([]);

  readonly total = signal(0);

  // True once a run has finished, to tell "not run yet" from "no matches".
  readonly ran = signal(false);

  // What the shown results were run with, to flag them as stale after edits.
  private readonly lastRun = signal<string|null>(null);

  readonly running = signal(false);

  readonly saving = signal(false);

  readonly error = signal<string|null>(null);

  // Highlight clauses that still need values (after Run/Save was refused because of them).
  readonly showInvalid = signal(false);

  readonly selected = signal(new Set<string>());

  readonly copyState = signal<'idle'|'copied'|'failed'>('idle');

  // Text of the page's single, persistent live region.
  readonly announcement = signal('');

  private copyTimer?:ReturnType<typeof setTimeout>;

  private subs:Partial<Record<'load'|'run'|'save', Subscription>> = {};

  private destroyed = false;

  // projectId is a plain input but is fixed once the constructor has read the dataset.
  readonly queryProjectId = computed(() => resolveProjectId(this.acrossProjects(), this.savedProjectId(), this.projectId));

  // Neither the query nor the page has a project: it can only run across projects.
  readonly hasOwnProject = computed(() => resolveProjectId(false, this.savedProjectId(), this.projectId) != null);

  readonly layoutRows = computed(() => layout(this.tree()));

  // Same cached form request as the rows; used to name rows and to find clauses without values.
  private readonly fields = toSignal(
    toObservable(this.queryProjectId).pipe(switchMap((id) => this.schema.fields(id).pipe(catchError(() => of(null))))),
    { initialValue: null as FieldSchema[]|null },
  );

  // Accessible name of every row ("Clause 2 (Status)", "Group 1"), so row controls are distinct.
  readonly rowNames = computed(() => {
    let clauses = 0;
    let groups = 0;
    const fields = this.fields();
    return this.layoutRows().map((row) => {
      if (row.kind === 'group') {
        groups += 1;
        return this.I18n.t('js.work_item_queries.editor.group_name', { n: groups });
      }
      clauses += 1;
      const field = row.node.field && (fields?.find((f) => f.id === row.node.field)?.name ?? row.node.field);
      return field
        ? this.I18n.t('js.work_item_queries.editor.clause_name_field', { n: clauses, field })
        : this.I18n.t('js.work_item_queries.editor.clause_name', { n: clauses });
    });
  });

  readonly incompleteKeys = computed(() => new Set(
    this.layoutRows().filter((r) => r.kind === 'condition' && needsValues(this.fields(), r.node)).map((r) => r.key),
  ));

  readonly canGroup = computed(() => canGroup([...this.selected()].map((k) => k.split('.').map(Number))));

  readonly state = computed(():EditorState => ({
    name: this.name(),
    mode: this.mode(),
    acrossProjects: this.acrossProjects(),
    columns: this.columns(),
    isPublic: this.isPublic(),
    tree: this.tree(),
  }));

  readonly dirty = computed(() => {
    const base = this.baseline();
    return base != null && comparable(this.state()) !== comparable(base);
  });

  readonly stale = computed(() => this.ran() && this.lastRun() !== JSON.stringify(this.runBody()));

  constructor() {
    populateInputsFromDataset(this);
  }

  ngOnInit():void {
    if (this.queryId == null) {
      this.acrossProjects.set(this.projectId == null);
      this.ensureClause();
      this.baseline.set(this.state());
      return;
    }
    this.status.set('loading');
    this.announce(this.text.loadingQuery);
    this.subs.load = this.service.get(Number(this.queryId)).subscribe({
      next: (query) => {
        this.load(query);
        this.status.set('ready');
        this.run();
      },
      error: (err:HttpErrorResponse) => {
        this.status.set('failed');
        this.error.set(errorText(err, this.I18n.t('js.work_item_queries.errors.load_failed')));
      },
    });
  }

  ngOnDestroy():void {
    this.destroyed = true;
    clearTimeout(this.copyTimer);
    Object.values(this.subs).forEach((sub) => sub?.unsubscribe());
  }

  @HostListener('window:beforeunload', ['$event'])
  onBeforeUnload(event:BeforeUnloadEvent):void {
    if (this.dirty()) {
      event.preventDefault();
      event.returnValue = ''; // older browsers only prompt with returnValue set
    }
  }

  columnLabel(id:string):string {
    const key = columnLabelKey(id);
    return key ? this.I18n.t(key) : id;
  }

  exportCsv():void {
    const csv = toCsv(this.results(), this.columns(), {
      label: (c) => this.columnLabel(c),
      format: timezoneFormat(this.timezone),
    });
    downloadCsv(this.document, `${safeFileName(this.name(), this.text.newQuery)}.csv`, csv);
  }

  copyUrl():void {
    const id = this.currentId();
    if (id == null) { return; }
    const win = this.document.defaultView;
    const done = (state:'copied'|'failed'):void => {
      if (this.destroyed) { return; }
      this.copyState.set(state);
      this.announce(state === 'copied' ? this.text.copied : this.text.copyFailed);
      clearTimeout(this.copyTimer);
      this.copyTimer = setTimeout(() => { this.copyState.set('idle'); }, 2000);
    };
    void copyText(win?.navigator.clipboard, `${win?.location.origin ?? ''}${this.queryUrl(id)}`).then(done);
  }

  run():void {
    if (this.blockIncomplete()) { return; }
    this.subs.run?.unsubscribe(); // last request wins; finalize resets `running` before we set it again
    this.running.set(true);
    this.error.set(null);
    this.announce(this.text.running);
    const body = this.runBody();
    this.subs.run = this.service
      .execute({ ...body, pageSize: PAGE_SIZE })
      .pipe(finalize(() => { this.running.set(false); }))
      .subscribe({
        next: (res) => {
          this.ran.set(true);
          this.lastRun.set(JSON.stringify(body));
          this.total.set(res._embedded.results.total ?? 0);
          this.results.set(toResultRows(res));
          this.announce(this.text.workItemsCount(this.total()));
        },
        error: (err:HttpErrorResponse) => {
          this.clearResults();
          this.error.set(errorText(err, this.I18n.t('js.work_item_queries.errors.run_failed')));
        },
      });
  }

  add(parent:Path = []):void { this.tree.update((t) => addCondition(t, parent)); }

  remove(path:Path):void {
    this.tree.update((t) => removeAt(t, path));
    this.ensureClause();
    this.selected.set(new Set());
  }

  update(path:Path, patch:Partial<Condition>):void { this.tree.update((t) => updateCondition(t, path, patch)); }

  setOp(path:Path, op:Op):void { this.tree.update((t) => setOp(t, path, op)); }

  pathKey(row:LayoutRow):string { return row.path.join('.'); }

  toggleSelected(path:Path, checked:boolean):void {
    const key = path.join('.');
    this.selected.update((prev) => {
      const next = new Set(prev);
      if (checked) { next.add(key); } else { next.delete(key); }
      return next;
    });
  }

  toggleColumn(id:string, on:boolean):void { this.columns.update((cols) => toggleColumn(cols, id, on)); }

  group():void {
    if (!this.canGroup()) { return; }
    this.tree.update((t) => group(t, [...this.selected()].map((s) => s.split('.').map(Number))));
    this.selected.set(new Set());
  }

  ungroup(path:Path):void {
    this.tree.update((t) => ungroup(t, path));
    this.selected.set(new Set());
  }

  setName(value:string):void {
    this.name.set(value);
    if (value.trim()) { this.nameInvalid.set(false); }
  }

  save():void {
    if (this.saving() || this.status() !== 'ready') { return; }
    const name = this.name().trim();
    if (!name) {
      this.nameInvalid.set(true);
      this.error.set(this.text.nameRequired);
      this.nameInput()?.nativeElement.focus();
      return;
    }
    if (this.blockIncomplete()) { return; }
    this.error.set(null);
    const sent = { ...this.state(), name };
    const id = this.currentId();
    const body = { ...this.payload(sent), name };
    this.saving.set(true);
    this.announce(this.text.saving);
    const req = id != null ? this.service.update(id, body) : this.service.create(body);
    this.subs.save = req.pipe(finalize(() => { this.saving.set(false); })).subscribe({
      next: (saved) => { this.saved(saved, sent, id == null); },
      error: (err:HttpErrorResponse) => {
        const errors = apiErrors(err);
        if (errors.some((e) => e.attribute === 'public')) {
          this.publicDenied.set(true);
          this.isPublic.set(false);
        }
        if (errors.some((e) => e.attribute === 'name')) { this.nameInvalid.set(true); }
        this.error.set(errorText(err, this.I18n.t('js.work_item_queries.errors.save_failed')));
      },
    });
  }

  // Revert restores every field from the baseline and clears the results (it does not re-run).
  revert():void {
    const base = this.baseline();
    if (!base) { return; }
    if (this.dirty() && !this.document.defaultView?.confirm(this.text.confirmRevert)) { return; }
    this.restore(base);
    this.clearResults();
    this.error.set(null);
    this.nameInvalid.set(false);
    this.showInvalid.set(false);
  }

  private saved(saved:WorkItemQuery, sent:EditorState, wasNew:boolean):void {
    // Keep a name typed while the request was in flight.
    if (this.name().trim() === sent.name) { this.name.set(saved.name); }
    this.currentId.set(saved.id);
    this.savedProjectId.set(linkId(saved._links.project));
    this.baseline.set({ ...sent, name: saved.name });
    if (wasNew) {
      this.document.defaultView?.history.replaceState(null, '', this.queryUrl(saved.id));
    }
    this.toast.addSuccess(this.I18n.t(wasNew ? 'js.notice_successful_create' : 'js.notice_successful_update'));
  }

  private load(query:WorkItemQuery):void {
    const projectId = linkId(query._links.project);
    this.currentId.set(query.id);
    this.savedProjectId.set(projectId);
    this.restore({
      name: query.name,
      mode: query.mode,
      acrossProjects: projectId == null,
      columns: [...query.columns],
      isPublic: query.public,
      tree: withKeys(query.tree ?? emptyTree()),
    });
    this.ensureClause();
    this.baseline.set(this.state());
  }

  private restore(s:EditorState):void {
    this.name.set(s.name);
    this.mode.set(s.mode);
    this.acrossProjects.set(s.acrossProjects);
    this.columns.set([...s.columns]);
    this.isPublic.set(s.isPublic);
    this.tree.set(structuredClone(s.tree));
    this.selected.set(new Set());
  }

  // The editor always shows at least one (possibly blank) clause, like the Azure DevOps editor.
  private ensureClause():void {
    if (rows(this.tree()).length === 0) { this.tree.update((t) => addCondition(t, [])); }
  }

  private runBody():WorkItemQueryPayload {
    // name and public do not change the results
    const { name: _name, public: _public, ...body } = this.payload(this.state());
    return body;
  }

  private payload(s:EditorState):WorkItemQueryPayload {
    const projectId = resolveProjectId(s.acrossProjects, this.savedProjectId(), this.projectId);
    return {
      name: s.name,
      mode: s.mode,
      public: s.isPublic,
      columns: s.columns,
      tree: pruneIncomplete(s.tree),
      _links: { project: { href: this.service.projectHref(projectId) } },
    };
  }

  // Refuses Run/Save while a clause has a field but not the values its operator needs.
  private blockIncomplete():boolean {
    const incomplete = this.incompleteKeys().size > 0;
    this.showInvalid.set(incomplete);
    if (incomplete) { this.error.set(this.text.incompleteClauses); }
    return incomplete;
  }

  private clearResults():void {
    this.results.set([]);
    this.total.set(0);
    this.ran.set(false);
    this.lastRun.set(null);
  }

  private queryUrl(id:number):string { return `${this.editorUrl}?id=${id}`; }

  private announce(message:string):void { this.announcement.set(message); }
}
