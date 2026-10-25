import { MergedVideo, Settings, DEFAULT_SETTINGS } from './Types';
import { DiscoverySearchService } from '../data/DiscoverySearchService';

export interface DiscoverySearchState {
  results: MergedVideo[];
  refreshing: boolean;
  updatedAt: number;
  failedCount: number;
  error: string;
}

/** Request generations protect a different film or a dismissed destination from late completions. */
export class DiscoverySearchSession {
  state: DiscoverySearchState = { results: [], refreshing: false, updatedAt: 0, failedCount: 0, error: '' };
  onChange: (state: DiscoverySearchState) => void = () => {};
  private generation: number = 0;
  private keyword: string = '';
  private settings: Settings = DEFAULT_SETTINGS;

  open(keyword: string, settings: Settings): void {
    this.generation++;
    this.keyword = keyword;
    this.settings = settings;
    const cached = DiscoverySearchService.peek(keyword, settings);
    this.state = { results: cached !== null ? cached.results : [], refreshing: false,
      updatedAt: cached !== null ? cached.updatedAt : 0, failedCount: 0, error: '' };
    this.onChange(this.state);
    if (cached === null || DiscoverySearchService.stale(cached) || DiscoverySearchService.inFlight(keyword, settings)) this.refresh();
  }

  async refresh(): Promise<void> {
    if (this.state.refreshing || this.keyword.trim() === '') return;
    const token = ++this.generation;
    this.state = { results: this.state.results, refreshing: true, updatedAt: this.state.updatedAt,
      failedCount: this.state.failedCount, error: '' };
    this.onChange(this.state);
    const reply = await DiscoverySearchService.refresh(this.keyword, this.settings);
    if (token !== this.generation) return;
    this.state = { results: reply.cache !== null ? reply.cache.results : this.state.results, refreshing: false,
      updatedAt: reply.cache !== null ? reply.cache.updatedAt : this.state.updatedAt,
      failedCount: reply.failedCount, error: reply.error };
    this.onChange(this.state);
  }

  close(): void { this.generation++; }
}
