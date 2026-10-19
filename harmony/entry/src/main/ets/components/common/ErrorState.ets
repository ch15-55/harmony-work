/**
 * 模块职责：统一异常态（架构 9.6）。
 * 加载失败时渲染「图标 + 文案 + 重试」，重试动作由页面回调实现。
 */
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';

@Component
export struct ErrorState {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 异常标题 */
  @Prop title: string | Resource = $r('app.string.common_error_title');
  /** 异常描述 */
  @Prop message: string | Resource = $r('app.string.common_error_desc');
  /** 重试回调 */
  onRetry?: () => void;

  build() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
        .fontSize(48)
        .fontColor([palette(this.isDark).warning])
        .opacity(0.7)

      Text(this.title)
        .fontSize($r('app.float.font_body'))
        .fontColor(palette(this.isDark).textPrimary)
        .textAlign(TextAlign.Center)

      Text(this.message)
        .fontSize($r('app.float.font_aux'))
        .fontColor(palette(this.isDark).textSecondary)
        .textAlign(TextAlign.Center)

      if (this.onRetry !== undefined) {
        Text($r('app.string.common_retry'))
          .fontSize($r('app.float.font_body'))
          .fontColor(palette(this.isDark).primary)
          .borderRadius($r('app.float.radius_button'))
          .borderWidth(1)
          .borderColor(palette(this.isDark).primary)
          .padding({ left: 24, right: 24, top: 8, bottom: 8 })
          .margin({ top: 8 })
          .onClick(() => {
            this.fireRetry();
          })
      }
    }
    .width('100%')
    .padding({ top: 48, bottom: 48, left: 24, right: 24 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private fireRetry(): void {
    const cb: (() => void) | undefined = this.onRetry;
    if (cb !== undefined) {
      cb();
    }
  }
}
