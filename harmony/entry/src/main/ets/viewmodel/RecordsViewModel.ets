/**
 * 模块职责：明细页 ViewModel（架构 T03）。
 * - 按月加载流水并按日分组（今天/昨天/MM-DD 周X 头 + 当日收支小计）
 * - 月度汇总条（支出/收入/结余）、关键词搜索、多维筛选
 * - 月份前进/后退（日边界由 DateUtil 收口）
 */
import { Transaction } from '../model/Transaction';
import { TxDisplayItem, TxGroup, MonthSummary } from '../model/StatsModels';
import { TxFilter } from '../model/TxFilter';
import { TxType } from '../constants/AppConstants';
import { TransactionService } from '../service/TransactionService';
import { TxDisplayMapper } from './TxDisplayMapper';
import { DateUtil } from '../utils/DateUtil';
import { LogUtil } from '../utils/LogUtil';

/** 明细页一次加载数据包 */
export class RecordsData {
  public monthKey: string = '';
  public groups: TxGroup[] = [];
  public summary: MonthSummary = new MonthSummary();
  /** 当前月总笔数（含筛选后口径） */
  public totalCount: number = 0;
}

/** 分类下钻数据包（统计页环形图 → CategoryTxListPage） */
export class CategoryTxData {
  /** 已关联分类/账户名的流水（txDate 倒序） */
  public items: TxDisplayItem[] = [];
  /** 该分类当月合计（分） */
  public total: number = 0;
  /** 笔数 */
  public count: number = 0;
}

export class RecordsViewModel {

  /** 加载某月流水：优先走筛选链路，空筛选走快路径（listByMonth） */
  public static async load(monthKey: string, keyword: string, filter: TxFilter): Promise<RecordsData> {
    LogUtil.timeStart('RecordsViewModel/load');
    const data: RecordsData = new RecordsData();
    data.monthKey = monthKey;
    let txList: Transaction[];
    // 关键词属于 TxFilter 的一部分，交由 SQL 同时匹配备注、分类名和账户名。
    // 拷贝后再写入，避免调用方持有的筛选状态被加载操作意外修改。
    const queryFilter: TxFilter = filter.copy();
    queryFilter.keyword = keyword.trim();
    if (!queryFilter.isEmpty()) {
      txList = await TransactionService.listByFilter(monthKey, queryFilter);
    } else {
      txList = await TransactionService.listByMonth(monthKey);
    }

    data.totalCount = txList.length;
    data.groups = RecordsViewModel.groupByDay(txList);
    data.summary = RecordsViewModel.summarize(txList);
    LogUtil.timeEnd('RecordsViewModel/load');
    return data;
  }

  /** 上一月 / 下一月（返回新月键） */
  public static prevMonth(monthKey: string): string {
    return DateUtil.monthKey(DateUtil.addMonths(DateUtil.monthKeyToStart(monthKey), -1));
  }

  public static nextMonth(monthKey: string): string {
    return DateUtil.monthKey(DateUtil.addMonths(DateUtil.monthKeyToStart(monthKey), 1));
  }

  /** 删除流水（Service 内含转账双删事务与 bump） */
  public static async deleteTx(id: number): Promise<void> {
    await TransactionService.delete(id);
  }

  /**
   * 单条流水详情（详情页消费）：不存在或已删除返回 null，页面渲染空态。
   * 名称关联复用 TxDisplayMapper，避免页面触达 Service。
   */
  public static async loadDetail(txId: number): Promise<TxDisplayItem | null> {
    const tx: Transaction | null = await TransactionService.getById(txId);
    if (tx === null) {
      return null;
    }
    const single: Transaction[] = [tx];
    const displays: TxDisplayItem[] = await TxDisplayMapper.resolve(single);
    if (displays.length === 0) {
      return null;
    }
    return displays[0];
  }

  /** 某月某分类的全部流水（环形图/排行榜下钻） */
  public static async loadByCategory(monthKey: string, categoryId: number): Promise<CategoryTxData> {
    const filter: TxFilter = new TxFilter();
    filter.categoryIds = [categoryId];
    const txList: Transaction[] = await TransactionService.listByFilter(monthKey, filter);
    const data: CategoryTxData = new CategoryTxData();
    data.items = await TxDisplayMapper.resolve(txList);
    data.count = txList.length;
    let total: number = 0;
    for (let i = 0; i < txList.length; i++) {
      total += txList[i].amount;
    }
    data.total = total;
    return data;
  }

  /** 按本地日分组（txDate 倒序输入 → 日组保持倒序；用日 0 点比较而非标签反解） */
  private static groupByDay(txList: Transaction[]): TxGroup[] {
    const groups: TxGroup[] = [];
    let current: TxGroup | null = null;
    let currentDayStart: number = -1;
    for (let i = 0; i < txList.length; i++) {
      const tx: Transaction = txList[i];
      const dayStart: number = DateUtil.startOfDay(tx.txDate);
      if (current === null || currentDayStart !== dayStart) {
        current = new TxGroup();
        current.label = DateUtil.dayLabel(tx.txDate);
        currentDayStart = dayStart;
        groups.push(current);
      }
      if (tx.type === TxType.EXPENSE) {
        current.expense += tx.amount;
      } else if (tx.type === TxType.INCOME) {
        current.income += tx.amount;
      }
      current.items.push(tx);
    }
    return groups;
  }

  /** 月度汇总（排除转账） */
  private static summarize(txList: Transaction[]): MonthSummary {
    const summary: MonthSummary = new MonthSummary();
    for (let i = 0; i < txList.length; i++) {
      const tx: Transaction = txList[i];
      if (tx.type === TxType.EXPENSE) {
        summary.expense += tx.amount;
      } else if (tx.type === TxType.INCOME) {
        summary.income += tx.amount;
      }
    }
    return summary;
  }

}
