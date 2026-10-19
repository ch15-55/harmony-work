/**
 * 模块职责：我的页 ViewModel（架构 T03，v1.1 T04/T05 增量）。
 * - 汇总：账本/账户/分类数量、预算状态、应用锁状态、主题、货币、提醒状态
 * - exportCsv：委托 ExportService（R8 三态：saved/cancelled/failed），
 *   返回 Result<number>：data = 导出条数；cancelled → ok=true 且 data 缺省（静默）；
 *   failed → ok=false + ErrorMessages.EXPORT_FAILED
 * - clearAllData：清库 + 重置锁凭据（页面二次确认后调用）
 */
import { common } from '@kit.AbilityKit';
import { Account } from '../model/Account';
import { AppSettings } from '../model/AppSettings';
import { AppConstants, Result, ThemeMode } from '../constants/AppConstants';
import { ErrorMessages } from '../constants/ErrorMessages';
import { AccountService } from '../service/AccountService';
import { CategoryService } from '../service/CategoryService';
import { BudgetService } from '../service/BudgetService';
import { LedgerService } from '../service/LedgerService';
import { DatabaseManager } from '../service/DatabaseManager';
import { ExportService, ExportOutcome, ExportStatus } from '../service/ExportService';
import { AppLockService } from '../service/AppLockService';
import { SettingsService } from '../service/SettingsService';
import { DataBus } from '../service/DataBus';
import { DateUtil } from '../utils/DateUtil';
import { LogUtil } from '../utils/LogUtil';

/** 我的页汇总数据包 */
export class MineSummary {
  /** 账本数量（F-10.2 多账本，我的页展示「N 个」） */
  public ledgerCount: number = 0;
  /** 账户数量（未归档） */
  public accountCount: number = 0;
  /** 可见分类数量 */
  public categoryCount: number = 0;
  /** 本月预算是否已设置 */
  public budgetSet: boolean = false;
  /** 本月预算金额（分，未设置为 0） */
  public budgetAmount: number = 0;
  public settings: AppSettings = new AppSettings();
  public themeMode: number = ThemeMode.SYSTEM;
}

export class MineViewModel {

  /** 汇总加载（各项独立容错：单项失败不拖垮整页） */
  public static async loadSummary(): Promise<MineSummary> {
    const summary: MineSummary = new MineSummary();
    const accounts: Account[] = await AccountService.listAll(false);
    summary.accountCount = accounts.length;
    summary.categoryCount = await CategoryService.countAll();
    summary.ledgerCount = await LedgerService.countAll();

    const monthKey: string = DateUtil.monthKey(DateUtil.now());
    const budget = await BudgetService.getByMonth(monthKey);
    if (budget !== null) {
      summary.budgetSet = budget.totalAmount > 0;
      summary.budgetAmount = budget.totalAmount;
    }

    const settings: AppSettings = new AppSettings();
    settings.themeMode = SettingsService.getThemeMode();
    settings.currency = SettingsService.getCurrency();
    settings.monthStartDay = SettingsService.getMonthStartDay();
    settings.lockEnabled = AppLockService.isEnabled();
    settings.pinHash = SettingsService.getPinHash();
    settings.pinSalt = SettingsService.getPinSalt();
    settings.lastAccountId = SettingsService.getLastAccountId();
    settings.lastCategoryId = SettingsService.getLastCategoryId();
    settings.privacyAgreed = SettingsService.isPrivacyAgreed();
    settings.amountHidden = SettingsService.isAmountHidden();
    summary.settings = settings;
    summary.themeMode = settings.themeMode;
    return summary;
  }

  /**
   * 导出 CSV（架构 R8 三态语义）。
   * saved → ok=true 且 data=条数；cancelled → ok=true 且 data 缺省（页面静默）；
   * failed → ok=false + ErrorMessages.EXPORT_FAILED。
   */
  public static async exportCsv(context: common.UIAbilityContext, monthKey: string): Promise<Result<number>> {
    try {
      const outcome: ExportOutcome = await ExportService.exportViaPicker(context, monthKey);
      if (outcome.status === ExportStatus.SAVED) {
        const saved: Result<number> = { ok: true, data: outcome.count };
        return saved;
      }
      if (outcome.status === ExportStatus.CANCELLED) {
        const cancelled: Result<number> = { ok: true };
        return cancelled;
      }
      // failed：把失败点 + 完整错误码一并带回，便于真机定位与反馈
      const reason: string = MineViewModel.exportFailureReason(outcome.failurePoint);
      const failed: Result<number> = {
        ok: false,
        message: ErrorMessages.EXPORT_FAILED + (reason.length > 0 ? '（' + reason + '）' : ''),
        detail: outcome.detail
      };
      return failed;
    } catch (e) {
      const err: Error = e as Error;
      LogUtil.e('MineViewModel', 'exportCsv failed: ' + err.message);
      const failed: Result<number> = { ok: false, message: ErrorMessages.EXPORT_FAILED };
      return failed;
    }
  }

  /** 导出失败点 → 中文可读原因（service 层已按点 LogUtil.e 留痕） */
  private static exportFailureReason(failurePoint: string): string {
    if (failurePoint === 'build') {
      return '数据生成异常';
    }
    if (failurePoint === 'temp_file') {
      return '沙箱写入失败';
    }
    if (failurePoint === 'picker') {
      return '系统保存面板异常';
    }
    if (failurePoint === 'copy') {
      return '文件写入目标失败';
    }
    return '';
  }

  /**
   * 清空全部数据（忘记密码重置 / 用户主动清空共用）。
   * 清库 → 重置 PIN 凭据 → bump 全局刷新。
   */
  public static async clearAllData(): Promise<Result<boolean>> {
    try {
      await DatabaseManager.getInstance().clearAllData();
      AppLockService.disable();
      DataBus.bump();
      const ok: Result<boolean> = { ok: true, data: true };
      return ok;
    } catch (e) {
      LogUtil.e('MineViewModel', 'clearAllData failed');
      const failed: Result<boolean> = { ok: false, message: ErrorMessages.CLEAR_FAILED };
      return failed;
    }
  }
}
