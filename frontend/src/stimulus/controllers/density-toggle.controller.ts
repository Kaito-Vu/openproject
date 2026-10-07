import { Controller } from '@hotwired/stimulus';

const KEY = 'op-density';

// Switches between the compact (default) and comfortable UI density.
// The choice is per browser and stored in localStorage.
export default class DensityToggleController extends Controller {
  connect() {
    this.apply(this.stored());
  }

  toggle() {
    const next = this.stored() === 'comfortable' ? 'compact' : 'comfortable';
    try { localStorage.setItem(KEY, next); } catch { /* storage unavailable */ }
    this.apply(next);
  }

  private stored():string {
    try { return localStorage.getItem(KEY) === 'comfortable' ? 'comfortable' : 'compact'; } catch { return 'compact'; }
  }

  private apply(density:string) {
    document.documentElement.dataset.density = density;
    (this.element as HTMLElement).setAttribute('aria-pressed', String(density === 'comfortable'));
  }
}
