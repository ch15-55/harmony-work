/**
 * 模块职责：分类排行条形列表（架构 T04 BarRankList，F-4.3）。
 * 非 Canvas：Row 组合（名次 + 色点 + 名称 + 金额 + 占比 + 条形），文字排版交给系统更稳。
 * Top3 名次高亮；空数据渲染 EmptyState（全站三态要求）。
 * 简洁化：分类标识用纯色圆点（与环形图图例一致），不渲染 emoji 字形。
 */
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';
import { CategorySlice } from '../../model/StatsModels';
import { AmountText } from '../common/AmountText';
import { EmptyState } from '../common/EmptyState';

@Component
export struct BarRankList {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 排行数据（降序） */
  @Prop slices: CategorySlice[] = [];
  /** 空态文案 */
  emptyText: string | Resource = $r('app.string.stats_empty');
  /** 条目点击回调（categoryId>0 可下钻） */
  onItemTap?: (categoryId: number) => void;

  build() {
    if (this.slices.length === 0) {
      EmptyState({ title: this.emptyText, iconKey: 'ic_common_none' })
    } else {
      Column() {
        ForEach(this.slices, (slice: CategorySlice, index: number) => {
          Row({ space: 10 }) {
            // 名次（Top3 高亮）
            Text((index + 1).toString())
              .fontSize($r('app.float.font_aux'))
              .fontWeight(FontWeight.Bold)
              .fontColor(index < 3 ? palette(this.isDark).primary : palette(this.isDark).textTertiary)
              .width(18)

            // 分类色点（与环形图图例一致，简洁不抢焦点）
            Circle()
              .width(10)
              .height(10)
              .fill(slice.color)

            Text(slice.categoryName)
              .fontSize($r('app.float.font_body'))
              .fontColor(palette(this.isDark).textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width(64)

            AmountText({
              amountFen: slice.amount,
              txType: 0,
              autoColor: false,
              colorValue: palette(this.isDark).textPrimary
            })

            Text((slice.ratio * 100).toFixed(1) + '%')
              .fontSize($r('app.float.font_aux'))
              .fontColor(palette(this.isDark).textSecondary)
              .width(48)
              .textAlign(TextAlign.End)

            // 条形：宽度按占比，颜色随分类
            Row() {
              Row()
                .height(6)
                .borderRadius(3)
                .backgroundColor(slice.color)
                .width(this.barWidth(slice.ratio))
            }
            .layoutWeight(1)
            .height(6)
            .borderRadius(3)
            .backgroundColor(palette(this.isDark).chartEmpty)
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
          .onClick(() => {
            if (this.onItemTap !== undefined && slice.categoryId > 0) {
              this.onItemTap(slice.categoryId);
            }
          })
        }, (slice: CategorySlice) => 'rank_' + slice.categoryId.toString() + '_' +
          slice.amount.toString())
      }
      .width('100%')
    }
  }

  /** 条形宽度：占比 0~1 映射到 8%~100%，保证小占比也可见 */
  private barWidth(ratio: number): string {
    const clamped: number = Math.max(0, Math.min(1, ratio));
    const percent: number = 8 + clamped * 92;
    return percent.toFixed(1) + '%';
  }
}
