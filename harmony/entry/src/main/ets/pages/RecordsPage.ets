/**
 * 模块职责：明细页（架构 T05 / PRD 5.3 P3）。
 * 月份切换 + 关键词搜索 + 按日分组流水 + 左滑编辑/删除 + 点进详情。
 * 通过 @StorageLink('dataVersion') @Watch 自动刷新（删除/记账后）。
 */
import { router } from '@kit.ArkUI';
import { palette } from '../constants/ThemeConstants';
import { AppStorageKeys, TxType } from '../constants/AppConstants';
import { ErrorMessages } from '../constants/ErrorMessages';
import { RouteConstants } from '../constants/RouteConstants';
import { RecordsViewModel, RecordsData } from '../viewmodel/RecordsViewModel';
import { TxDisplayMapper } from '../viewmodel/TxDisplayMapper';
import { TxFilter } from '../model/TxFilter';
import { TxGroup, TxDisplayItem } from '../model/StatsModels';
import { Transaction } from '../model/Transaction';
import { LazyDataSource } from '../utils/LazyDataSource';
import { DateUtil } from '../utils/DateUtil';
import { MonthSwitcher } from '../components/list/MonthSwitcher';
import { SearchBar } from '../components/list/SearchBar';
import { TxDayGroupHeader } from '../components/list/TxDayGroupHeader';
import { TxListItem, SWIPE_BUTTON_WIDTH } from '../components/list/TxListItem';
import { EmptyState } from '../components/common/EmptyState';
import { LoadingState } from '../components/common/LoadingState';
import { ErrorState } from '../components/common/ErrorState';
import { ConfirmDialog } from '../components/common/ConfirmDialog';
import { ToastUtil } from '../utils/ToastUtil';
import { DataBus } from '../service/DataBus';

@Entry
@Component
export struct RecordsPage {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  @StorageLink(AppStorageKeys.DATA_VERSION) @Watch('onDataChanged') dataVersion: number = 0;
  @StorageLink(AppStorageKeys.ACTIVE_TAB) @Watch('onActiveTabChanged') activeTab: number = 0;

  @State private data: RecordsData | null = null;
  @State private displayMap: Map<number, TxDisplayItem> = new Map();
  @State private loading: boolean = true;
  @State private errorMsg: string = '';
  @State private monthKey: string = DateUtil.monthKey(DateUtil.now());
  @State private keyword: string = '';

