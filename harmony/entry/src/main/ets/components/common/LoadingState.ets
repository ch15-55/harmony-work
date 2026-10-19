/**
 * 模块职责：统一加载态（架构 9.6：骨架块，不转圈，观感更好）。
 * rows 控制骨架行数，页面首次加载时替换列表区域渲染。
 */
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';

@Component
export struct LoadingState {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 骨架行数 */
  @Prop rows: number = 4;
  /** 骨架块高度（vp） */
  @Prop rowHeight: number = 56;

  build() {
    Column({ space: 12 }) {
      ForEach(this.skeletonIndexes(), (item: number) => {
        Row({ space: 12 }) {
          // 圆形图标占位
          Circle()
            .width(40)
            .height(40)
            .fill(palette(this.isDark).divider)
          // 文本占位
          Column({ space: 8 }) {
            Row()
              .width('60%')
              .height(14)
              .borderRadius(4)
              .backgroundColor(palette(this.isDark).divider)
            Row()
              .width('40%')
              .height(12)
              .borderRadius(4)
              .backgroundColor(palette(this.isDark).divider)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .height(this.rowHeight)
        .padding($r('app.float.card_padding'))
        .borderRadius($r('app.float.radius_card'))
        .backgroundColor(palette(this.isDark).bgCard)
      }, (item: number) => 'skeleton_' + item.toString())
    }
    .width('100%')
  }

  /** 生成骨架行下标数组（ForEach 需要） */
  private skeletonIndexes(): number[] {
    const result: number[] = [];
    const count: number = this.rows > 0 ? this.rows : 1;
    for (let i = 0; i < count; i++) {
      result.push(i);
    }
    return result;
  }
}
