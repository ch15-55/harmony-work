/**
 * 模块职责：统计页（架构 T05 填充业务 UI，PRD 5.3 P4 / F-4.1 ~ F-4.4）。
 * - 月份切换 + 月度三数字（复用 MonthSwitcher）
 * - 总计卡：当前账本全部时间累计支出 / 收入 / 结余（getGrandTotal）
 * - 支出/收入口径切换（本页自绘二态胶囊，取色一律走 palette）
 * - DonutChart 分类占比（点击扇区下钻 CategoryTxListPage）
 * - BarRankList 分类排行（点击同样下钻）
 * - BarChart 近 6 月收支趋势双柱状图（F-4.4，点击柱组切换到该月）
 * - 三态齐全：LoadingState / ErrorState / EmptyState（无数据月）
 */
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { palette, cardShadow, cardBorderWidth } from '../constants/ThemeConstants';
import { AppConstants, AppStorageKeys, CategoryType } from '../constants/AppConstants';
import { RouteConstants } from '../constants/RouteConstants';
import { StatsData, StatsViewModel } from '../viewmodel/StatsViewModel';
import { CategorySlice } from '../model/StatsModels';
import { MonthSwitcher } from '../components/list/MonthSwitcher';
import { DonutChart } from '../components/chart/DonutChart';
import { BarRankList } from '../components/chart/BarRankList';
import { BarChart } from '../components/chart/BarChart';
import { EmptyState } from '../components/common/EmptyState';
import { ErrorState } from '../components/common/ErrorState';
import { LoadingState } from '../components/common/LoadingState';
import { MoneyUtil } from '../utils/MoneyUtil';
import { DateUtil } from '../utils/DateUtil';
import { LogUtil } from '../utils/LogUtil';
import { CategoryTxListParams } from './CategoryTxListPage';

/** 环形图尺寸（vp）：Canvas 需要确定尺寸，由外层容器提供 */
const DONUT_SIZE: number = 180;
/** 总计卡收支双环尺寸（vp） */
const GRAND_DONUT_SIZE: number = 120;
/** 折线图高度（vp） */
const LINE_HEIGHT: number = 240;

@Entry
@Component
export struct StatisticsPage {
  private static readonly TAG: string = 'StatisticsPage';
  @StorageLink(AppStorageKeys.IS_DARK) @Watch('onThemeChanged') isDark: boolean = false;
  @StorageLink(AppStorageKeys.DATA_VERSION) @Watch('onDataVersionChanged') dataVersion: number = 0;
  @StorageLink(AppStorageKeys.ACTIVE_TAB) @Watch('onActiveTabChanged') activeTab: number = 0;
  @State private monthKey: string = DateUtil.monthKey(DateUtil.now());
  /**
   * 总计卡双环切片缓存。
   * 原先 grandSlices() 在 build 内每次都新建数组，DonutChart 的 @Prop 引用一变
   * 就触发 @Watch 重绘 Canvas —— 任何一次页面重渲染都会连带重绘图表。
   * 改为仅在「数据加载完成」与「主题切换」时重建。
   */
  @State private grandSlicesCache: CategorySlice[] = [];
  /** 当前口径（CategoryType.EXPENSE / INCOME） */
  @State private statsType: number = CategoryType.EXPENSE;
  @State private data: StatsData = new StatsData();
  @State private loading: boolean = true;
  @State private loadFailed: boolean = false;
  /** 是否已完成首次加载（此后 bump/切月重载不再亮骨架屏，原地刷新） */
  private firstLoaded: boolean = false;
  /** 本页在 Tabs 中的下标（门控 bump 并发重载用） */
  private static readonly TAB_INDEX: number = 3;
  /** 是否已加载过：避免 aboutToAppear 与 onPageShow 重复加载 */
  private loadedOnce: boolean = false;
  /** 不可见期间发生过 bump：切回本 Tab 时再加载，避免保存瞬间并发全量 SQL */
  private pendingReload: boolean = false;
  /** 加载序号：只有最新一次加载的响应生效（防 bump 重载与切月/切口径乱序覆盖） */
  private loadSeq: number = 0;

