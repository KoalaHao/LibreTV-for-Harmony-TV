import { RecommendItem } from './Types';

export interface TvFeedRow {
  key: string;
  kind: string;
  items: RecommendItem[];
}

/** One lazy list owns the viewport, including its full-width header and footer. */
export class TvFeedDataSource implements IDataSource {
  private rows: TvFeedRow[] = [
    { key: 'header', kind: 'header', items: [] },
    { key: 'footer', kind: 'footer', items: [] }
  ];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.rows.length; }
  getData(index: number): TvFeedRow { return this.rows[index]; }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) this.listeners.push(listener);
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((entry: DataChangeListener) => entry !== listener);
  }

  setItems(items: RecommendItem[]): void {
    const rows: TvFeedRow[] = [{ key: 'header', kind: 'header', items: [] }];
    for (let index = 0; index < items.length; index += 6) {
      const posters = items.slice(index, index + 6);
      const identity = JSON.stringify(posters.map((item: RecommendItem) => [item.id, item.title, item.cover,
        item.rating || '', item.isTv.toString(), item.metadataProvider || '']));
      rows.push({ key: 'posters-' + identity, kind: 'posters', items: posters });
    }
    rows.push({ key: 'footer', kind: 'footer', items: [] });
    this.rows = rows;
    // Network changes only. Scrolling never rebuilds or publishes the collection.
    for (const listener of this.listeners) listener.onDataReloaded();
  }
}
