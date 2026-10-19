/**
 * 模块职责：流水检索筛选条件（架构 4.3 TxFilter，F-5.3/F-5.4）。
 * 纯数据 + isEmpty() 判定，SQL 拼装在 TransactionService（T03）完成。
 */
export class TxFilter {
  /** 关键词：匹配备注 / 分类名 / 账户名 */
  public keyword: string = '';
  /** 分类多选（空数组表示不限） */
  public categoryIds: number[] = [];
  /** 账户多选（空数组表示不限） */
  public accountIds: number[] = [];
  /** 流水类型多选（TxType，空数组表示不限） */
  public types: number[] = [];
  /** 金额区间下限（分），<=0 表示不限 */
  public minAmount: number = 0;
  /** 金额区间上限（分），<=0 表示不限 */
  public maxAmount: number = 0;
  /** 时间区间下限（UTC 毫秒，含），<=0 表示不限 */
  public startDate: number = 0;
  /** 时间区间上限（UTC 毫秒，不含），<=0 表示不限 */
  public endDate: number = 0;

  /** 是否为空筛选（全部条件未启用时可直接走 listByMonth 快路径） */
  public isEmpty(): boolean {
    if (this.keyword.length > 0) {
      return false;
    }
    if (this.categoryIds.length > 0) {
      return false;
    }
    if (this.accountIds.length > 0) {
      return false;
    }
    if (this.types.length > 0) {
      return false;
    }
    if (this.minAmount > 0 || this.maxAmount > 0) {
      return false;
    }
    if (this.startDate > 0 || this.endDate > 0) {
      return false;
    }
    return true;
  }

  /** 重置全部条件 */
  public reset(): void {
    this.keyword = '';
    this.categoryIds = [];
    this.accountIds = [];
    this.types = [];
    this.minAmount = 0;
    this.maxAmount = 0;
    this.startDate = 0;
    this.endDate = 0;
  }

  /** 深拷贝（筛选面板「取消」回滚用） */
  public copy(): TxFilter {
    const clone: TxFilter = new TxFilter();
    clone.keyword = this.keyword;
    clone.categoryIds = this.categoryIds.slice();
    clone.accountIds = this.accountIds.slice();
    clone.types = this.types.slice();
    clone.minAmount = this.minAmount;
    clone.maxAmount = this.maxAmount;
    clone.startDate = this.startDate;
    clone.endDate = this.endDate;
    return clone;
  }
}
