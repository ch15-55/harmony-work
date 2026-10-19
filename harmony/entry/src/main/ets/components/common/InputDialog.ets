/**
 * 模块职责：单行文本输入弹窗（components/common/InputDialog.ets）。
 * 用于新建账本 / 重命名账本等需要用户输入简短文本的场景。
 * @CustomDialog 用法（页面内）：
 *   dialogController: CustomDialogController = new CustomDialogController({
 *     builder: InputDialog({
 *       title: ..., placeholder: ..., initialValue: this.inputText,
 *       onConfirmed: (text: string) => { ... }
 *     }),
 *     autoCancel: true, customStyle: false
 *   })
 * initialValue 传 @State 变量：每次 open 前先更新该变量，@Prop @Watch 会同步到输入框。
 */
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';

@CustomDialog
export struct InputDialog {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** CustomDialog 控制器（框架注入，勿手动赋值） */
  controller?: CustomDialogController;
  /** 标题 */
  title: string | Resource = '';
  /** 输入框占位文案 */
  placeholder: string | Resource = '';
  /** 初始文本（父组件 @State 驱动，open 前更新即可生效） */
  @Prop @Watch('onInitialChanged') initialValue: string = '';
  /** 最大输入长度 */
  @Prop maxLength: number = 20;
  /** 确认按钮文案 */
  confirmText: string | Resource = $r('app.string.common_confirm');
  /** 确认回调（弹窗自动关闭后触发，携带去首尾空格的输入值） */
  onConfirmed?: (text: string) => void;
  @State private text: string = '';

  aboutToAppear(): void {
    this.text = this.initialValue;
  }

  /** 父组件在 open() 前更新 initialValue 时同步输入框 */
  onInitialChanged(): void {
    this.text = this.initialValue;
  }

  private confirm(): void {
    const trimmed: string = this.text.trim();
    if (trimmed.length === 0) {
      return;
    }
    if (this.controller !== undefined) {
      this.controller.close();
    }
    if (this.onConfirmed !== undefined) {
      this.onConfirmed(trimmed);
    }
  }

  build() {
    Column({ space: 16 }) {
      Text(this.title)
        .fontSize($r('app.float.font_title'))
        .fontWeight(FontWeight.Medium)
        .fontColor(palette(this.isDark).textPrimary)

      TextInput({ text: this.text, placeholder: this.placeholder })
        .maxLength(this.maxLength)
        .fontSize($r('app.float.font_body'))
        .fontColor(palette(this.isDark).textPrimary)
        .placeholderColor(palette(this.isDark).textTertiary)
        .backgroundColor(palette(this.isDark).bgPage)
        .borderRadius($r('app.float.radius_button'))
        .onChange((value: string) => {
          this.text = value;
        })
        .onSubmit(() => {
          this.confirm();
        })

      Row({ space: 12 }) {
        Text($r('app.string.common_cancel'))
          .fontSize($r('app.float.font_body'))
          .fontColor(palette(this.isDark).textPrimary)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .padding({ top: 11, bottom: 11 })
          .borderRadius($r('app.float.radius_button'))
          .backgroundColor(palette(this.isDark).bgPage)
          .onClick(() => {
            if (this.controller !== undefined) {
              this.controller.close();
            }
          })

        Text(this.confirmText)
          .fontSize($r('app.float.font_body'))
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .padding({ top: 11, bottom: 11 })
          .borderRadius($r('app.float.radius_button'))
          .backgroundColor(palette(this.isDark).primary)
          .opacity(this.text.trim().length === 0 ? 0.5 : 1)
          .onClick(() => {
            this.confirm();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 24, bottom: 20 })
    .backgroundColor(palette(this.isDark).bgElevated)
    .borderRadius($r('app.float.radius_card'))
  }
}
