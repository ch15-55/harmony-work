/**
 * 模块职责：应用锁设置页（架构 T05 / PRD F-7.4）。
 * - 开关：开启 → 设置 4 位 PIN（输入 + 二次确认）；关闭 → 确认后校验当前 PIN
 * - 修改密码：跳转 PinVerifyPage（旧密码校验 → 设置新密码）
 * - 忘记密码：二次确认后清空全部数据以重置（唯一重置途径）
 * - 文案全走 $r；取色全走 palette；PIN 仅经 AppLockService（零权限、SHA-256 加盐）
 */
import { router } from '@kit.ArkUI';
import { palette } from '../constants/ThemeConstants';
import { AppStorageKeys } from '../constants/AppConstants';
import { RouteConstants } from '../constants/RouteConstants';
import { AppLockService } from '../service/AppLockService';
import { MineViewModel } from '../viewmodel/MineViewModel';
import { NavTitleBar } from '../components/common/NavTitleBar';
import { SettingItem } from '../components/common/SettingItem';
import { PinLockOverlay } from '../components/common/PinLockOverlay';
import { ConfirmDialog } from '../components/common/ConfirmDialog';
import { ToastUtil } from '../utils/ToastUtil';
import { LogUtil } from '../utils/LogUtil';

@Entry
@Component
struct AppLockSettingPage {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  @State private lockEnabled: boolean = AppLockService.isEnabled();
  @State private showSetPin: boolean = false;
  @State private showVerify: boolean = false;
  @State private pin1: string = '';
  @State private pin2: string = '';

  private disableDialog: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({
      title: $r('app.string.common_confirm'),
      message: $r('app.string.applock_disable_confirm'),
      danger: false,
      onConfirmed: (): void => {
        this.showVerify = true;
      }
    }),
    autoCancel: true
  });

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

  onPageShow(): void {
    this.lockEnabled = AppLockService.isEnabled();
  }

  aboutToAppear(): void {
    this.lockEnabled = AppLockService.isEnabled();
  }

  /** 开关变化：开启走设置 PIN，关闭走确认 + 校验 */
  private onToggleLock(newVal: boolean): void {
    if (newVal) {
      this.pin1 = '';
      this.pin2 = '';
      this.showSetPin = true;
    } else {
      this.disableDialog.open();
    }
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
      this.lockEnabled = true;
      this.showSetPin = false;
      this.pin1 = '';
      this.pin2 = '';
      ToastUtil.showRes($r('app.string.applock_set_success'));
    } catch (e) {
      ToastUtil.showRes($r('app.string.toast_save_failed'));
    }
  }

  private cancelSetPin(): void {
    this.showSetPin = false;
    this.pin1 = '';
    this.pin2 = '';
  }

  /** 关闭应用锁：校验当前 PIN；通过则 disable */
  private async onSubmitVerify(pin: string): Promise<boolean> {
    const ok: boolean = await AppLockService.verifyPin(pin);
    if (ok) {
      AppLockService.disable();
      this.lockEnabled = false;
      this.showVerify = false;
    }
    return ok;
  }

  private async confirmReset(): Promise<void> {
    const result = await MineViewModel.clearAllData();
    if (result.ok) {
      AppLockService.disable();
      this.lockEnabled = false;
      ToastUtil.showRes($r('app.string.toast_delete_success'));
    } else {
      ToastUtil.showRes($r('app.string.toast_operate_failed'));
    }
  }

  build() {
    Stack() {
      Column() {
        NavTitleBar({
          title: $r('app.string.page_applock_setting_title'),
          showBack: true,
          onBack: (): void => {
            router.back();
          }
        })

        Scroll() {
          Column({ space: 12 }) {
            Text($r('app.string.applock_turn_on_tip'))
              .fontSize($r('app.float.font_aux'))
              .fontColor(palette(this.isDark).textSecondary)
              .width('100%')
              .padding({ left: 4 })

            Column() {
              SettingItem({
                iconKey: 'ic_common_none',
                title: $r('app.string.mine_applock'),
                showToggle: true,
                toggleOn: this.lockEnabled,
                showDivider: this.lockEnabled,
                onToggleChange: (on: boolean): void => {
                  this.onToggleLock(on);
                }
              })
              if (this.lockEnabled) {
                SettingItem({
                  iconKey: 'ic_common_none',
                  title: $r('app.string.applock_change_pin'),
                  onItemClick: (): void => {
                    router.pushUrl({ url: RouteConstants.PIN_VERIFY })
                      .catch((e: Object) => {
                        LogUtil.e('AppLockSettingPage', 'pushUrl PIN_VERIFY failed');
                      });
                  }
                })
              }
            }
            .width('100%')
            .borderRadius($r('app.float.radius_card'))
            .backgroundColor(palette(this.isDark).bgCard)
            .clip(true)
          }
          .width('100%')
          .padding(16)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')

      if (this.showSetPin) {
        this.setPinOverlay()
      }

      if (this.showVerify) {
        PinLockOverlay({
          onSubmit: (pin: string): Promise<boolean> => this.onSubmitVerify(pin),
          onForgot: (): void => {
            this.showVerify = false;
            this.resetDialog.open();
          },
          lockedRemainMs: (): number => AppLockService.getLockoutRemainMs()
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).bgPage)
  }

  /** 设置 / 修改 PIN 的覆盖层（两个输入框 + 确认） */
  @Builder
  private setPinOverlay() {
    Column() {
      Stack() {
        Column({ space: 16 }) {
          Text($r('app.string.applock_set_pin'))
            .fontSize($r('app.float.font_title'))
            .fontWeight(FontWeight.Medium)
            .fontColor(palette(this.isDark).textPrimary)

          TextInput({ text: this.pin1, placeholder: $r('app.string.applock_set_pin') })
            .type(InputType.Password)
            .maxLength(4)
            .width('80%')
            .textAlign(TextAlign.Center)
            .backgroundColor(palette(this.isDark).bgCard)
            .borderRadius($r('app.float.radius_button'))
            .onChange((v: string): void => {
              this.pin1 = v;
            })

          TextInput({ text: this.pin2, placeholder: $r('app.string.applock_confirm_pin') })
            .type(InputType.Password)
            .maxLength(4)
            .width('80%')
            .textAlign(TextAlign.Center)
            .backgroundColor(palette(this.isDark).bgCard)
            .borderRadius($r('app.float.radius_button'))
            .onChange((v: string): void => {
              this.pin2 = v;
            })

          Row({ space: 12 }) {
            Button($r('app.string.common_cancel'))
              .layoutWeight(1)
              .backgroundColor(palette(this.isDark).bgElevated)
              .fontColor(palette(this.isDark).textPrimary)
              .onClick((): void => {
                this.cancelSetPin();
              })
            Button($r('app.string.common_confirm'))
              .layoutWeight(1)
              .backgroundColor(palette(this.isDark).primary)
              .fontColor('#FFFFFF')
              .onClick((): void => {
                this.savePin();
              })
          }
          .width('80%')
        }
        .padding(24)
        .backgroundColor(palette(this.isDark).bgElevated)
        .borderRadius($r('app.float.radius_card'))
        .alignSelf(ItemAlign.Center)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(palette(this.isDark).mask)
    }
    .width('100%')
    .height('100%')
  }
}
