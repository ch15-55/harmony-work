/**
 * 模块职责：我的页（架构 T05 填充业务 UI，PRD 5.3 P5 / F-7.1 ~ F-7.9，v1.1 T04 增量）。
 * - 用 SettingItem 组装 4 组设置：账本与账户 / 数据与备份 / 通用 / 关于与帮助
 * - 当前值展示（账本数、账户数、分类数、预算、提醒、应用锁、主题与货币）来自 MineViewModel.loadSummary()
 * - 跳转一律 RouteConstants；v1.1 能力（账本管理 / 备份恢复）均为真实入口
 * - 三态齐全：LoadingState / ErrorState（汇总失败可重试）
 * - 刷新：@StorageLink(dataVersion) @Watch + onPageShow（设置页返回后当前值同步）
 */
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { palette } from '../constants/ThemeConstants';
import { AppStorageKeys, ThemeMode } from '../constants/AppConstants';
import { RouteConstants } from '../constants/RouteConstants';
import { MineSummary, MineViewModel } from '../viewmodel/MineViewModel';
import { SettingItem } from '../components/common/SettingItem';
import { ErrorState } from '../components/common/ErrorState';
import { LoadingState } from '../components/common/LoadingState';
import { MoneyUtil } from '../utils/MoneyUtil';
import { LogUtil } from '../utils/LogUtil';

@Entry
@Component
export struct MinePage {
  private static readonly TAG: string = 'MinePage';
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  @StorageLink(AppStorageKeys.DATA_VERSION) @Watch('onDataVersionChanged') dataVersion: number = 0;
  @StorageLink(AppStorageKeys.ACTIVE_TAB) @Watch('onActiveTabChanged') activeTab: number = 0;
  @State private summary: MineSummary = new MineSummary();
  @State private loading: boolean = true;
  @State private loadFailed: boolean = false;
  /** 本页在 Tabs 中的下标（门控 bump 并发重载用） */
  private static readonly TAB_INDEX: number = 4;
  /** 是否已加载过：避免 aboutToAppear 与 onPageShow 重复加载 */
  private loadedOnce: boolean = false;
  /** 不可见期间发生过 bump：切回本 Tab 时再加载，避免保存瞬间并发全量 SQL */
  private pendingReload: boolean = false;

  aboutToAppear(): void {
    if (this.activeTab === MinePage.TAB_INDEX) {
      this.loadedOnce = true;
      this.loadData();
    }
  }

  onPageShow(): void {
    if (this.pendingReload || !this.loadedOnce) {
      this.pendingReload = false;
      this.loadedOnce = true;
      this.loadData();
    }
  }

  /** 切到本 Tab：启动首次加载 / 补执行不可见期间的 bump 重载（Tab 切换不触发 onPageShow） */
  private onActiveTabChanged(): void {
    if (this.activeTab === MinePage.TAB_INDEX && (this.pendingReload || !this.loadedOnce)) {
      this.pendingReload = false;
      this.loadedOnce = true;
      this.loadData();
    }
  }

  private onDataVersionChanged(propName: string): void {
    if (this.activeTab === MinePage.TAB_INDEX) {
      this.loadData();
    } else {
      this.pendingReload = true;
    }
  }

  /** 资源 → 纯文本（SettingItem 的 valueText 是 string，需先取值） */
  private resText(res: Resource): string {
    const context: common.Context = getContext(this) as common.Context;
    return context.resourceManager.getStringSync(res);
  }

  private async loadData(): Promise<void> {
    this.loading = true;
    this.loadFailed = false;
    try {
      const result: MineSummary = await MineViewModel.loadSummary();
      this.summary = result;
      this.loadFailed = false;
    } catch (e) {
      LogUtil.e(MinePage.TAG, 'loadSummary failed');
      this.loadFailed = true;
    }
    this.loading = false;
  }

