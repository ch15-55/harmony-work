/**
 * 模块职责：二次确认弹窗（架构 T01 components/common/ConfirmDialog.ets）。
 * 危险操作（删除/清空数据/忘记密码）使用：标题 + 说明 + 取消 + 红色主按钮。
 * @CustomDialog 用法（页面内）：
 *   dialogController: CustomDialogController = new CustomDialogController({
 *     builder: ConfirmDialog({
 *       title: ..., message: ...,
 *       onConfirmed: () => { ... }
 *     })
 *   })
 */
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';

@CustomDialog
export struct ConfirmDialog {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** CustomDialog 控制器（框架注入，勿手动赋值） */
  controller?: CustomDialogController;
  /** 标题（静态入参，非装饰器属性） */
  title: string | Resource = '';
  /** 说明文案（静态入参，非装饰器属性） */
  message: string | Resource = '';
  /** 确认按钮文案（静态入参，非装饰器属性） */
  confirmText: string | Resource = $r('app.string.common_confirm');
  /** 是否危险操作（确认按钮红色） */
  @Prop danger: boolean = true;
  /** 确认回调（弹窗自动关闭后触发业务动作） */
  onConfirmed?: () => void;

  build() {
    Column({ space: 16 }) {
      Text(this.title)
        .fontSize($r('app.float.font_title'))
        .fontWeight(FontWeight.Medium)
        .fontColor(palette(this.isDark).textPrimary)

      Text(this.message)
        .fontSize($r('app.float.font_body'))
        .fontColor(palette(this.isDark).textSecondary)
        .textAlign(TextAlign.Center)

      Row({ space: 12 }) {
        // 取消
        Text($r('app.string.common_cancel'))
          .fontSize($r('app.float.font_body'))
          .fontColor(palette(this.isDark).textPrimary)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .padding({ top: 11, bottom: 11 })
          .borderRadius($r('app.float.radius_button'))
          .backgroundColor(palette(this.isDark).bgPage)
          .onClick(() => {
            this.close();
          })

        // 确认（危险操作红色）
        Text(this.confirmText)
          .fontSize($r('app.float.font_body'))
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .padding({ top: 11, bottom: 11 })
          .borderRadius($r('app.float.radius_button'))
          .backgroundColor(this.danger ? palette(this.isDark).danger : palette(this.isDark).primary)
          .onClick(() => {
            this.close();
            if (this.onConfirmed !== undefined) {
              this.onConfirmed();
            }
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 24, bottom: 20 })
    .backgroundColor(palette(this.isDark).bgElevated)
    .borderRadius($r('app.float.radius_card'))
  }

  /** 关闭弹窗（controller 可能未注入，统一判空） */
  private close(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
  }
}
