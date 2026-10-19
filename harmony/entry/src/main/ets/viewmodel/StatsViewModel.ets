/**
 * 模块职责：统计页 ViewModel（架构 T03 / 6.4 时序 ④）。
 * 一次 load 聚合月度汇总 + 分类切片 + 趋势点，页面 @State 直接消费。
 */
import { CategorySlice, MonthSummary, MonthTrendPoint } from '../model/StatsModels';
import { StatsService } from '../service/StatsService';
import { AppConstants, CategoryType } from '../constants/AppConstants';
import { DateUtil } from '../utils/DateUtil';
import { LogUtil } from '../utils/LogUtil';

/** 统计页一次加载数据包 */
export class StatsData {
  public monthKey: string = '';
  /** 当前口径（CategoryType.EXPENSE / INCOME） */
  public type: number = CategoryType.EXPENSE;
  public summary: MonthSummary = new MonthSummary();
  /** 全时间总计（当前账本累计收支，总计卡展示） */
  public grandTotal: MonthSummary = new MonthSummary();
  public slices: CategorySlice[] = [];
  public trend: MonthTrendPoint[] = [];
}

export class StatsViewModel {

  /**
   * 聚合加载：汇总 / 总计 / 切片 / 趋势四路并发。
   * @param monthKey 月份键
   * @param type 支出或收入口径
   * @param trendMonths 趋势月数（默认近 6 个月）
   */
  public static async load(monthKey: string, type: number,
    trendMonths: number = AppConstants.TREND_MONTHS): Promise<StatsData> {
    LogUtil.timeStart('StatsViewModel/load');
    const data: StatsData = new StatsData();
    data.monthKey = monthKey;
    data.type = type;

    const tasks: Promise<void>[] = [];
    tasks.push(StatsService.getMonthSummary(monthKey).then((summary: MonthSummary) => {
      data.summary = summary;
    }));
    tasks.push(StatsService.getGrandTotal().then((grandTotal: MonthSummary) => {
      data.grandTotal = grandTotal;
    }));
    tasks.push(StatsService.getCategorySlices(monthKey, type).then((slices: CategorySlice[]) => {
      data.slices = slices;
    }));
    tasks.push(StatsService.getTrend(trendMonths).then((trend: MonthTrendPoint[]) => {
      data.trend = trend;
    }));
    await Promise.all(tasks);
    LogUtil.timeEnd('StatsViewModel/load');
    return data;
  }

  /** 支出/收入口径切换（返回新口径值供页面刷新） */
  public static switchType(current: number): number {
    return current === CategoryType.EXPENSE ? CategoryType.INCOME : CategoryType.EXPENSE;
  }

  /** 月份切换 */
  public static prevMonth(monthKey: string): string {
    return DateUtil.monthKey(DateUtil.addMonths(DateUtil.monthKeyToStart(monthKey), -1));
  }

  public static nextMonth(monthKey: string): string {
    return DateUtil.monthKey(DateUtil.addMonths(DateUtil.monthKeyToStart(monthKey), 1));
  }
}