  /** 待删除记录 id（删除二次确认用） */
  @State private pendingDeleteId: number = 0;
  /** 本页在 Tabs 中的下标（门控 bump 并发重载用） */
  private static readonly TAB_INDEX: number = 1;
  /** 加载序号：只有最新一次加载的响应生效（防 bump 重载与切月/搜索乱序覆盖） */
  private loadSeq: number = 0;
  /** 是否已加载过：避免 aboutToAppear 与 onPageShow 重复加载 */
  private loadedOnce: boolean = false;
  /** 不可见期间发生过 bump：切回本 Tab 时再加载，避免保存瞬间并发全量 SQL */
  private pendingReload: boolean = false;
  /** 最近一次真正完成渲染的数据版本，弥补后台 Tab 可能错过 @Watch 回调的情况。 */
  private loadedDataVersion: number = -1;
  private deleteDialog: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({
      title: $r('app.string.list_delete_confirm_title'),
      message: $r('app.string.list_delete_confirm_message'),
      danger: true,
      onConfirmed: (): void => {
        this.confirmDelete();
      }
    }),
    autoCancel: true
  });
  private transferDeleteDialog: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({
      title: $r('app.string.list_delete_confirm_title'),
      message: $r('app.string.list_delete_transfer_tip'),
      danger: true,
      onConfirmed: (): void => {
        this.confirmDelete();
      }
    }),
    autoCancel: true
  });

  /** 外层（日分组）惰性数据源：通过 replace 通知 LazyForEach 整段重载。 */
  private groupSource: LazyDataSource<TxGroup> = new LazyDataSource<TxGroup>();
  /** 内层（每组流水项）惰性数据源：按分组键复用并通知重载。 */
  private itemSources: Map<string, LazyDataSource<Transaction>> = new Map();

  /** 切到本 Tab：启动首次加载 / 补执行不可见期间的 bump 重载（Tab 切换不触发 onPageShow） */
  private onActiveTabChanged(): void {
    if (this.activeTab === RecordsPage.TAB_INDEX &&
      (this.pendingReload || !this.loadedOnce || this.loadedDataVersion !== DataBus.current())) {
      this.pendingReload = false;
      this.loadedOnce = true;
      this.reload();
    }
  }

  /** 数据版本变化：仅当前可见 Tab 真正重载，其余置脏标记 */
  onDataChanged(): void {
    if (this.activeTab === RecordsPage.TAB_INDEX) {
      this.reload();
    } else {
      this.pendingReload = true;
    }
  }

  onPageShow(): void {
    if (this.pendingReload || !this.loadedOnce || this.loadedDataVersion !== DataBus.current()) {
      this.pendingReload = false;
      this.loadedOnce = true;
      this.reload();
    }
  }

  aboutToAppear(): void {
    if (this.activeTab === RecordsPage.TAB_INDEX) {
      this.loadedOnce = true;
      this.reload();
    }
  }

  /** 加载当月流水，并用 TxDisplayMapper 一次性关联分类名/账户名 */
  private async reload(): Promise<void> {
    const seq: number = ++this.loadSeq;
    const reloadDataVersion: number = DataBus.current();
    this.loading = true;
    this.errorMsg = '';
    try {
      const result: RecordsData = await RecordsViewModel.load(this.monthKey, this.keyword, new TxFilter());
      if (seq !== this.loadSeq) {
        return; // 已有更新的加载在途，丢弃过期响应
      }
      const allTx: Transaction[] = [];
      for (let i = 0; i < result.groups.length; i++) {
        const items: Transaction[] = result.groups[i].items;
        for (let j = 0; j < items.length; j++) {
          allTx.push(items[j]);
        }
      }
      const displays: TxDisplayItem[] = await TxDisplayMapper.resolve(allTx);
      // 分类/账户名称关联同样是异步的；此期间若又发生了保存，旧结果不能覆盖新请求。
      if (seq !== this.loadSeq) {
        return;
      }
      const map: Map<number, TxDisplayItem> = new Map();
      for (let i = 0; i < displays.length; i++) {
        map.set(displays[i].tx.id, displays[i]);
      }
      this.displayMap = map;
      // 先更新内层源，再通知外层重载；同日分组保留数据源实例，确保已注册监听者收到更新。
      const srcMap: Map<string, LazyDataSource<Transaction>> = new Map();
      for (let i: number = 0; i < result.groups.length; i++) {
        const g: TxGroup = result.groups[i];
        const key: string = this.groupKeyOf(g);
        const existing: LazyDataSource<Transaction> | undefined = this.itemSources.get(key);
        const src: LazyDataSource<Transaction> = existing === undefined ?
          new LazyDataSource<Transaction>(g.items) : existing;
        if (existing !== undefined) {
          src.replace(g.items);
        }
        srcMap.set(key, src);
      }
      this.itemSources = srcMap;
      this.groupSource.replace(result.groups);
      this.data = result;
      this.loadedDataVersion = reloadDataVersion;
    } catch (e) {
      if (seq !== this.loadSeq) {
        return;
      }
      this.errorMsg = (e instanceof Error) ? e.message : getContext(this).resourceManager.getStringSync($r('app.string.common_error_title'));
      this.data = null;
    } finally {
      if (seq === this.loadSeq) {
        this.loading = false;
      }
    }
  }

  private async onPrevMonth(): Promise<void> {
    this.monthKey = RecordsViewModel.prevMonth(this.monthKey);
    await this.reload();
  }

  private async onNextMonth(): Promise<void> {
    this.monthKey = RecordsViewModel.nextMonth(this.monthKey);
    await this.reload();
  }

  /**
   * 搜索：SearchBar 组件内已做 300ms 防抖（逐字输入不打库），
   * 此处不再二次防抖，避免两层叠加导致 600ms 延迟。
   */
  private onSearch(keyword: string): void {
    this.keyword = keyword;
    this.reload();
  }

  private onEdit(tx: Transaction): void {
    // 左滑入口也必须遵守转账不可单条编辑的规则，不能只依赖详情页按钮。
    if (tx.type === TxType.TRANSFER) {
      ToastUtil.show(ErrorMessages.TX_TRANSFER_EDIT_BLOCKED);
      return;
    }
    router.pushUrl({ url: RouteConstants.RECORD_EDIT, params: { mode: 'edit', txId: tx.id } });
  }

  private onDelete(tx: Transaction): void {
    this.pendingDeleteId = tx.id;
    if (tx.type === TxType.TRANSFER) {
      this.transferDeleteDialog.open();
    } else {
      this.deleteDialog.open();
    }
  }

  private async confirmDelete(): Promise<void> {
    if (this.pendingDeleteId <= 0) {
      return;
    }
    try {
      await RecordsViewModel.deleteTx(this.pendingDeleteId);
      ToastUtil.showRes($r('app.string.toast_delete_success'));
      await this.reload();
    } catch (e) {
      ToastUtil.showRes($r('app.string.toast_delete_failed'));
    } finally {
      this.pendingDeleteId = 0;
    }
  }

  build() {
    Column() {
      if (this.data !== null) {
        Column() {
          MonthSwitcher({
            monthKey: this.monthKey,
            summary: this.data.summary,
            onPrev: (): void => { this.onPrevMonth(); },
            onNext: (): void => { this.onNextMonth(); }
          })
        }
        .width('100%')
        .backgroundColor(palette(this.isDark).bgCard)
        .borderRadius($r('app.float.radius_card'))
        .padding({ top: 12, bottom: 12, left: 12, right: 12 })
        .shadow({ radius: 8, color: palette(this.isDark).shadow, offsetX: 0, offsetY: 2 })
        .margin({ bottom: 12 })

        SearchBar({
          onSearch: (kw: string): void => { this.onSearch(kw); }
        })
        .margin({ bottom: 12 })
      }

      if (this.loading && this.data === null) {
        LoadingState({ rows: 6 })
      } else if (this.errorMsg.length > 0) {
        ErrorState({ onRetry: (): void => { this.reload(); } })
      } else if (this.data === null || this.data.groups.length === 0) {
        EmptyState({ title: $r('app.string.list_empty_month') })
      } else {
        this.list()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).bgPage)
    .padding({ left: 16, right: 16, top: 8 })
  }

  /**
   * 明细列表（无参 Builder：直接绑定 this.data）。
   * ⚠️ ArkUI 铁律一：@Builder 按值传参不随状态刷新，必须引用 this.* 保持响应式。
   * 数据源通过 replace() 显式通知重载，避免异步查询后的旧列表缓存残留。
   */
  @Builder
  private list() {
    List({ space: 10 }) {
      LazyForEach(this.groupSource, (group: TxGroup) => {
        ListItemGroup({ header: this.groupHeader(group) }) {
          LazyForEach(this.itemSources.get(this.groupKeyOf(group))!, (tx: Transaction) => {
            ListItem() {
              TxListItem({
                item: this.displayMap.get(tx.id) ?? this.emptyDisplay(tx),
                showCard: true,
                swipeEnabled: true,
                onItemClick: (txId: number): void => {
                  router.pushUrl({ url: RouteConstants.TX_DETAIL, params: { txId: txId } });
                }
              })
            }
            .swipeAction({ end: this.swipeButtons(tx) })
          }, (tx: Transaction) => 'tx_' + tx.id.toString() + '_' + tx.updatedAt.toString())
        }
      }, (group: TxGroup) => this.groupKeyOf(group))
    }
    .width('100%')
    .layoutWeight(1)
    .cachedCount(5)
    .scrollBar(BarState.Off)
  }

  /** 分组键含汇总与笔数；同日新增、删除或金额修改均会获得新的分组节点。 */
  private groupKeyOf(group: TxGroup): string {
    return 'grp_' + group.label + '_' + group.expense.toString() +
      '_' + group.income.toString() + '_' + group.items.length.toString();
  }

  @Builder
  private groupHeader(group: TxGroup) {
    TxDayGroupHeader({ group: group })
  }

  @Builder
  private swipeButtons(tx: Transaction) {
    Row() {
      if (tx.type !== TxType.TRANSFER) {
        Button($r('app.string.common_edit'))
          .width(SWIPE_BUTTON_WIDTH)
          .height('100%')
          .backgroundColor(palette(this.isDark).primary)
          .fontColor('#FFFFFF')
          .onClick(() => { this.onEdit(tx); })
      }
      Button($r('app.string.common_delete'))
        .width(SWIPE_BUTTON_WIDTH)
        .height('100%')
        .backgroundColor(palette(this.isDark).danger)
        .fontColor('#FFFFFF')
        .onClick(() => { this.onDelete(tx); })
    }
  }

  private emptyDisplay(tx: Transaction): TxDisplayItem {
    const d: TxDisplayItem = new TxDisplayItem();
    d.tx = tx;
    return d;
  }
}
