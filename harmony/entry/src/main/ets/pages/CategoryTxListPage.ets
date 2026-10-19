/**
 * 模块职责：分类下钻流水列表页（架构 T05 填充业务 UI，F-4.2 环形图下钻）。
 * - 由统计页环形图/排行榜点击进入，展示某月某分类的全部流水
 * - 头部：分类名 + 该月合计 + 笔数；列表：TxListItem（点击进详情，不提供左滑）
 * - 三态齐全：LoadingState / ErrorState / EmptyState
 * - 刷新：@StorageLink(dataVersion) @Watch + onPageShow（详情页删除后回来自动更新）
 */
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { palette } from '../constants/ThemeConstants';
import { AppStorageKeys } from '../constants/AppConstants';
import { RouteConstants } from '../constants/RouteConstants';
import { CategoryTxData, RecordsViewModel } from '../viewmodel/RecordsViewModel';
import { TxDisplayItem } from '../model/StatsModels';
import { TxListItem } from '../components/list/TxListItem';
import { LazyDataSource } from '../utils/LazyDataSource';
import { NavTitleBar } from '../components/common/NavTitleBar';
import { EmptyState } from '../components/common/EmptyState';
import { ErrorState } from '../components/common/ErrorState';
import { LoadingState } from '../components/common/LoadingState';
import { MoneyUtil } from '../utils/MoneyUtil';
import { DateUtil } from '../utils/DateUtil';
import { LogUtil } from '../utils/LogUtil';
import { TxDetailParams } from './TransactionDetailPage';

/**
 * 分类下钻路由参数（统计页传入）。
 * 字段声明为可选：router.getParams() 来自运行期，缺字段时按默认值兜底，
 * 同时避免「非可选字段与 undefined 比较」的类型告警。
 */
export interface CategoryTxListParams {
  /** 月份键 'yyyy-MM' */
  monthKey?: string;
  categoryId?: number;
  /** 分类名（统计页已有，避免本页再查库） */
  categoryName?: string;
}

@Entry
@Component
export struct CategoryTxListPage {
  private static readonly TAG: string = 'CategoryTxListPage';
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  @StorageLink(AppStorageKeys.DATA_VERSION) @Watch('onDataVersionChanged') dataVersion: number = 0;
  @State private data: CategoryTxData = new CategoryTxData();
  @State private loading: boolean = true;
  @State private loadFailed: boolean = false;
  /** 流水惰性数据源：配合 LazyForEach 虚拟化长列表（某分类可能数百笔） */
  private txSource: LazyDataSource<TxDisplayItem> = new LazyDataSource<TxDisplayItem>();
  /** 路由入参 */
  @State private categoryName: string = '';
  private monthKey: string = DateUtil.monthKey(DateUtil.now());
  private categoryId: number = 0;
  private firstShowConsumed: boolean = false;

  aboutToAppear(): void {
    const params: Object | undefined = router.getParams();
    if (params !== undefined && params !== null) {
      const typed: CategoryTxListParams = params as CategoryTxListParams;
      if (typed.monthKey !== undefined && typed.monthKey.length > 0) {
        this.monthKey = typed.monthKey;
      }
      if (typed.categoryId !== undefined) {
        this.categoryId = typed.categoryId;
      }
      if (typed.categoryName !== undefined) {
        this.categoryName = typed.categoryName;
      }
    }
    this.loadData();
  }

  onPageShow(): void {
    if (!this.firstShowConsumed) {
      this.firstShowConsumed = true;
      return;
    }
    this.loadData();
  }

  private onDataVersionChanged(propName: string): void {
    this.loadData();
  }

  /** 资源 → 纯文本 */
  private resText(res: Resource): string {
    const context: common.Context = getContext(this) as common.Context;
    return context.resourceManager.getStringSync(res);
  }

  private async loadData(): Promise<void> {
    if (this.categoryId <= 0) {
      this.loading = false;
      this.data = new CategoryTxData();
      return;
    }
    this.loading = true;
    this.loadFailed = false;
    try {
      const result: CategoryTxData = await RecordsViewModel.loadByCategory(this.monthKey, this.categoryId);
      this.txSource.replace(result.items);
      this.data = result;
      this.loadFailed = false;
    } catch (e) {
      LogUtil.e(CategoryTxListPage.TAG, 'loadData failed');
      this.loadFailed = true;
    }
    this.loading = false;
  }

  /** 标题：优先分类名，缺失时回落页面标题 */
  private titleText(): string {
    if (this.categoryName.length > 0) {
      return this.categoryName;
    }
    return this.resText($r('app.string.page_category_tx_list_title'));
  }

  /** 月份标签 '2026年5月' */
  private monthLabel(): string {
    return DateUtil.monthLabel(DateUtil.monthKeyToStart(this.monthKey));
  }

  /** 「共 N 笔」 */
  private countText(): string {
    return this.resText($r('app.string.common_total_prefix')) + ' ' +
      this.data.count.toString() + ' ' +
      this.resText($r('app.string.common_count_suffix'));
  }

  private openDetail(txId: number): void {
    const params: TxDetailParams = { txId: txId };
    router.pushUrl({ url: RouteConstants.TX_DETAIL, params: params })
      .catch((e: Object) => {
        LogUtil.e(CategoryTxListPage.TAG, 'pushUrl TX_DETAIL failed');
      });
  }

  /** 汇总头卡 */
  @Builder
  private summaryCard() {
    Column({ space: 6 }) {
      Row() {
        Text(this.monthLabel())
          .fontSize($r('app.float.font_aux'))
          .fontColor(palette(this.isDark).textSecondary)
          .layoutWeight(1)
        Text(this.countText())
          .fontSize($r('app.float.font_aux'))
          .fontColor(palette(this.isDark).textTertiary)
      }
      .width('100%')

      Row({ space: 8 }) {
        Text($r('app.string.stats_center_total'))
          .fontSize($r('app.float.font_aux'))
          .fontColor(palette(this.isDark).textSecondary)
        Text(MoneyUtil.display(this.data.total))
          .fontSize($r('app.float.font_amount'))
          .fontWeight(FontWeight.Medium)
          .fontColor(palette(this.isDark).textPrimary)
          .fontFeature('"tnum" on')
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding($r('app.float.card_padding'))
    .borderRadius($r('app.float.radius_card'))
    .backgroundColor(palette(this.isDark).bgCard)
  }

  /** 列表区 */
  @Builder
  private listArea() {
    List({ space: 2 }) {
      LazyForEach(this.txSource, (item: TxDisplayItem) => {
        ListItem() {
          TxListItem({
            item: item,
            swipeEnabled: false,
            onItemClick: (txId: number): void => {
              this.openDetail(txId);
            }
          })
        }
      }, (item: TxDisplayItem) => 'cat_tx_' + item.tx.id.toString() + '_' +
      item.tx.updatedAt.toString())
    }
    .layoutWeight(1)
    .width('100%')
    .cachedCount(5)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  build() {
    Column() {
      NavTitleBar({
        title: this.titleText(),
        showBack: true,
        onBack: (): void => {
          router.back();
        }
      })

      Column() {
        this.summaryCard()
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
          LoadingState({ rows: 6, rowHeight: 64 })
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
      } else if (this.data.items.length === 0) {
        EmptyState({ title: $r('app.string.list_empty_month'), iconKey: 'ic_common_book' })
          .layoutWeight(1)
      } else {
        Column() {
          this.listArea()
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: $r('app.float.page_padding'), right: $r('app.float.page_padding') })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).bgPage)
  }
}
