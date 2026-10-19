/**
 * 模块职责：备份与恢复 ViewModel（架构 T03 / 9.5 错误处理分层）。
 * - Service 只 throw 业务异常，本层 catch 后统一收口为 Result<number>
 * - backup：saved → data=备份总行数；cancelled → ok=true 且 data 缺省（静默）；
 *   failed → ok=false + 失败文案
 * - restore：成功 → data=恢复总行数；校验/恢复失败 → ok=false + 校验原因或兜底文案
 */
import { common } from '@kit.AbilityKit';
import { Result } from '../constants/AppConstants';
import { ErrorMessages } from '../constants/ErrorMessages';
import { BackupService } from '../service/BackupService';
import { ExportOutcome, ExportStatus } from '../service/ExportService';
import { LogUtil } from '../utils/LogUtil';

export class BackupViewModel {
  private static readonly TAG: string = 'BackupViewModel';

  /** 本地备份（data = 备份总行数；cancelled 返回 ok=true 且 data 缺省） */
  public static async backup(context: common.UIAbilityContext): Promise<Result<number>> {
    try {
      const outcome: ExportOutcome = await BackupService.exportViaPicker(context);
      if (outcome.status === ExportStatus.SAVED) {
        const ok: Result<number> = { ok: true, data: outcome.count };
        return ok;
      }
      if (outcome.status === ExportStatus.CANCELLED) {
        // 用户取消：沿用「ok=true 且 data 缺省」的静默约定（架构 1.3）
        const cancelled: Result<number> = { ok: true };
        return cancelled;
      }
      const failed: Result<number> = { ok: false, message: ErrorMessages.EXPORT_FAILED };
      return failed;
    } catch (e) {
      const err: Error = e as Error;
      LogUtil.e(BackupViewModel.TAG, 'backup failed: ' + err.message);
      const failed: Result<number> = { ok: false, message: ErrorMessages.EXPORT_FAILED };
      return failed;
    }
  }

  /** 从备份恢复（data = 恢复总行数；失败 message = 校验原因或兜底文案） */
  public static async restore(context: common.UIAbilityContext, uri: string): Promise<Result<number>> {
    if (uri.length === 0) {
      // 用户在选择器取消：静默
      const cancelled: Result<number> = { ok: true };
      return cancelled;
    }
    try {
      const rowsTotal: number = await BackupService.restoreFromJson(uri);
      const ok: Result<number> = { ok: true, data: rowsTotal };
      return ok;
    } catch (e) {
      const err: Error = e as Error;
      LogUtil.e(BackupViewModel.TAG, 'restore failed: ' + err.message);
      const failed: Result<number> = {
        ok: false,
        message: err.message.length > 0 ? err.message : ErrorMessages.RESTORE_FAILED
      };
      return failed;
    }
  }
}
