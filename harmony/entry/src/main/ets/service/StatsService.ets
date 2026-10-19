/**
 * 模块职责：统计聚合服务（架构 T03 / 4.7）。
 * - 月度收支汇总 / 分类占比切片 / 趋势折线数据点
 * - 全部聚合排除 type=2（转账不计入收支）
 * - **每个方法首行 LogUtil.timeStart / 末行 timeEnd**：QA 实测「1 万条 < 300ms」指标
 * - 趋势用单次区间查询 + 内存按月分组，规避 strftime 兼容问题（架构 6.4）
 */
import { relationalStore } from '@kit.ArkData';
import { DatabaseManager } from './DatabaseManager';
import { Tables } from './SchemaConstants';
import { CategorySlice, MonthSummary, MonthTrendPoint } from '../model/StatsModels';
import { Category } from '../model/Category';
import { Transaction } from '../model/Transaction';
import { AppConstants, CategoryType, TxType } from '../constants/AppConstants';
import { CategoryService } from './CategoryService';
import { TransactionService } from './TransactionService';
import { SettingsService } from './SettingsService';
import {
  MERGED_OTHER_COLOR,
  MERGED_OTHER_ICON,
  MERGED_OTHER_LABEL
} from '../constants/CategoryPresets';
import { DateUtil } from '../utils/DateUtil';
import { LogUtil } from '../utils/LogUtil';

export class StatsService {
  private static readonly TAG: string = 'StatsService';

  /** 月度收支汇总（本月收入 / 支出；结余由 MonthSummary.net 计算） */
  public static async getMonthSummary(monthKey: string): Promise<MonthSummary> {
    LogUtil.timeStart(StatsService.TAG + '/getMonthSummary');
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    const start: number = DateUtil.monthKeyToStart(monthKey);
    const end: number = DateUtil.endOfMonth(start);
    // 走 idx_tx_ledger_type_date 前缀：WHERE ledger_id=? AND type IN (0,1) AND tx_date BETWEEN
    const sql: string = 'SELECT type, SUM(amount) AS total FROM ' + Tables.TRANSACTION +
      ' WHERE ledger_id = ? AND type IN (?, ?) AND tx_date >= ? AND tx_date < ? GROUP BY type';
    const resultSet: relationalStore.ResultSet = await store.querySql(sql,
      [SettingsService.getCurrentLedgerId(), TxType.EXPENSE, TxType.INCOME, start, end]);
    const summary: MonthSummary = new MonthSummary();
    try {
      while (resultSet.goToNextRow()) {
        const type: number = resultSet.getLong(resultSet.getColumnIndex('type'));
        const total: number = resultSet.getLong(resultSet.getColumnIndex('total'));
        if (type === TxType.EXPENSE) {
          summary.expense = total;
        } else if (type === TxType.INCOME) {
          summary.income = total;
        }
      }
    } finally {
      resultSet.close();
    }
    LogUtil.timeEnd(StatsService.TAG + '/getMonthSummary');
    return summary;
  }

  /**
   * 分类占比切片（环形图 + 排行榜）。
   * - 按分类聚合降序，关联 ll_category 补 name/icon/color，计算 ratio
   * - 占比 < 2%（SLICE_MERGE_RATIO）的尾部合并为「其他」切片（categoryId=0 不可下钻）
   */
  /** 全时间总计（统计页总计卡）：当前账本累计收入/支出（转账不计入，无日期过滤） */
  public static async getGrandTotal(): Promise<MonthSummary> {
    LogUtil.timeStart(StatsService.TAG + '/getGrandTotal');
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    const sql: string = 'SELECT type, SUM(amount) AS total FROM ' + Tables.TRANSACTION +
      ' WHERE ledger_id = ? AND type IN (?, ?) GROUP BY type';
    const resultSet: relationalStore.ResultSet = await store.querySql(sql,
      [SettingsService.getCurrentLedgerId(), TxType.EXPENSE, TxType.INCOME]);
    const summary: MonthSummary = new MonthSummary();
    try {
      while (resultSet.goToNextRow()) {
        const type: number = resultSet.getLong(resultSet.getColumnIndex('type'));
        const total: number = resultSet.getLong(resultSet.getColumnIndex('total'));
        if (type === TxType.EXPENSE) {
          summary.expense = total;
        } else if (type === TxType.INCOME) {
          summary.income = total;
        }
      }
    } finally {
      resultSet.close();
    }
    LogUtil.timeEnd(StatsService.TAG + '/getGrandTotal');
    return summary;
  }

