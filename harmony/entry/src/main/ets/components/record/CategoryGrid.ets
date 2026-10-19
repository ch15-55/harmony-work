/**
 * 模块职责：分类 4 列宫格（架构 T04 record/CategoryGrid）。
 * - 数据：Category[]（页面/ViewModel 按当前类型加载），末尾固定「更多」格
 * - 选中态：圆底实色填充当前类型强调色 + 名称同色；未选中统一中性底
 * - 图标：系统矢量符号（HM Symbol），单色随主题着色，自定义分类回退 more
 * - 空状态：仅渲染「更多」格（用户清空自定义分类时仍可跳转管理页）
 */
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';
import { Category } from '../../model/Category';
import { categorySymbolRes } from '../../constants/IconConstants';

/** 宫格数据项：分类实体 + 末尾「更多」哨兵（id=-1） */
const MORE_SENTINEL_ID: number = -1;

@Component
export struct CategoryGrid {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 可选分类列表 */
  @Prop categories: Category[] = [];
  /** 当前选中分类 id（0=未选） */
  @Prop selectedId: number = 0;
  /**
   * 选中态强调色（由页面传入当前类型色：支出红/收入绿/转账紫）。
   * 为空时回退到主色，保证单色场景不依赖外部注入。
   */
  @Prop accentColor: string = '';
  /** 选中分类回调 */
  onSelect?: (categoryId: number) => void;
  /** 点击「更多」回调（页面跳转分类管理） */
  onMore?: () => void;

  build() {
    Grid() {
      ForEach(this.categories, (category: Category) => {
        GridItem() {
          this.categoryCell(category.id, category.name, category.icon)
        }
      }, (category: Category) => 'cat_' + category.id.toString())

      GridItem() {
        this.categoryCell(MORE_SENTINEL_ID, $r('app.string.record_category_more'), 'ic_cat_more')
      }
    }
    .columnsTemplate('1fr 1fr 1fr 1fr')
    .columnsGap($r('app.float.space_sm'))
    .rowsGap($r('app.float.space_md'))
    .width('100%')
  }

  /** 选中态强调色：注入优先，回退主色 */
  private activeAccent(): string {
    return this.accentColor.length > 0 ? this.accentColor : palette(this.isDark).primary;
  }

  /** 单元格：more 哨兵时点击走 onMore；无圆底符号 + 分类名，选中黑圆白标 */
  @Builder
  private categoryCell(id: number, name: string | Resource, iconKey: string) {
    Column({ space: 6 }) {
      Stack() {
        // 恒绘占位：选中实心黑圆，未选中透明（保证行高稳定不塌陷）
        Circle()
          .width(48)
          .height(48)
          .fill(id === this.selectedId ? this.activeAccent() : Color.Transparent)
        SymbolGlyph(categorySymbolRes(iconKey))
          .fontSize(22)
          .fontColor([id === this.selectedId
            ? '#FFFFFF'
            : palette(this.isDark).textPrimary])
      }

      Text(name)
        .fontSize($r('app.float.font_aux'))
        .fontWeight(id === this.selectedId ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(id === this.selectedId
          ? this.activeAccent()
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
