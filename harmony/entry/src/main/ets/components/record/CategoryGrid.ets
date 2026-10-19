/**
 * 模块职责：分类 4 列宫格（架构 T04 record/CategoryGrid）。
 * - 数据：Category[]（页面/ViewModel 按当前类型加载），末尾固定「更多」格
 * - 选中态：主色描边 + 名称主色；色块用分类自身 color（数据驱动）
 * - 简洁化：格内不渲染图标字形，浅色圆 + 实色小点标识分类
 * - 空状态：仅渲染「更多」格（用户清空自定义分类时仍可跳转管理页）
 */
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';
import { Category } from '../../model/Category';
import { hexToRgba } from '../chart/ChartCanvasBase';

/** 宫格数据项：分类实体 + 末尾「更多」哨兵（id=-1） */
const MORE_SENTINEL_ID: number = -1;

@Component
export struct CategoryGrid {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 可选分类列表 */
  @Prop categories: Category[] = [];
  /** 当前选中分类 id（0=未选） */
  @Prop selectedId: number = 0;
  /** 选中分类回调 */
  onSelect?: (categoryId: number) => void;
  /** 点击「更多」回调（页面跳转分类管理） */
  onMore?: () => void;

  build() {
    Grid() {
      ForEach(this.categories, (category: Category) => {
      GridItem() {
        this.categoryCell(category.id, category.name, category.color)
      }
    }, (category: Category) => 'cat_' + category.id.toString())

      GridItem() {
        this.categoryCell(MORE_SENTINEL_ID, $r('app.string.record_category_more'),
          palette(this.isDark).textSecondary)
      }
    }
    .columnsTemplate('1fr 1fr 1fr 1fr')
    .columnsGap($r('app.float.space_sm'))
    .rowsGap($r('app.float.space_sm'))
    .width('100%')
  }

  /** 单元格：more 哨兵时点击走 onMore；浅色圆 + 实色小点 + 名称 */
  @Builder
  private categoryCell(id: number, name: string | Resource, color: string) {
    Column({ space: 4 }) {
      Stack() {
        Circle()
          .width(48)
          .height(48)
          .fill(id === MORE_SENTINEL_ID
            ? palette(this.isDark).bgElevated
            : hexToRgba(color, 0.16))
          .stroke(id === this.selectedId ? palette(this.isDark).primary : Color.Transparent)
          .strokeWidth(id === this.selectedId ? 2 : 0)
        if (id !== MORE_SENTINEL_ID) {
          Circle()
            .width(14)
            .height(14)
            .fill(color)
        } else {
          Text('···')
            .fontSize(14)
            .fontColor(palette(this.isDark).textSecondary)
        }
      }

      Text(name)
        .fontSize($r('app.float.font_aux'))
        .fontColor(id === this.selectedId
          ? palette(this.isDark).primary
          : palette(this.isDark).textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 64 })
    }
    .padding({ top: 6, bottom: 6 })
    .borderRadius($r('app.float.radius_tag'))
    .onClick(() => {
      if (id === MORE_SENTINEL_ID) {
        if (this.onMore !== undefined) {
          this.onMore();
        }
        return;
      }
      if (this.onSelect !== undefined) {
        this.onSelect(id);
      }
    })
  }
}