  public static async getCategorySlices(monthKey: string, type: number): Promise<CategorySlice[]> {
    LogUtil.timeStart(StatsService.TAG + '/getCategorySlices');
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    const start: number = DateUtil.monthKeyToStart(monthKey);
    const end: number = DateUtil.endOfMonth(start);
    const sql: string = 'SELECT category_id, SUM(amount) AS t FROM ' + Tables.TRANSACTION +
      ' WHERE ledger_id = ? AND type = ? AND tx_date >= ? AND tx_date < ?' +
      ' GROUP BY category_id ORDER BY t DESC';
    const resultSet: relationalStore.ResultSet = await store.querySql(sql,
      [SettingsService.getCurrentLedgerId(), type, start, end]);
    const amounts: Map<number, number> = new Map();
    let grandTotal: number = 0;
    try {
      while (resultSet.goToNextRow()) {
        const categoryId: number = resultSet.getLong(resultSet.getColumnIndex('category_id'));
        const amount: number = resultSet.getLong(resultSet.getColumnIndex('t'));
        amounts.set(categoryId, amount);
        grandTotal += amount;
      }
    } finally {
      resultSet.close();
    }
    LogUtil.timeEnd(StatsService.TAG + '/getCategorySlices');
    if (grandTotal <= 0) {
      return [];
    }

    // 补充分类元数据并整形
    const categoryMap: Map<number, Category> = await CategoryService.loadNameMap();
    const slices: CategorySlice[] = [];
    let mergedAmount: number = 0;
    amounts.forEach((amount: number, categoryId: number) => {
      const ratio: number = amount / grandTotal;
      const category: Category | undefined = categoryMap.get(categoryId);
      if (ratio < AppConstants.SLICE_MERGE_RATIO) {
        mergedAmount += amount;
        return;
      }
      const slice: CategorySlice = new CategorySlice();
      slice.categoryId = categoryId;
      slice.amount = amount;
      slice.ratio = ratio;
      if (category === undefined) {
        // 分类被删除的兜底：保持金额可见，不可下钻
        slice.categoryName = MERGED_OTHER_LABEL;
        slice.icon = MERGED_OTHER_ICON;
        slice.color = MERGED_OTHER_COLOR;
      } else {
        slice.categoryName = category.name;
        slice.icon = category.icon;
        slice.color = category.color;
      }
      slices.push(slice);
    });
    if (mergedAmount > 0) {
      const other: CategorySlice = new CategorySlice();
      other.categoryId = 0;
      other.categoryName = MERGED_OTHER_LABEL;
      other.icon = MERGED_OTHER_ICON;
      other.color = MERGED_OTHER_COLOR;
      other.amount = mergedAmount;
      other.ratio = mergedAmount / grandTotal;
      slices.push(other);
    }
    return slices;
  }

  /**
   * 近 n 个月收支趋势（折线图，D3 定稿进 v1.0）。
   * 单次区间查询（走 idx_tx_ledger_date）+ 内存按 ym 分组，n=6 时约 3600 行、< 10ms。
   */
  public static async getTrend(nMonths: number): Promise<MonthTrendPoint[]> {
    LogUtil.timeStart(StatsService.TAG + '/getTrend');
    const monthStarts: number[] = DateUtil.monthRange(nMonths);
    if (monthStarts.length === 0) {
      return [];
    }
    const rangeStart: number = monthStarts[0];
    const rangeEnd: number = DateUtil.endOfMonth(monthStarts[monthStarts.length - 1]);
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    const sql: string = 'SELECT tx_date, type, amount FROM ' + Tables.TRANSACTION +
      ' WHERE ledger_id = ? AND type IN (?, ?) AND tx_date >= ? AND tx_date < ?';
    const resultSet: relationalStore.ResultSet = await store.querySql(sql,
      [SettingsService.getCurrentLedgerId(), TxType.EXPENSE, TxType.INCOME, rangeStart, rangeEnd]);

    // 预填 n 个月数据点，保证无数据月份也在 X 轴上
    const points: MonthTrendPoint[] = [];
    for (let i = 0; i < monthStarts.length; i++) {
      const point: MonthTrendPoint = new MonthTrendPoint();
      point.month = DateUtil.monthKey(monthStarts[i]);
      point.income = 0;
      point.expense = 0;
      points.push(point);
    }
    const pointIndex: Map<string, number> = new Map();
    for (let i = 0; i < points.length; i++) {
      pointIndex.set(points[i].month, i);
    }
    try {
      while (resultSet.goToNextRow()) {
        const txDate: number = resultSet.getLong(resultSet.getColumnIndex('tx_date'));
        const type: number = resultSet.getLong(resultSet.getColumnIndex('type'));
        const amount: number = resultSet.getLong(resultSet.getColumnIndex('amount'));
        const idx: number | undefined = pointIndex.get(DateUtil.monthKey(txDate));
        if (idx === undefined) {
          continue;
        }
        if (type === TxType.EXPENSE) {
          points[idx].expense += amount;
        } else if (type === TxType.INCOME) {
          points[idx].income += amount;
        }
      }
    } finally {
      resultSet.close();
    }
    LogUtil.timeEnd(StatsService.TAG + '/getTrend');
    return points;
  }

  /** 最近 n 条流水（委托 TransactionService，避免重复实现；架构 5.1 保留该入口） */
  public static async getRecent(n: number): Promise<Transaction[]> {
    return TransactionService.getRecent(n);
  }

  /** 分类类型常量透出（统计页支出/收入切换使用） */
  public static expenseType(): number {
    return CategoryType.EXPENSE;
  }
}
