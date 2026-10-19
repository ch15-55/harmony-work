/**
 * 模块职责：预算领域服务（架构 T03）。
 * - 按月读取 / 保存（UPSERT 走 uk_budget_ledger_month 唯一索引）
 * - 进度计算：已用 = 当月支出合计（type=0，排除转账）；分级 80% 预警 / 100% 超支
 * - 分级判定用整数乘法比较，避免浮点占比误差
 */
import { relationalStore } from '@kit.ArkData';
import { DatabaseManager } from './DatabaseManager';
import { DataBus } from './DataBus';
import { Tables } from './SchemaConstants';
import { Budget } from '../model/Budget';
import { BudgetProgress } from '../model/StatsModels';
import { AppConstants, BudgetLevel, TxType } from '../constants/AppConstants';
import { SettingsService } from './SettingsService';
import { DateUtil } from '../utils/DateUtil';
import { ErrorMessages } from '../constants/ErrorMessages';

export class BudgetService {
  private static readonly TAG: string = 'BudgetService';

  /** 读取某月预算；未设置返回 null */
  public static async getByMonth(monthKey: string): Promise<Budget | null> {
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    return await BudgetService.getByMonthIn(store, monthKey);
  }

  private static async getByMonthIn(store: relationalStore.RdbStore, monthKey: string): Promise<Budget | null> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(Tables.BUDGET);
    predicates.equalTo('ledger_id', SettingsService.getCurrentLedgerId());
    predicates.equalTo('month', monthKey);
    const resultSet: relationalStore.ResultSet = await store.query(predicates);
    let budget: Budget | null = null;
    try {
      if (resultSet.goToFirstRow()) {
        budget = Budget.fromRow(resultSet);
      }
    } finally {
      resultSet.close();
    }
    return budget;
  }

  /**
   * 保存某月总预算（UPSERT 语义：有则更新、无则插入，依托唯一索引 uk_budget_ledger_month）。
   * totalAmount <= 0 视为清除预算。
   */
  public static async save(monthKey: string, totalAmount: number): Promise<void> {
    if (!Number.isSafeInteger(totalAmount) || totalAmount < 0) {
      throw new Error(ErrorMessages.BUDGET_NEGATIVE);
    }
    if (totalAmount > AppConstants.MAX_MONEY_FEN) {
      throw new Error(ErrorMessages.AMOUNT_INVALID);
    }
    const now: number = DateUtil.now();
    const db: DatabaseManager = DatabaseManager.getInstance();
    await db.runInTransaction<void>(async (store: relationalStore.RdbStore): Promise<void> => {
      const existing: Budget | null = await BudgetService.getByMonthIn(store, monthKey);
      if (existing === null) {
        if (totalAmount === 0) {
          return;
        }
        const budget: Budget = new Budget();
        budget.ledgerId = SettingsService.getCurrentLedgerId();
        budget.month = monthKey;
        budget.totalAmount = totalAmount;
        budget.createdAt = now;
        budget.updatedAt = now;
        await store.insert(Tables.BUDGET, budget.toValuesBucket());
      } else if (totalAmount === 0) {
        const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(Tables.BUDGET);
        predicates.equalTo('id', existing.id);
        await store.delete(predicates);
      } else {
        const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(Tables.BUDGET);
        predicates.equalTo('id', existing.id);
        const patch: relationalStore.ValuesBucket = {
          'total_amount': totalAmount,
          'updated_at': now
        };
        await store.update(patch, predicates);
      }
    });
    DataBus.bump();
  }

  /**
   * 预算进度（首页预算卡）：
   * 已用 = 当月支出合计；剩余 = total - used（可为负）；日均可用 = 剩余 ÷ 本月剩余天数（含今天）。
   */
  public static async getProgress(monthKey: string): Promise<BudgetProgress | null> {
    const budget: Budget | null = await BudgetService.getByMonth(monthKey);
    if (budget === null || budget.totalAmount <= 0) {
      return null;
    }
    const used: number = await BudgetService.getMonthExpense(monthKey);
    const progress: BudgetProgress = new BudgetProgress();
    progress.total = budget.totalAmount;
    progress.used = used;
    progress.remain = budget.totalAmount - used;
    progress.dailyAvailable = BudgetService.dailyAvailable(progress.remain);
    progress.level = BudgetService.getLevel(used, budget.totalAmount);
    return progress;
  }

  /** 当月支出合计（type=0；转账 type=2 不计入收支统计） */
  public static async getMonthExpense(monthKey: string): Promise<number> {
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    const start: number = DateUtil.monthKeyToStart(monthKey);
    const end: number = DateUtil.endOfMonth(start);
    const resultSet: relationalStore.ResultSet = await store.querySql(
      'SELECT COALESCE(SUM(amount),0) AS total FROM ' + Tables.TRANSACTION +
      ' WHERE ledger_id = ? AND type = ? AND tx_date >= ? AND tx_date < ?',
      [SettingsService.getCurrentLedgerId(), TxType.EXPENSE, start, end]);
    let total: number = 0;
    try {
      if (resultSet.goToFirstRow()) {
        total = resultSet.getLong(resultSet.getColumnIndex('total'));
      }
    } finally {
      resultSet.close();
    }
    return total;
  }

  /**
   * 分级判定（F-3.4）：used >= total → 超支；used*10 >= total*8 → 预警；否则正常。
   * 用整数乘法比较占比，规避浮点误差（金额铁律：全程整数运算）。
   */
  public static getLevel(used: number, total: number): number {
    if (total <= 0) {
      return BudgetLevel.NORMAL;
    }
    if (used >= total) {
      return BudgetLevel.OVER;
    }
    if (used * 10 >= total * Math.round(AppConstants.BUDGET_WARN_RATIO * 10)) {
      return BudgetLevel.WARN;
    }
    return BudgetLevel.NORMAL;
  }

  /** 日均可用：剩余预算 ÷ 本月剩余天数（含今天，向上取整） */
  public static dailyAvailable(remain: number): number {
    const now: number = DateUtil.now();
    const remainMs: number = DateUtil.endOfMonth(now) - DateUtil.startOfDay(now);
    const days: number = Math.ceil(remainMs / 86400000);
    if (days <= 0) {
      return remain;
    }
    if (remain <= 0) {
      return remain;
    }
    return Math.floor(remain / days);
  }
}
