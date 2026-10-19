/**
 * 模块职责：账本 ViewModel（架构 T02 / 9.5 错误处理分层）。
 * - Service 只 throw 业务异常，本层 catch 后统一收口为 Result
 * - Page 层据 ok / message 三态提示，不再感知异常类型
 */
import { Ledger } from '../model/Ledger';
import { AppConstants, Result } from '../constants/AppConstants';
import { ErrorMessages } from '../constants/ErrorMessages';
import { LedgerService } from '../service/LedgerService';
import { LogUtil } from '../utils/LogUtil';

export class LedgerViewModel {
  private static readonly TAG: string = 'LedgerViewModel';

  /** 账本列表（含当前标记所需的全部字段） */
  public static async load(): Promise<Result<Ledger[]>> {
    try {
      const ledgers: Ledger[] = await LedgerService.list();
      const ok: Result<Ledger[]> = { ok: true, data: ledgers };
      return ok;
    } catch (e) {
      const err: Error = e as Error;
      LogUtil.e(LedgerViewModel.TAG, 'load ledgers failed: ' + err.message);
      const failed: Result<Ledger[]> = { ok: false, message: ErrorMessages.UNKNOWN };
      return failed;
    }
  }

  /** 新建账本（data = 新账本 id） */
  public static async createLedger(name: string, icon: string, color: string): Promise<Result<number>> {
    try {
      const newId: number = await LedgerService.create(name, icon, color);
      const ok: Result<number> = { ok: true, data: newId };
      return ok;
    } catch (e) {
      const err: Error = e as Error;
      LogUtil.e(LedgerViewModel.TAG, 'createLedger failed: ' + err.message);
      const failed: Result<number> = { ok: false, message: err.message };
      return failed;
    }
  }

  /** 重命名账本（含图标/颜色一并更新，QA M2） */
  public static async renameLedger(id: number, name: string, icon: string, color: string): Promise<Result<boolean>> {
    try {
      await LedgerService.rename(id, name, icon, color);
      const ok: Result<boolean> = { ok: true, data: true };
      return ok;
    } catch (e) {
      const err: Error = e as Error;
      LogUtil.e(LedgerViewModel.TAG, 'renameLedger failed: ' + err.message);
      const failed: Result<boolean> = { ok: false, message: err.message };
      return failed;
    }
  }

  /** 删除账本（拦截口径由 Service 校验：默认账本 / 最后一本 / 有流水） */
  public static async deleteLedger(id: number): Promise<Result<boolean>> {
    try {
      await LedgerService.delete(id);
      const ok: Result<boolean> = { ok: true, data: true };
      return ok;
    } catch (e) {
      const err: Error = e as Error;
      LogUtil.e(LedgerViewModel.TAG, 'deleteLedger failed: ' + err.message);
      const failed: Result<boolean> = { ok: false, message: err.message };
      return failed;
    }
  }
}
