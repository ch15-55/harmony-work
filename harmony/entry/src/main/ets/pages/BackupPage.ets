/**
 * 模块职责：备份与恢复页（架构 T03 / PRD F-10.5 / F-10.6）。
 * - 「立即备份」：BackupViewModel.backup → 三态 Toast（成功含条数 / 取消静默 / 失败明确文案）
 * - 「从备份恢复」：选文件 → ConfirmDialog 覆盖二次确认（取消则不发生任何数据变更）
 *   → BackupViewModel.restore → 成功 Toast（含条数），DataBus.bump 由 service 触发
 * - 提示：「备份文件包含全部账目数据，请妥善保管」；防重复点击（busy 状态）
 */
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { palette } from '../constants/ThemeConstants';
import { AppStorageKeys, Result } from '../constants/AppConstants';
import { BackupViewModel } from '../viewmodel/BackupViewModel';
import { BackupService } from '../service/BackupService';
import { NavTitleBar } from '../components/common/NavTitleBar';
import { ConfirmDialog } from '../components/common/ConfirmDialog';
import { ToastUtil } from '../utils/ToastUtil';
import { LogUtil } from '../utils/LogUtil';

@Entry
@Component
struct BackupPage {
  private static readonly TAG: string = 'BackupPage';
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 防重复点击（备份/恢复共用） */
  @State private busy: boolean = false;
  /** 待恢复的备份文件 URI（确认弹窗回调用） */
  private pendingRestoreUri: string = '';

  private restoreDialog: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({
      title: $r('app.string.restore_confirm_title'),
      message: $r('app.string.restore_confirm_message'),
      danger: true,
      onConfirmed: (): void => {
        this.doRestore();
      }
    }),
    autoCancel: true,
    customStyle: false
  });

  build() {
    Column() {
      NavTitleBar({
        title: $r('app.string.backup_page_title'),
        showBack: true,
        onBack: (): void => {
          router.back();
        }
      })

      Scroll() {
        Column({ space: 12 }) {
          Text($r('app.string.backup_hint'))
            .fontSize($r('app.float.font_aux'))
            .fontColor(palette(this.isDark).textSecondary)
            .width('100%')
            .padding({ left: 4, right: 4, top: 4 })

          // 备份动作卡
          Column() {
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text($r('app.string.backup_action'))
                  .fontSize($r('app.float.font_body'))
                  .fontColor(palette(this.isDark).textPrimary)
                Text($r('app.string.backup_action_desc'))
                  .fontSize($r('app.float.font_aux'))
                  .fontColor(palette(this.isDark).textSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .height(64)
            .padding({ left: 12, right: 12 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.doBackup();
            })
          }
          .width('100%')
          .backgroundColor(palette(this.isDark).bgCard)
          .borderRadius($r('app.float.radius_card'))
          .clip(true)

          // 恢复动作卡
          Column() {
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text($r('app.string.restore_action'))
                  .fontSize($r('app.float.font_body'))
                  .fontColor(palette(this.isDark).textPrimary)
                Text($r('app.string.restore_action_desc'))
                  .fontSize($r('app.float.font_aux'))
                  .fontColor(palette(this.isDark).textSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .height(64)
            .padding({ left: 12, right: 12 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.pickAndConfirmRestore();
            })
          }
          .width('100%')
          .backgroundColor(palette(this.isDark).bgCard)
          .borderRadius($r('app.float.radius_card'))
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
    .backgroundColor(palette(this.isDark).bgPage)
  }

  private context(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  /** 取当前语言环境下含参数的文案（支持 %d/%s 替换） */
  private resText(res: Resource, ...args: Array<string | number>): string {
    return this.context().resourceManager.getStringSync(res, ...args);
  }

  /** 立即备份：三态分流（成功含条数 / 取消静默 / 失败明确文案） */
  private async doBackup(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const result: Result<number> = await BackupViewModel.backup(this.context());
      if (result.ok) {
        if (result.data !== undefined) {
          ToastUtil.show(this.resText($r('app.string.backup_success_count'), result.data));
        }
        // 用户取消：静默，无 Toast（架构 R8）
      } else {
        ToastUtil.show(result.message !== undefined && result.message.length > 0
          ? result.message
          : this.resText($r('app.string.backup_restore_failed')));
      }
    } finally {
      this.busy = false;
    }
  }

  /** 选择备份文件 → 空则静默；否则弹覆盖二次确认（架构 4.3） */
  private async pickAndConfirmRestore(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const uri: string = await BackupService.pickBackupFile(this.context());
      if (uri.length === 0) {
        return; // 用户取消选择：静默
      }
      // 覆盖确认前先完整校验；此步骤只读文件，不会修改当前账本。
      await BackupService.validateBackupUri(uri);
      this.pendingRestoreUri = uri;
      this.restoreDialog.open();
    } catch (e) {
      const err: Error = e as Error;
      ToastUtil.show(err.message.length > 0 ? err.message : this.resText($r('app.string.backup_restore_failed')));
    } finally {
      this.busy = false;
    }
  }

  /** 确认后的恢复执行（弹窗关闭后触发；失败 Toast 校验原因，库由事务保证不变） */
  private async doRestore(): Promise<void> {
    const uri: string = this.pendingRestoreUri;
    this.pendingRestoreUri = '';
    if (uri.length === 0 || this.busy) {
      return;
    }
    this.busy = true;
    try {
      const result: Result<number> = await BackupViewModel.restore(this.context(), uri);
      if (result.ok && result.data !== undefined) {
        ToastUtil.show(this.resText($r('app.string.backup_restore_success_count'), result.data));
      } else if (!result.ok) {
        ToastUtil.show(result.message !== undefined && result.message.length > 0
          ? result.message
          : this.resText($r('app.string.backup_restore_failed')));
      }
    } catch (e) {
      LogUtil.e(BackupPage.TAG, 'doRestore unexpected error');
      ToastUtil.showRes($r('app.string.backup_restore_failed'));
    } finally {
      this.busy = false;
    }
  }
}
