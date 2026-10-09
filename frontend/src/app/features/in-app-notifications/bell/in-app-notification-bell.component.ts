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

import { ChangeDetectionStrategy, Component, ElementRef, Input, OnInit, HostListener, inject } from '@angular/core';
import { combineLatest, merge, Observable, timer } from 'rxjs';
import { filter, map, shareReplay, switchMap, throttleTime } from 'rxjs/operators';
import { ActiveWindowService } from 'core-app/core/active-window/active-window.service';
import { PathHelperService } from 'core-app/core/path-helper/path-helper.service';
import { ApiV3Service } from 'core-app/core/apiv3/api-v3.service';
import { I18nService } from 'core-app/core/i18n/i18n.service';
import { ChangeDetectorRef } from '@angular/core';
import { InAppNotificationsResourceService } from 'core-app/core/state/in-app-notifications/in-app-notifications.service';
import { INotification } from 'core-app/core/state/in-app-notifications/in-app-notification.model';
import { IAN_FACET_FILTERS } from 'core-app/features/in-app-notifications/center/state/ian-center.store';
import { IanBellService } from 'core-app/features/in-app-notifications/bell/state/ian-bell.service';
import { populateInputsFromDataset } from 'core-app/shared/components/dataset-inputs';

@Component({
  selector: 'opce-in-app-notification-bell',
  templateUrl: './in-app-notification-bell.component.html',
  styleUrls: ['./in-app-notification-bell.component.sass'],
  changeDetection: ChangeDetectionStrategy.OnPush,
  standalone: false,
})
export class InAppNotificationBellComponent implements OnInit {
  readonly elementRef = inject<ElementRef<HTMLElement>>(ElementRef);
  readonly storeService = inject(IanBellService);
  readonly apiV3Service = inject(ApiV3Service);
  readonly activeWindow = inject(ActiveWindowService);
  readonly pathHelper = inject(PathHelperService);
  readonly I18n = inject(I18nService);
  readonly cdRef = inject(ChangeDetectorRef);
  readonly resourceService = inject(InAppNotificationsResourceService);

  open = false;
  loading = false;
  notifications:INotification[] = [];

  text = {
    title: this.I18n.t('js.label_notification_center_plural', { defaultValue: 'Notifications' }),
    empty: this.I18n.t('js.notifications.center.empty_state.no_notification'),
    view_all: this.I18n.t('js.notifications.center.view_all', { defaultValue: 'View all' }),
  };

  get notificationsPath():string {
    return this.pathHelper.notificationsPath();
  }

  itemPath(notification:INotification):string {
    const id = notification._links.resource?.href?.split('/').pop();
    return id ? this.pathHelper.notificationsDetailsPath(id, 'activity') : this.notificationsPath;
  }

  @HostListener('document:click', ['$event'])
  onDocumentClick(event:MouseEvent) {
    const target = event.target as HTMLElement;
    if (target.closest('.op-ian-bell')) {
      this.toggle();
    } else if (this.open && !this.elementRef.nativeElement.contains(target)) {
      this.close();
    }
  }

  @HostListener('document:keydown.escape')
  close() {
    this.open = false;
    this.cdRef.markForCheck();
  }

  reasonText(reason:string):string {
    return this.I18n.t(`js.notifications.reasons.${reason}`, { defaultValue: reason });
  }

  private toggle() {
    this.open = !this.open;
    if (this.open) {
      this.load();
    }
    this.cdRef.markForCheck();
  }

  private load() {
    this.loading = true;
    this.resourceService
      .fetchCollection({
        filters: IAN_FACET_FILTERS.unread,
        pageSize: 5,
        sortBy: [['createdAt', 'desc']],
      })
      .subscribe({
        next: (result) => {
          this.notifications = result._embedded.elements;
          this.loading = false;
          this.cdRef.markForCheck();
        },
        error: () => {
          this.loading = false;
          this.cdRef.markForCheck();
        },
      });
  }

  @Input() interval = 50000;

  polling$:Observable<number>;

  unreadCount$:Observable<number>;

  unreadCountText$:Observable<number|string>;

  public bellDisplayLimit = 99;

  constructor() {
    populateInputsFromDataset(this);
  }

  // enable other parts of the application to trigger an immediate update
  // e.g. a stimulus controller
  // currently used by the new activities tab which does its own polling
  // and receives updates from the backend earlier than the polling in the bell component
  @HostListener('document:ian-update-immediate')
  triggerImmediateUpdate() {
    this.storeService.fetchUnread().subscribe();
  }

  ngOnInit() {
    this.polling$ = merge(
      timer(10, this.interval).pipe(filter(() => this.activeWindow.isActive)),
      timer(10, this.interval * 10).pipe(filter(() => !this.activeWindow.isActive)),
    )
      .pipe(
        throttleTime(this.interval),
        switchMap(() => this.storeService.fetchUnread()),
      );

    this.unreadCount$ = combineLatest([
      this.storeService.unread$,
      this.polling$,
    ]).pipe(
      map(([count]) => count),
      shareReplay(1),
    );

    this.unreadCountText$ = this
      .unreadCount$
      .pipe(
        map((count) => {
          if (count > this.bellDisplayLimit || count <= 0) {
            return '';
          }

          return count;
        }),
      );
  }
}
