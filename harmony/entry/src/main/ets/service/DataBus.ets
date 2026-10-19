/**
 * 模块职责：数据版本号总线（架构 1.4 跨页面刷新协议的唯一机制）。
 * 铁律：**任何写库操作之后必须调用 bump()**——忘了就是
 * 「记账了但首页不刷新」（架构文档给工程师的三条开工提醒之三）。
 * 页面侧协议：
 *   @StorageLink(AppConstants.KEY_DATA_VERSION) @Watch('onDataChanged') dv: number
 *   onDataChanged() { reload(); }
 *   onPageShow()    { reload(); }  // router.back() 返回时的兜底
 */
import { AppStorageKeys } from '../constants/AppConstants';

export class DataBus {
  /** 递增数据版本号，驱动所有监听页面重载 */
  public static bump(): void {
    const current: number | undefined = AppStorage.get<number>(AppStorageKeys.DATA_VERSION);
    const next: number = (current === undefined ? 0 : current) + 1;
    AppStorage.setOrCreate(AppStorageKeys.DATA_VERSION, next);
  }

  /** 当前版本号（测试与诊断用） */
  public static current(): number {
    const current: number | undefined = AppStorage.get<number>(AppStorageKeys.DATA_VERSION);
    return current === undefined ? 0 : current;
  }
}
