/**
 * 模块职责：首页（架构 T05 / PRD 5.3 P1）。
 * 组装 LedgerSwitcher / AssetCard / MonthSummaryCard / BudgetProgressCard / RecentListCard，
 * 并通过 @StorageLink('dataVersion') @Watch 实现记账后自动刷新（架构 1.4 唯一刷新机制），
 * onPageShow 兜底重载。三态：加载 / 异常 / 正常。
 */
import { router } from '@kit.ArkUI';
import { palette } from '../constants/ThemeConstants';
import { AppStorageKeys, AppConstants } from '../constants/AppConstants';
import { RouteConstants } from '../constants/RouteConstants';
import { HomeViewModel, HomeData } from '../viewmodel/HomeViewModel';
import { LedgerSwitcher } from '../components/home/LedgerSwitcher';
import { AssetCard } from '../components/home/AssetCard';
import { MonthSummaryCard } from '../components/home/MonthSummaryCard';
import { BudgetProgressCard } from '../components/home/BudgetProgressCard';
import { RecentListCard } from '../components/home/RecentListCard';
import { InputDialog } from '../components/common/InputDialog';
import { LoadingState } from '../components/common/LoadingState';
import { ErrorState } from '../components/common/ErrorState';
import { LedgerService } from '../service/LedgerService';
import { LedgerViewModel } from '../viewmodel/LedgerViewModel';
import { Result } from '../constants/AppConstants';
import { ToastUtil } from '../utils/ToastUtil';
import { LogUtil } from '../utils/LogUtil';

@Entry
@Component
export struct HomePage {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  @StorageLink(AppStorageKeys.DATA_VERSION) @Watch('onDataChanged') dataVersion: number = 0;
  @StorageLink(AppStorageKeys.ACTIVE_TAB) @Watch('onActiveTabChanged') activeTab: number = 0;

  @State private data: HomeData | null = null;
  @State private loading: boolean = false;
  @State private errorMsg: string = '';

  /** 新建账本弹窗（LedgerSwitcher 的「新建账本」入口拉起） */
  private createLedgerDialog: CustomDialogController = new CustomDialogController({
    builder: InputDialog({
      title: $r('app.string.ledger_create_title'),
      placeholder: $r('app.string.ledger_name_hint'),
      initialValue: '',
      maxLength: 20,
      confirmText: $r('app.string.ledger_create_action'),
      onConfirmed: (text: string): void => {
        this.onCreateLedger(text);
      }
    }),
    autoCancel: true,
    customStyle: false
  });

  /** 新建账本（LedgerService 内部已含播种：新账本建完即可记账；创建后自动切换） */
  private async onCreateLedger(name: string): Promise<void> {
    const result: Result<number> = await LedgerViewModel.createLedger(name, '', '');
    if (result.ok && result.data !== undefined) {
      // 建完即用：switchTo 持久化 + bump 驱动全站按新账本刷新（service 层触发）
      await LedgerService.switchTo(result.data);
      ToastUtil.showRes($r('app.string.ledger_create_success'));
    } else {
      ToastUtil.show(result.message !== undefined ? result.message : '');
    }
  }

  /** 本页在 Tabs 中的下标（门控 bump 并发重载用） */
  private static readonly TAB_INDEX: number = 0;
  /** 加载序号：只有最新一次加载的响应生效（防 bump 重载被守卫吞掉 / 乱序覆盖） */
  private loadSeq: number = 0;
  /** 是否已加载过：避免 aboutToAppear 与 onPageShow 重复加载 */
  private loadedOnce: boolean = false;
  /** 不可见期间发生过 bump：切回本 Tab 时再加载，避免保存瞬间并发全量 SQL */
  private pendingReload: boolean = false;

  /** 切到本 Tab：启动首次加载 / 补执行不可见期间的 bump 重载（Tab 切换不触发 onPageShow） */
  private onActiveTabChanged(): void {
    if (this.activeTab === HomePage.TAB_INDEX && (this.pendingReload || !this.loadedOnce)) {
      this.pendingReload = false;
      this.loadedOnce = true;
      this.load();
    }
  }

