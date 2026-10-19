/**
 * 模块职责：统计查询 DTO（架构 4.3 StatsModels）。
 * 纯数据载体，由 StatsService（T03）聚合查询后填充，图表组件直接消费。
 */
import { Transaction } from './Transaction';

/**
 * 账户余额（实时计算结果，不冗余存储）。
 * balance = initialBalance + income - expense + transferIn - transferOut（架构 4.7）
 */
export class AccountBalance {
  public accountId: number = 0;
  public initialBalance: number = 0;
  /** 该账户收入流水合计（type=1，分） */
  public income: number = 0;
  /** 该账户支出流水合计（type=0，分） */
  public expense: number = 0;
  /** 转入合计（type=2 且 to_account_id=本账户，分） */
  public transferIn: number = 0;
  /** 转出合计（type=2 且 account_id=本账户，分） */
  public transferOut: number = 0;

  /** 实时余额（分），可为负（信用卡欠款） */
  public get balance(): number {
    return this.initialBalance + this.income - this.expense + this.transferIn - this.transferOut;
  }
}

/** 资产总览 DTO（首页资产卡） */
export class NetAssetSummary {
  /** 总资产 = Σ 未归档账户 balance ≥ 0 部分 */
  public totalAsset: number = 0;
  /** 总负债 = Σ 信用卡账户 balance < 0 的绝对值 */
  public totalDebt: number = 0;
  /** 净资产 = 总资产 - 总负债 */
  public netAsset: number = 0;
}

/** 分类占比切片（环形图 / 排行榜） */
export class CategorySlice {
  public categoryId: number = 0;
  public categoryName: string = '';
  public icon: string = 'ic_cat_more';
  public color: string = '#8A8F9E';
  /** 该分类金额（分） */
  public amount: number = 0;
  /** 占比 0~1 */
  public ratio: number = 0;
}

/** 月度收支汇总（首页结余卡 / 统计页三数字） */
export class MonthSummary {
  /** 收入合计（分） */
  public income: number = 0;
  /** 支出合计（分） */
  public expense: number = 0;

  /** 结余 = 收入 - 支出（分），可为负 */
  public get net(): number {
    return this.income - this.expense;
  }
}

/** 趋势折线图单月数据点 */
export class MonthTrendPoint {
  /** 月份键 'yyyy-MM' */
  public month: string = '';
  /** 该月收入（分） */
  public income: number = 0;
  /** 该月支出（分） */
  public expense: number = 0;
}

/** 预算进度 DTO（首页预算卡） */
export class BudgetProgress {
  /** 月度总预算（分），0 表示未设置 */
  public total: number = 0;
  /** 已用（分） */
  public used: number = 0;
  /** 剩余（分） */
  public remain: number = 0;
  /** 日均可用（分）= remain / 本月剩余天数 */
  public dailyAvailable: number = 0;
  /** 分级（BudgetLevel.NORMAL/WARN/OVER） */
  public level: number = 0;
}

/** 日分组流水（明细页列表，架构 5.3 P3） */
export class TxGroup {
  /** 日分组头标签：今天 / 昨天 / MM-DD 周X */
  public label: string = '';
  /** 该日收入合计（分） */
  public income: number = 0;
  /** 该日支出合计（分） */
  public expense: number = 0;
  /** 该日流水（txDate 倒序） */
  public items: Transaction[] = [];
}

/**
 * 流水条目展示 DTO（架构 T04 list/TxListItem 消费）。
 * ll_transaction 只存 id，名称/图标由 TxDisplayMapper 批量关联后填充；
 * 转账条目 categoryName 为空，accountName 为「转出账户 → 转入账户」。
 */
export class TxDisplayItem {
  public tx: Transaction = new Transaction();
  public categoryName: string = '';
  public categoryIcon: string = '';
  public categoryColor: string = '#8A8F9E';
  public accountName: string = '';
}