  /** 统一跳转（失败只记日志，不打扰用户） */
  private go(url: string): void {
    router.pushUrl({ url: url })
      .catch((e: Object) => {
        LogUtil.e(MinePage.TAG, 'pushUrl failed: ' + url);
      });
  }

  /** 「N 个」 */
  private countValue(count: number): string {
    return count.toString() + ' ' + this.resText($r('app.string.mine_unit_count'));
  }

  /** 预算当前值：已设置显示金额，否则「未设置」 */
  private budgetValue(): string {
    if (this.summary.budgetSet && this.summary.budgetAmount > 0) {
      return MoneyUtil.display(this.summary.budgetAmount);
    }
    return this.resText($r('app.string.mine_value_not_set'));
  }

  /** 应用锁当前值 */
  private lockValue(): string {
    return this.summary.settings.lockEnabled
      ? this.resText($r('app.string.mine_value_on'))
      : this.resText($r('app.string.mine_value_off'));
  }

  /** 主题与货币当前值：「跟随系统 · ¥」 */
  private themeValue(): string {
    let themeText: string = this.resText($r('app.string.mine_theme_system'));
    if (this.summary.themeMode === ThemeMode.LIGHT) {
      themeText = this.resText($r('app.string.mine_theme_light'));
    } else if (this.summary.themeMode === ThemeMode.DARK) {
      themeText = this.resText($r('app.string.mine_theme_dark'));
    }
    return themeText + ' · ' + this.summary.settings.currency;
  }

  /** 分组标题 */
  @Builder
  private groupTitle(title: Resource) {
    Text(title)
      .fontSize($r('app.float.font_aux'))
      .fontColor(palette(this.isDark).textSecondary)
      .width('100%')
      .padding({ left: 4, top: 12, bottom: 6 })
  }

  /** 账本与账户 */
  @Builder
  private ledgerGroup() {
    Column() {
      SettingItem({
        iconKey: 'ic_common_book',
        title: $r('app.string.mine_ledger_manage'),
        valueText: this.countValue(this.summary.ledgerCount),
        showDivider: true,
        onItemClick: (): void => {
          this.go(RouteConstants.LEDGER_MANAGE);
        }
      })
      SettingItem({
        iconKey: 'ic_common_wallet',
        title: $r('app.string.mine_account_manage'),
        valueText: this.countValue(this.summary.accountCount),
        showDivider: true,
        onItemClick: (): void => {
          this.go(RouteConstants.ACCOUNT_MANAGE);
        }
      })
      SettingItem({
        iconKey: 'ic_cat_more',
        title: $r('app.string.mine_category_manage'),
        valueText: this.countValue(this.summary.categoryCount),
        showDivider: true,
        onItemClick: (): void => {
          this.go(RouteConstants.CATEGORY_MANAGE);
        }
      })
      SettingItem({
        iconKey: 'ic_cat_gift',
        title: $r('app.string.mine_budget_manage'),
        valueText: this.budgetValue(),
        showDivider: false,
        onItemClick: (): void => {
          this.go(RouteConstants.BUDGET_SETTING);
        }
      })
    }
    .width('100%')
    .borderRadius($r('app.float.radius_card'))
    .backgroundColor(palette(this.isDark).bgCard)
    .clip(true)
  }

  /** 数据与备份 */
  @Builder
  private dataGroup() {
    Column() {
      SettingItem({
        iconKey: 'ic_cat_reimburse',
        title: $r('app.string.mine_export'),
        valueText: '',
        showDivider: true,
        onItemClick: (): void => {
          this.go(RouteConstants.EXPORT);
        }
      })
      SettingItem({
        iconKey: 'ic_acc_other',
        title: $r('app.string.mine_backup'),
        valueText: '',
        showDivider: true,
        onItemClick: (): void => {
          this.go(RouteConstants.BACKUP);
        }
      })
      SettingItem({
        iconKey: 'ic_common_none',
        title: $r('app.string.mine_diagnostics'),
        valueText: '',
        showDivider: false,
        onItemClick: (): void => {
          this.go(RouteConstants.DIAGNOSTICS);
        }
      })
    }
    .width('100%')
    .borderRadius($r('app.float.radius_card'))
    .backgroundColor(palette(this.isDark).bgCard)
    .clip(true)
  }

