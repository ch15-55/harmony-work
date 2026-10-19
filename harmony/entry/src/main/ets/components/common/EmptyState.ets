/**
 * 模块职责：统一空状态（架构 9.6 / F-8.6）。
 * 全站禁止白屏：任何列表/图表为空时渲染本组件。
 * 按钮动作通过回调交给页面（组件不做路由）。
 */
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';

@Component
export struct EmptyState {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 主文案（静态入参，非装饰器属性） */
  title: string | Resource = $r('app.string.common_empty_title');
  /** 副文案（可选） */
  @Prop subtitle: string = '';
  /** 图标键（已停用：简洁化不再渲染图标，参数保留兼容旧调用） */
  @Prop iconKey: string = 'ic_common_none';
  /** 按钮文案（可选） */
  @Prop buttonText: string = '';
  /** 按钮回调 */
  onButton?: () => void;

  build() {
    Column({ space: 12 }) {
      Text(this.title)
        .fontSize($r('app.float.font_body'))
        .fontColor(palette(this.isDark).textPrimary)
        .textAlign(TextAlign.Center)

      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize($r('app.float.font_aux'))
          .fontColor(palette(this.isDark).textSecondary)
          .textAlign(TextAlign.Center)
      }

      if (this.buttonText.length > 0 && this.onButton !== undefined) {
        Text(this.buttonText)
          .fontSize($r('app.float.font_body'))
          .fontColor('#FFFFFF')
          .backgroundColor(palette(this.isDark).primary)
          .borderRadius($r('app.float.radius_button'))
          .padding({ left: 24, right: 24, top: 9, bottom: 9 })
          .margin({ top: 8 })
          .onClick(() => {
            this.fireButtonTap();
          })
      }
    }
    .width('100%')
    .padding({ top: 40, bottom: 40, left: 24, right: 24 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private fireButtonTap(): void {
    const cb: (() => void) | undefined = this.onButton;
    if (cb !== undefined) {
      cb();
    }
  }
}
