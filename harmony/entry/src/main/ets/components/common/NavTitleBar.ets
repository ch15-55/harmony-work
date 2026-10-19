/**
 * 模块职责：带返回箭头的标题栏（架构 T01 components/common/NavTitleBar.ets）。
 * 返回动作通过回调交给页面处理（components 禁止 router 跳转，架构 3.1）。
 * 页面侧用法：NavTitleBar({ title: $r('app.string.page_xxx_title'), onBack: () => router.back() })
 */
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';

@Component
export struct NavTitleBar {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 状态栏高度（px，WindowUtil 冷启动写入），沉浸式布局下标题栏下移避让 */
  @StorageLink(AppStorageKeys.STATUS_BAR_HEIGHT_PX) statusBarHeightPx: number = 0;
  /** 标题（字符串或资源引用；静态入参，非装饰器属性） */
  title: string | Resource = '';
  /** 是否显示返回箭头 */
  @Prop showBack: boolean = true;
  /** 右侧动作文案（可选，字符串或资源引用） */
  @Prop actionText: string | Resource = '';
  /** 返回回调（页面实现 router.back()） */
  onBack?: () => void;
  /** 右侧动作回调 */
  onAction?: () => void;

  build() {
    Column() {
      Row() {
      Row() {
        if (this.showBack) {
          Text('‹')
            .fontSize(26)
            .fontColor(palette(this.isDark).textPrimary)
            .fontWeight(FontWeight.Medium)
            .width(32)
            .height(32)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              if (this.onBack !== undefined) {
                this.onBack();
              }
            })
        }
        Text(this.title)
          .fontSize($r('app.float.font_title'))
          .fontWeight(FontWeight.Medium)
          .fontColor(palette(this.isDark).textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: this.showBack ? 4 : 0 })
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)

      if (this.actionText !== '') {
        Text(this.actionText)
          .fontSize($r('app.float.font_body'))
          .fontColor(palette(this.isDark).primary)
          .padding({ left: 12, right: 4, top: 6, bottom: 6 })
          .onClick(() => {
            if (this.onAction !== undefined) {
              this.onAction();
            }
          })
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: $r('app.float.page_padding'), right: $r('app.float.page_padding') })
    .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ top: px2vp(this.statusBarHeightPx) })
  }
}