  /** 通用 */
  @Builder
  private generalGroup() {
    Column() {
      SettingItem({
        iconKey: 'ic_acc_credit',
        title: $r('app.string.mine_applock'),
        valueText: this.lockValue(),
        showDivider: true,
        onItemClick: (): void => {
          this.go(RouteConstants.APPLOCK_SETTING);
        }
      })
      SettingItem({
        iconKey: 'ic_cat_daily',
        title: $r('app.string.mine_theme'),
        valueText: this.themeValue(),
        showDivider: false,
        onItemClick: (): void => {
          this.go(RouteConstants.THEME_SETTING);
        }
      })
    }
    .width('100%')
    .borderRadius($r('app.float.radius_card'))
    .backgroundColor(palette(this.isDark).bgCard)
    .clip(true)
  }

  /** 关于与帮助（v1.1：意见反馈入口已移除，反馈邮箱保留在隐私政策/用户协议文本中） */
  @Builder
  private aboutGroup() {
    Column() {
      SettingItem({
        iconKey: 'ic_cat_edu',
        title: $r('app.string.mine_privacy'),
        valueText: '',
        showDivider: true,
        onItemClick: (): void => {
          this.go(RouteConstants.PRIVACY_POLICY);
        }
      })
      SettingItem({
        iconKey: 'ic_cat_edu',
        title: $r('app.string.mine_agreement'),
        valueText: '',
        showDivider: true,
        onItemClick: (): void => {
          this.go(RouteConstants.USER_AGREEMENT);
        }
      })
      SettingItem({
        iconKey: 'ic_common_none',
        title: $r('app.string.mine_about'),
        valueText: '',
        showDivider: false,
        onItemClick: (): void => {
          this.go(RouteConstants.ABOUT);
        }
      })
    }
    .width('100%')
    .borderRadius($r('app.float.radius_card'))
    .backgroundColor(palette(this.isDark).bgCard)
    .clip(true)
  }

  /** 正文（滚动区） */
  @Builder
  private contentArea() {
    Scroll() {
      Column() {
        this.groupTitle($r('app.string.mine_group_ledger'))
        this.ledgerGroup()
        this.groupTitle($r('app.string.mine_group_data'))
        this.dataGroup()
        this.groupTitle($r('app.string.mine_group_general'))
        this.generalGroup()
        this.groupTitle($r('app.string.mine_group_about'))
        this.aboutGroup()

        Text($r('app.string.mine_offline_tip'))
          .fontSize($r('app.float.font_aux'))
          .fontColor(palette(this.isDark).textTertiary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 20, bottom: 8 })
      }
      .width('100%')
      .padding({ bottom: 24 })
    }
    .layoutWeight(1)
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ left: $r('app.float.page_padding'), right: $r('app.float.page_padding') })
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.page_mine_title'))
          .fontSize($r('app.float.font_title'))
          .fontWeight(FontWeight.Medium)
          .fontColor(palette(this.isDark).textPrimary)
          .layoutWeight(1)
      }
      .width('100%')
      .height(48)
      .padding({ left: $r('app.float.page_padding'), right: $r('app.float.page_padding') })
      .alignItems(VerticalAlign.Center)

      if (this.loading) {
        // 骨架屏外层承载页面内边距（自定义组件不直接加 padding）
        Column() {
          LoadingState({ rows: 6, rowHeight: 52 })
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: $r('app.float.page_padding'), right: $r('app.float.page_padding') })
      } else if (this.loadFailed) {
        ErrorState({
          title: $r('app.string.common_error_title'),
          message: $r('app.string.common_error_desc'),
          onRetry: (): void => {
            this.loadData();
          }
        })
          .layoutWeight(1)
      } else {
        this.contentArea()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).bgPage)
  }
}
