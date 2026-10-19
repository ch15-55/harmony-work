/**
 * 模块职责：应用锁全屏 PIN 覆盖层（架构 T01 骨架 + 2.4 叠加层）。
 * - 覆盖于 Index 根 Stack 最上层（zIndex 最高），locked=true 时渲染
 * - PIN 校验通过回调交给宿主页完成（components 禁止调用 Service，架构 3.1）
 * - 等待期由宿主页通过 lockedRemainMs 回调提供，期间禁用键盘并展示剩余秒数
 * - 忘记密码：明确提示需清空全部数据以重置（文案走 string.json）
 */
import { palette } from '../../constants/ThemeConstants';
import { AppConstants, AppStorageKeys } from '../../constants/AppConstants';
import { ToastUtil } from '../../utils/ToastUtil';

@Component
export struct PinLockOverlay {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 已输入的 PIN（组件内状态） */
  @State private inputPin: string = '';
  /** 是否处于错误抖动提示态 */
  @State private showError: boolean = false;
  /** 等待期剩余毫秒（>0 时禁用输入） */
  @State private lockRemainMs: number = 0;
  /** PIN 校验回调：返回 true 表示校验通过（宿主页实现解锁） */
  onSubmit?: (pin: string) => Promise<boolean>;
  /** 忘记密码回调（宿主页弹出确认并走清空数据重置流程） */
  onForgot?: () => void;
  /** 等待期剩余毫秒提供者（宿主页读 AppLockService，组件不直接依赖 Service） */
  lockedRemainMs?: () => number;

  private countdownTimer: number = -1;

  aboutToAppear(): void {
    this.syncLockRemain();
  }

  aboutToDisappear(): void {
    this.stopCountdown();
  }

  /** 同步等待状态：有剩余则启动秒级倒计时，归零后自动恢复输入 */
  private syncLockRemain(): number {
    if (this.lockedRemainMs === undefined) {
      this.lockRemainMs = 0;
      return 0;
    }
    const remain: number = this.lockedRemainMs();
    this.lockRemainMs = remain > 0 ? remain : 0;
    if (this.lockRemainMs > 0) {
      this.startCountdown();
    } else {
      this.stopCountdown();
    }
    return this.lockRemainMs;
  }

  private startCountdown(): void {
    if (this.countdownTimer >= 0) {
      return;
    }
    this.countdownTimer = setInterval((): void => {
      const remain: number = this.lockedRemainMs !== undefined ? this.lockedRemainMs() : 0;
      this.lockRemainMs = remain > 0 ? remain : 0;
      if (this.lockRemainMs <= 0) {
        this.showError = false;
        this.stopCountdown();
      }
    }, 1000);
  }

  private stopCountdown(): void {
    if (this.countdownTimer >= 0) {
      clearInterval(this.countdownTimer);
      this.countdownTimer = -1;
    }
  }

  build() {
    Column({ space: 16 }) {
      Blank().height(64)

      Text($r('app.string.lock_title'))
        .fontSize($r('app.float.font_title'))
        .fontWeight(FontWeight.Medium)
        .fontColor(palette(this.isDark).textPrimary)

      Text($r('app.string.lock_subtitle'))
        .fontSize($r('app.float.font_aux'))
        .fontColor(palette(this.isDark).textSecondary)

      // 密码圆点
      Row({ space: 16 }) {
        ForEach(this.dotIndexes(), (item: number) => {
          Circle()
            .width(14)
            .height(14)
            .fill(this.inputPin.length > item ?
            palette(this.isDark).primary : palette(this.isDark).divider)
        }, (item: number) => 'dot_' + item.toString())
      }
      .height(24)

      if (this.lockRemainMs > 0) {
        Text($r('app.string.lock_wait_seconds', Math.ceil(this.lockRemainMs / 1000)))
          .fontSize($r('app.float.font_aux'))
          .fontColor(palette(this.isDark).danger)
      } else if (this.showError) {
        Text($r('app.string.lock_error'))
          .fontSize($r('app.float.font_aux'))
          .fontColor(palette(this.isDark).danger)
      }

      // 数字键盘
      Column({ space: 12 }) {
        ForEach(this.keyRows(), (row: string[]) => {
          Row({ space: 12 }) {
            ForEach(row, (key: string) => {
              if (key === '') {
                // 占位空键
                Blank()
                  .width(64)
                  .height(64)
              } else if (key === 'del') {
                Text('⌫')
                  .fontSize(22)
                  .fontColor(palette(this.isDark).textPrimary)
                  .width(64)
                  .height(64)
                  .textAlign(TextAlign.Center)
                  .onClick(() => {
                    this.onDeleteKey();
                  })
              } else {
                Text(key)
                  .fontSize(24)
                  .fontColor(palette(this.isDark).textPrimary)
                  .width(64)
                  .height(64)
                  .textAlign(TextAlign.Center)
                  .backgroundColor(palette(this.isDark).bgElevated)
                  .borderRadius($r('app.float.radius_circle'))
                  .onClick(() => {
                    this.onDigitKey(key);
                  })
              }
            }, (key: string) => 'key_' + key)
          }
        }, (row: string[], index: number) => 'row_' + index.toString())
      }
      .margin({ top: 16 })

      Blank()

      Text($r('app.string.lock_forgot'))
        .fontSize($r('app.float.font_aux'))
        .fontColor(palette(this.isDark).textSecondary)
        .padding(12)
        .onClick(() => {
          if (this.onForgot !== undefined) {
            this.onForgot();
          }
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).bgPage)
    .alignItems(HorizontalAlign.Center)
  }

  /** 数字键输入 */
  private onDigitKey(digit: string): void {
    if (this.lockRemainMs > 0) {
      return; // 等待期内不接受输入
    }
    if (this.inputPin.length >= AppConstants.PIN_LENGTH) {
      return;
    }
    this.showError = false;
    this.inputPin = this.inputPin + digit;
    if (this.inputPin.length === AppConstants.PIN_LENGTH) {
      this.verify();
    }
  }

  /** 退格 */
  private onDeleteKey(): void {
    if (this.inputPin.length > 0) {
      this.inputPin = this.inputPin.substring(0, this.inputPin.length - 1);
      this.showError = false;
    }
  }

  /** 校验：通过回调交给宿主页；失败后同步等待状态，达到上限即进入倒计时 */
  private async verify(): Promise<void> {
    if (this.onSubmit === undefined || this.lockRemainMs > 0) {
      return;
    }
    const pin: string = this.inputPin;
    let passed: boolean = false;
    try {
      passed = await this.onSubmit(pin);
    } catch (e) {
      passed = false;
    }
    if (passed) {
      this.inputPin = '';
      this.showError = false;
      this.lockRemainMs = 0;
      this.stopCountdown();
      return;
    }
    this.inputPin = '';
    this.showError = true;
    this.syncLockRemain();
    if (this.lockRemainMs > 0) {
      ToastUtil.showRes($r('app.string.lock_wait_seconds', Math.ceil(this.lockRemainMs / 1000)));
    } else {
      ToastUtil.showRes($r('app.string.lock_error'));
    }
  }

  /** 圆点下标 */
  private dotIndexes(): number[] {
    const dots: number[] = [];
    for (let i = 0; i < AppConstants.PIN_LENGTH; i++) {
      dots.push(i);
    }
    return dots;
  }

  /** 键盘 3 行布局（第二行中间留空键位对齐） */
  private keyRows(): string[][] {
    return [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'del']
    ];
  }
}