  /** 数据版本变化：仅当前可见 Tab 真正重载，其余置脏标记 */
  onDataChanged(): void {
    if (this.activeTab === HomePage.TAB_INDEX) {
      this.load();
    } else {
      this.pendingReload = true;
    }
  }

  onPageShow(): void {
    if (this.pendingReload || !this.loadedOnce) {
      this.pendingReload = false;
      this.loadedOnce = true;
      this.load();
    }
  }

  aboutToAppear(): void {
    if (this.activeTab === HomePage.TAB_INDEX) {
      this.loadedOnce = true;
      this.load();
    }
  }

  private async load(): Promise<void> {
    const seq: number = ++this.loadSeq;
    this.loading = true;
    this.errorMsg = '';
    try {
      const result: HomeData = await HomeViewModel.load();
      if (seq !== this.loadSeq) {
        return; // 已有更新的加载在途，丢弃过期响应
      }
      this.data = result;
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

  /** 触发 @State 重新渲染（@State 仅观察引用变化） */
  private commit(): void {
    if (this.data !== null) {
      this.data = this.data.clone();
    }
  }

  private async onToggleHide(): Promise<void> {
    if (this.data === null) {
      return;
    }
    const next: boolean = await HomeViewModel.toggleAmountHidden();
    this.data.amountHidden = next;
    this.commit();
  }

  build() {
    Column() {
      // 顶部账本切换器（v1.1 多账本：下拉切换 / 新建 / 管理入口）
      if (this.data !== null) {
        LedgerSwitcher({
          ledgerName: this.data.ledgerName,
          onSwitch: (ledgerId: number): void => {
            // switchTo 内部校验 + 持久化 + DataBus.bump，页面 @Watch 自动重载
            LedgerService.switchTo(ledgerId)
              .catch((e: Object) => {
                LogUtil.e('HomePage', 'switchTo failed: ' + (e as Error).message);
              });
          },
          onCreate: (): void => {
            this.createLedgerDialog.open();
          },
          onManage: (): void => {
            router.pushUrl({ url: RouteConstants.LEDGER_MANAGE })
              .catch((e: Object) => {
                LogUtil.e('HomePage', 'pushUrl LEDGER_MANAGE failed');
              });
          }
        })
          .margin({ top: 8, bottom: 4 })
      }

      if (this.loading && this.data === null) {
        LoadingState({ rows: 4, rowHeight: 80 })
      } else if (this.errorMsg.length > 0) {
        ErrorState({
          onRetry: (): void => {
            this.load();
          }
        })
      } else if (this.data !== null) {
        this.content()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).bgPage)
    .padding({ left: 16, right: 16 })
  }

  /**
   * 内容区（无参 Builder：直接绑定 this.data）。
   * ⚠️ ArkUI 铁律：@Builder 按值传参不随状态刷新，必须引用 this.* 保持响应式。
   */
  @Builder
  private content() {
    Scroll() {
      Column({ space: 12 }) {
        AssetCard({
          summary: this.data!.asset,
          hidden: this.data!.amountHidden,
          onToggleHide: (): void => {
            this.onToggleHide();
          }
        })

        MonthSummaryCard({
          summary: this.data!.monthSummary,
          monthLabel: this.data!.monthKey
        })

        BudgetProgressCard({
          progress: this.data!.budget,
          animate: true,
          onGoSetting: (): void => {
            router.pushUrl({ url: RouteConstants.BUDGET_SETTING });
          }
        })

        RecentListCard({
          items: this.data!.recent,
          onItemClick: (txId: number): void => {
            router.pushUrl({ url: RouteConstants.TX_DETAIL, params: { txId: txId } });
          },
          onViewAll: (): void => {
            router.pushUrl({ url: RouteConstants.RECORDS });
          }
        })

        Blank().height(16)
      }
      .padding({ top: 8, bottom: 8 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }
}
