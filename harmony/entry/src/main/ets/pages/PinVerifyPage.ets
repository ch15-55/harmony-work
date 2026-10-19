/**
 * 模块职责：PIN 校验页（架构 T05 / PRD F-7.4 修改 PIN 流程）。
 * 流程：校验旧 PIN（PinLockOverlay）→ 校验通过进入「设置新 PIN」→ setPin。
 * 忘记密码：二次确认后清空全部数据以重置（与 AppLockSettingPage 同口径）。
 * 文案全走 $r；取色全走 palette。
 */
import { router } from '@kit.ArkUI';
import { palette } from '../constants/ThemeConstants';
import { AppStorageKeys, AppConstants } from '../constants/AppConstants';
import { AppLockService } from '../service/AppLockService';
import { MineViewModel } from '../viewmodel/MineViewModel';
import { NavTitleBar } from '../components/common/NavTitleBar';
import { PinLockOverlay } from '../components/common/PinLockOverlay';
import { ConfirmDialog } from '../components/common/ConfirmDialog';
import { ToastUtil } from '../utils/ToastUtil';

@Entry
@Component
struct PinVerifyPage {
  /** 页面转场：二级页统一右侧滑入（v1.2 美化） */
  pageTransition() {
    PageTransitionEnter({ type: RouteType.Push, duration: 300, curve: Curve.EaseOut })
      .slide(SlideEffect.Right)
    PageTransitionExit({ type: RouteType.Pop, duration: 280, curve: Curve.EaseIn })
      .slide(SlideEffect.Right)
  }

  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 'verify' = 校验旧密码，'set' = 设置新密码 */
  @State private phase: string = 'verify';
  @State private pin1: string = '';
  @State private pin2: string = '';

  private resetDialog: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({
      title: $r('app.string.lock_forgot'),
      message: $r('app.string.lock_forgot_message'),
      danger: true,
      onConfirmed: (): void => {
        this.confirmReset();
      }
    }),
    autoCancel: true
  });

  /** 校验旧 PIN；通过则切换到设置新密码阶段 */
  private async onSubmitVerify(pin: string): Promise<boolean> {
    const ok: boolean = await AppLockService.verifyPin(pin);
    if (ok) {
      this.phase = 'set';
    }
    return ok;
  }

  private async savePin(): Promise<void> {
    if (this.pin1 !== this.pin2) {
      ToastUtil.showRes($r('app.string.applock_mismatch'));
      return;
    }
    if (!AppLockService.isValidPin(this.pin1)) {
      ToastUtil.showRes($r('app.string.toast_save_failed'));
      return;
    }
    try {
      await AppLockService.setPin(this.pin1);
      ToastUtil.showRes($r('app.string.applock_set_success'));
      router.back();
    } catch (e) {
      ToastUtil.showRes($r('app.string.toast_save_failed'));
    }
  }

  private async confirmReset(): Promise<void> {
    const result = await MineViewModel.clearAllData();
    if (result.ok) {
      AppLockService.disable();
      ToastUtil.showRes($r('app.string.toast_delete_success'));
      router.back();
    } else {
      ToastUtil.showRes($r('app.string.toast_operate_failed'));
    }
  }

  build() {
    Stack() {
      if (this.phase === 'verify') {
        PinLockOverlay({
          onSubmit: (pin: string): Promise<boolean> => this.onSubmitVerify(pin),
          onForgot: (): void => {
            this.resetDialog.open();
          },
          lockedRemainMs: (): number => AppLockService.getLockoutRemainMs()
        })

        // 返回按钮浮层（PinLockOverlay 无原生返回）
        Row({ space: 2 }) {
          Text('‹')
            .fontSize(20)
            .fontColor(palette(this.isDark).textSecondary)
          Text($r('app.string.common_back'))
            .fontSize(16)
            .fontColor(palette(this.isDark).textSecondary)
        }
        .padding({ top: 16, left: 12 })
        .onClick((): void => {
          router.back();
        })
        .alignSelf(ItemAlign.Start)
      } else {
        Column() {
          NavTitleBar({
            title: $r('app.string.applock_set_pin'),
            showBack: true,
            onBack: (): void => {
              router.back();
            }
          })

          Column({ space: 16 }) {
            Text($r('app.string.pin_verify_subtitle'))
              .fontSize($r('app.float.font_aux'))
              .fontColor(palette(this.isDark).textSecondary)
              .width('100%')
              .padding({ left: 4 })

            TextInput({ text: this.pin1, placeholder: $r('app.string.applock_set_pin') })
              .type(InputType.Password)
              .maxLength(AppConstants.PIN_LENGTH)
              .width('100%')
              .textAlign(TextAlign.Center)
              .backgroundColor(palette(this.isDark).bgCard)
              .borderRadius($r('app.float.radius_button'))
              .onChange((v: string): void => {
                this.pin1 = v;
              })

            TextInput({ text: this.pin2, placeholder: $r('app.string.applock_confirm_pin') })
              .type(InputType.Password)
              .maxLength(AppConstants.PIN_LENGTH)
              .width('100%')
              .textAlign(TextAlign.Center)
              .backgroundColor(palette(this.isDark).bgCard)
              .borderRadius($r('app.float.radius_button'))
              .onChange((v: string): void => {
                this.pin2 = v;
              })

            Button($r('app.string.common_confirm'))
              .width('100%')
              .height(48)
              .borderRadius($r('app.float.radius_button'))
              .backgroundColor(palette(this.isDark).primary)
              .fontColor('#FFFFFF')
              .onClick((): void => {
                this.savePin();
              })
          }
          .width('100%')
          .padding(16)
          .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).bgPage)
  }
}