  aboutToAppear(): void {
    if (this.activeTab === StatisticsPage.TAB_INDEX) {
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
    if (this.activeTab === StatisticsPage.TAB_INDEX && (this.pendingReload || !this.loadedOnce)) {
      this.pendingReload = false;
      this.loadedOnce = true;
      this.loadData();
    }
  }

  private onDataVersionChanged(propName: string): void {
    if (this.activeTab === StatisticsPage.TAB_INDEX) {
      this.loadData();
    } else {
      this.pendingReload = true;
    }
  }

  /** 主题变化：总计卡双环取色依赖 palette，需重建切片缓存 */
  private onThemeChanged(): void {
    this.grandSlicesCache = this.buildGrandSlices();
  }

  /** 资源 → 纯文本 */
  private resText(res: Resource): string {
    const context: common.Context = getContext(this) as common.Context;
    return context.resourceManager.getStringSync(res);
  }

  /** 聚合加载（汇总 / 切片 / 趋势） */
  private async loadData(): Promise<void> {
    const seq: number = ++this.loadSeq;
    // 首次加载才亮骨架屏；bump/切月触发的重载保留旧内容原地刷新，避免整页闪烁
    if (!this.firstLoaded) {
      this.loading = true;
    }
    this.loadFailed = false;
    try {
      const result: StatsData = await StatsViewModel.load(this.monthKey, this.statsType,
        AppConstants.TREND_MONTHS);
      if (seq !== this.loadSeq) {
        return; // 已有更新的加载在途，丢弃过期响应
      }
      this.data = result;
      this.grandSlicesCache = this.buildGrandSlices();
      this.firstLoaded = true;
      this.loadFailed = false;
    } catch (e) {
      if (seq !== this.loadSeq) {
        return;
      }
      LogUtil.e(StatisticsPage.TAG, 'loadData failed');
      this.loadFailed = true;
    }
    if (seq === this.loadSeq) {
      this.loading = false;
    }
  }

  /** 月份切换 */
  private switchMonth(next: boolean): void {
    this.monthKey = next
      ? StatsViewModel.nextMonth(this.monthKey)
      : StatsViewModel.prevMonth(this.monthKey);
    this.loadData();
  }

  /** 口径切换（支出 / 收入） */
  private switchType(type: number): void {
    if (this.statsType === type) {
      return;
    }
    this.statsType = type;
    this.loadData();
  }

  /** 当前口径合计（分） */
  private currentTotal(): number {
    return this.statsType === CategoryType.INCOME
      ? this.data.summary.income
      : this.data.summary.expense;
  }

  /** 当前口径文案 */
  private currentTypeRes(): Resource {
    return this.statsType === CategoryType.INCOME
      ? $r('app.string.stats_type_income')
      : $r('app.string.stats_type_expense');
  }

  /** 环形图下钻：某月某分类流水 */
  private openCategoryTxList(categoryId: number): void {
    if (categoryId <= 0) {
      return;
    }
    let categoryName: string = '';
    for (let i = 0; i < this.data.slices.length; i++) {
      if (this.data.slices[i].categoryId === categoryId) {
        categoryName = this.data.slices[i].categoryName;
        break;
      }
    }
    const params: CategoryTxListParams = {
      monthKey: this.monthKey,
      categoryId: categoryId,
      categoryName: categoryName
    };
    router.pushUrl({ url: RouteConstants.CATEGORY_TX_LIST, params: params })
      .catch((e: Object) => {
        LogUtil.e(StatisticsPage.TAG, 'pushUrl CATEGORY_TX_LIST failed');
      });
  }

  /** 折线图点击：切到该月 */
  private jumpMonth(monthKey: string): void {
    if (monthKey.length === 0 || monthKey === this.monthKey) {
      return;
    }
    this.monthKey = monthKey;
    this.loadData();
  }

  /** 口径切换胶囊（二态） */
  @Builder
  private typeSwitcher() {
    Row({ space: 8 }) {
      Text($r('app.string.stats_type_expense'))
        .fontSize($r('app.float.font_aux'))
        .fontColor(this.statsType === CategoryType.EXPENSE
          ? '#FFFFFF' : palette(this.isDark).textSecondary)
        .textAlign(TextAlign.Center)
        .padding({ left: 16, right: 16, top: 6, bottom: 6 })
        .borderRadius($r('app.float.radius_button'))
        .backgroundColor(this.statsType === CategoryType.EXPENSE
          ? palette(this.isDark).expense : palette(this.isDark).bgElevated)
        .onClick(() => {
          this.switchType(CategoryType.EXPENSE);
        })

      Text($r('app.string.stats_type_income'))
        .fontSize($r('app.float.font_aux'))
        .fontColor(this.statsType === CategoryType.INCOME
          ? '#FFFFFF' : palette(this.isDark).textSecondary)
        .textAlign(TextAlign.Center)
        .padding({ left: 16, right: 16, top: 6, bottom: 6 })
        .borderRadius($r('app.float.radius_button'))
        .backgroundColor(this.statsType === CategoryType.INCOME
          ? palette(this.isDark).income : palette(this.isDark).bgElevated)
        .onClick(() => {
          this.switchType(CategoryType.INCOME);
        })
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
  }

  /** 金额字号随文本长度自适应（单元格约 1/3 行宽，超长金额缩字保证完整显示） */
  private grandFontSize(fen: number): number {
    const len: number = MoneyUtil.display(fen).length;
    if (len <= 10) {
      return 14;
    }
    if (len <= 12) {
      return 12;
    }
    return 10;
  }

  /**
   * 总计卡双环切片：支出段（红）+ 收入段（绿）。
   * 全字段显式赋值（ArkTS 禁缺省）；ratio 按支出+收入合计归一，合计为 0 时置 0
   * （两值全 0 时 DonutChart 自带灰色空环兜底）。categoryId=0 → 不可下钻。
   */
  private buildGrandSlices(): CategorySlice[] {
    const expense: number = this.data.grandTotal.expense;
    const income: number = this.data.grandTotal.income;
    const total: number = expense + income;
    const expSlice: CategorySlice = new CategorySlice();
    expSlice.categoryId = 0;
    expSlice.categoryName = this.resText($r('app.string.stats_total_expense'));
    expSlice.icon = 'ic_cat_more';
    expSlice.color = palette(this.isDark).expense;
    expSlice.amount = expense;
    expSlice.ratio = total > 0 ? expense / total : 0;
    const incSlice: CategorySlice = new CategorySlice();
    incSlice.categoryId = 0;
    incSlice.categoryName = this.resText($r('app.string.stats_total_income'));
    incSlice.icon = 'ic_cat_more';
    incSlice.color = palette(this.isDark).income;
    incSlice.amount = income;
    incSlice.ratio = total > 0 ? income / total : 0;
    const slices: CategorySlice[] = [expSlice, incSlice];
    return slices;
  }

  /**
   * 累计金额单元格（无参 Builder：直接绑定 this.data.grandTotal.*）。
   * ⚠️ ArkUI 铁律：@Builder 按值传参后状态变化不触发内部刷新，必须引用 this.* 保持响应式。
   */
  @Builder
  private grandCell(labelRes: Resource, kind: string) {
    Column({ space: 2 }) {
      Text(labelRes)
        .fontSize($r('app.float.font_aux'))
        .fontColor(palette(this.isDark).textSecondary)
      if (kind === 'expense') {
        Text(MoneyUtil.display(this.data.grandTotal.expense))
          .fontSize(this.grandFontSize(this.data.grandTotal.expense))
          .fontColor(this.data.grandTotal.expense === 0 ?
            palette(this.isDark).textSecondary : palette(this.isDark).expense)
          .fontFeature('"tnum" on')
          .maxLines(1)
      } else if (kind === 'income') {
        Text(MoneyUtil.display(this.data.grandTotal.income))
          .fontSize(this.grandFontSize(this.data.grandTotal.income))
          .fontColor(this.data.grandTotal.income === 0 ?
            palette(this.isDark).textSecondary : palette(this.isDark).income)
          .fontFeature('"tnum" on')
          .maxLines(1)
      } else {
        Text(MoneyUtil.display(this.data.grandTotal.net))
          .fontSize(this.grandFontSize(this.data.grandTotal.net))
          .fontColor(this.data.grandTotal.net === 0 ? palette(this.isDark).textSecondary :
            (this.data.grandTotal.net < 0 ? palette(this.isDark).expense : palette(this.isDark).primary))
          .fontFeature('"tnum" on')
          .maxLines(1)
      }
    }
    .alignItems(HorizontalAlign.Start)
  }

  /** 总计卡：左侧红绿收支双环（中心结余）+ 右侧累计支出/收入/结余纵排 */
  @Builder
  private totalCard() {
    Column({ space: 8 }) {
      Text($r('app.string.stats_total_title'))
        .fontSize($r('app.float.font_title'))
        .fontWeight(FontWeight.Medium)
        .fontColor(palette(this.isDark).textPrimary)
        .width('100%')

      Row({ space: 16 }) {
        // 左：红绿双环（支出红段 + 收入绿段，中心显示累计结余），不可下钻
        Column() {
          DonutChart({
            slices: this.grandSlicesCache,
            backgroundRemain: 0,
            centerText: MoneyUtil.display(this.data.grandTotal.net),
            centerSubText: this.resText($r('app.string.stats_total_net')),
            animate: true
          })
        }
        .width(GRAND_DONUT_SIZE)
        .height(GRAND_DONUT_SIZE)

        // 右：三个累计单元格纵排（label 在上、金额在下）
        Column({ space: 12 }) {
          this.grandCell($r('app.string.stats_total_expense'), 'expense')
          this.grandCell($r('app.string.stats_total_income'), 'income')
          this.grandCell($r('app.string.stats_total_net'), 'net')
        }
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding($r('app.float.card_padding'))
    .borderRadius($r('app.float.radius_card'))
    .backgroundColor(palette(this.isDark).bgCard)
    .borderWidth(cardBorderWidth(this.isDark))
    .borderColor(palette(this.isDark).border)
    .shadow(cardShadow(this.isDark))
  }

  /** 分类占比卡（环形图 + 图例，空数据走 EmptyState） */
  @Builder
  private pieCard() {
    Column({ space: 12 }) {
      Text($r('app.string.stats_pie_title'))
        .fontSize($r('app.float.font_title'))
        .fontWeight(FontWeight.Medium)
        .fontColor(palette(this.isDark).textPrimary)
        .width('100%')

      if (this.data.slices.length === 0) {
        EmptyState({ title: $r('app.string.stats_empty'), iconKey: 'ic_common_none' })
          .width('100%')
      } else {
        Column() {
          DonutChart({
            slices: this.data.slices,
            backgroundRemain: 0,
            centerText: MoneyUtil.display(this.currentTotal()),
            centerSubText: this.resText(this.currentTypeRes()),
            animate: true,
            onSliceClick: (categoryId: number): void => {
              this.openCategoryTxList(categoryId);
            }
          })
        }
        .width(DONUT_SIZE)
        .height(DONUT_SIZE)

        // 图例：色点 + 分类名 + 占比（点击同样可下钻）
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.data.slices, (slice: CategorySlice) => {
            Row({ space: 4 }) {
              Circle()
                .width(8)
                .height(8)
                .fill(slice.color)
              Text(slice.categoryName)
                .fontSize($r('app.float.font_aux'))
                .fontColor(palette(this.isDark).textSecondary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 72 })
              Text((slice.ratio * 100).toFixed(0) + '%')
                .fontSize($r('app.float.font_aux'))
                .fontColor(palette(this.isDark).textTertiary)
            }
            .padding({ right: 12, top: 4, bottom: 4 })
            .onClick(() => {
              this.openCategoryTxList(slice.categoryId);
            })
          }, (slice: CategorySlice) => 'legend_' + slice.categoryId.toString() + '_' +
            slice.amount.toString())
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding($r('app.float.card_padding'))
    .borderRadius($r('app.float.radius_card'))
    .backgroundColor(palette(this.isDark).bgCard)
    .borderWidth(cardBorderWidth(this.isDark))
    .borderColor(palette(this.isDark).border)
    .shadow(cardShadow(this.isDark))
  }

  /** 分类排行卡 */
  @Builder
  private rankCard() {
    Column({ space: 8 }) {
      Text($r('app.string.stats_rank_title'))
        .fontSize($r('app.float.font_title'))
        .fontWeight(FontWeight.Medium)
        .fontColor(palette(this.isDark).textPrimary)
        .width('100%')

      BarRankList({
        slices: this.data.slices,
        emptyText: $r('app.string.stats_empty'),
        onItemTap: (categoryId: number): void => {
          this.openCategoryTxList(categoryId);
        }
      })
    }
    .width('100%')
    .padding($r('app.float.card_padding'))
    .borderRadius($r('app.float.radius_card'))
    .backgroundColor(palette(this.isDark).bgCard)
    .borderWidth(cardBorderWidth(this.isDark))
    .borderColor(palette(this.isDark).border)
    .shadow(cardShadow(this.isDark))
  }

  /** 趋势卡（近 6 月收支双柱状图） */
  @Builder
  private trendCard() {
    Column({ space: 8 }) {
      Text($r('app.string.stats_trend_title'))
        .fontSize($r('app.float.font_title'))
        .fontWeight(FontWeight.Medium)
        .fontColor(palette(this.isDark).textPrimary)
        .width('100%')

      if (this.data.trend.length === 0) {
        EmptyState({ title: $r('app.string.stats_empty'), iconKey: 'ic_common_none' })
          .width('100%')
      } else {
        Column() {
          BarChart({
            points: this.data.trend,
            animate: true,
            onPointClick: (monthKey: string): void => {
              this.jumpMonth(monthKey);
            }
          })
        }
        .width('100%')
        .height(LINE_HEIGHT)
      }
    }
    .width('100%')
    .padding($r('app.float.card_padding'))
    .borderRadius($r('app.float.radius_card'))
    .backgroundColor(palette(this.isDark).bgCard)
    .borderWidth(cardBorderWidth(this.isDark))
    .borderColor(palette(this.isDark).border)
    .shadow(cardShadow(this.isDark))
  }

  /** 正文（滚动区） */
  @Builder
  private contentArea() {
    Scroll() {
      Column({ space: 12 }) {
        this.totalCard()
        this.pieCard()
        this.rankCard()
        this.trendCard()
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
        Text($r('app.string.page_statistics_title'))
          .fontSize($r('app.float.font_title'))
          .fontWeight(FontWeight.Medium)
          .fontColor(palette(this.isDark).textPrimary)
          .layoutWeight(1)
      }
      .width('100%')
      .height(48)
      .padding({ left: $r('app.float.page_padding'), right: $r('app.float.page_padding') })
      .alignItems(VerticalAlign.Center)

      Column({ space: 8 }) {
        MonthSwitcher({
          monthKey: this.monthKey,
          summary: this.data.summary,
          onPrev: (): void => {
            this.switchMonth(false);
          },
          onNext: (): void => {
            this.switchMonth(true);
          }
        })
        this.typeSwitcher()
      }
      .width('100%')
      .padding({
        left: $r('app.float.page_padding'),
        right: $r('app.float.page_padding'),
        bottom: 8
      })

      if (this.loading) {
        // 骨架屏外层承载页面内边距（自定义组件不直接加 padding）
        Column() {
          LoadingState({ rows: 3, rowHeight: 120 })
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
