/**
 * 模块职责：最近记录卡（架构 T04 home/RecentListCard）。
 * - 最近 5 条（条数由 ViewModel 按 AppConstants.RECENT_COUNT 截取）
 * - 复用 list/TxListItem（swipeEnabled=false：首页卡片内不做左滑，
 *   编辑删除入口在明细页，避免双入口状态不同步）
 * - 空态：EmptyState（home_empty_recent 文案）
 */
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';
import { TxDisplayItem } from '../../model/StatsModels';
import { TxListItem } from '../list/TxListItem';
import { EmptyState } from '../common/EmptyState';

@Component
export struct RecentListCard {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 最近流水（已关联分类/账户名） */
  @Prop items: TxDisplayItem[] = [];
  /** 条目点击（进详情） */
  onItemClick?: (txId: number) => void;
  /** 「查看全部」回调 */
  onViewAll?: () => void;

  build() {
    Column({ space: 4 }) {
      Row() {
        Text($r('app.string.home_recent_title'))
          .fontSize($r('app.float.font_title'))
          .fontWeight(FontWeight.Medium)
          .fontColor(palette(this.isDark).textPrimary)
          .layoutWeight(1)

        Text($r('app.string.home_view_all'))
          .fontSize($r('app.float.font_aux'))
          .fontColor(palette(this.isDark).textSecondary)
          .onClick(() => {
            if (this.onViewAll !== undefined) {
              this.onViewAll();
            }
          })
      }
      .width('100%')
      .padding({ bottom: 8 })

      if (this.items.length === 0) {
        EmptyState({ title: $r('app.string.home_empty_recent') })
          .width('100%')
      } else {
        ForEach(this.items, (item: TxDisplayItem) => {
          TxListItem({
            item: item,
            swipeEnabled: false,
            onItemClick: (txId: number): void => {
              if (this.onItemClick !== undefined) {
                this.onItemClick(txId);
              }
            }
          })
        }, (item: TxDisplayItem) => 'recent_' + item.tx.id.toString() + '_' +
          item.tx.updatedAt.toString())
      }
    }
    .width('100%')
    .padding($r('app.float.card_padding'))
    .borderRadius($r('app.float.radius_card'))
    .backgroundColor(palette(this.isDark).bgCard)
  }
}
