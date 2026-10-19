/**
 * 模块职责：通用惰性数据源（配合 LazyForEach 实现列表虚拟化）。
 * 宿主页通过 replace() 整段替换数据，并通知已注册的 LazyForEach 重载子项。
 * 注：当前 SDK 的 @kit.ArkUI 未导出 IDataSource / DataChangeListener，
 * 故以结构体 + 本地监听接口满足 LazyForEach 的结构类型要求，无需 import 框架类型。
 */
interface LazyDataListener {
  onDataReloaded(): void;
}

export class LazyDataSource<T> {
  private listeners: LazyDataListener[] = [];
  private dataArray: T[] = [];

  constructor(data: T[] = []) {
    this.dataArray = data;
  }

  public totalCount(): number {
    return this.dataArray.length;
  }

  public getData(index: number): T {
    return this.dataArray[index];
  }

  /** 整段替换数据并通知列表重建，适用于查询结果整体刷新。 */
  public replace(data: T[]): void {
    this.dataArray = data;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  public registerDataChangeListener(listener: LazyDataListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  public unregisterDataChangeListener(listener: LazyDataListener): void {
    const pos: number = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }
}
