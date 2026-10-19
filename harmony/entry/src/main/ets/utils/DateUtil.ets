/**
 * 模块职责：时间处理（架构 9.2 时间铁律的唯一执行点）。
 * - 存储：一律 UTC 毫秒时间戳（INTEGER）
 * - 展示：一律经本文件按本地时区格式化
 * - 月区间：[startOfMonth, endOfMonth) 左闭右开；endOfMonth 返回下月 1 日 0 点
 * - 月键：'yyyy-MM'，用于 ll_budget.month 与月份切换
 * 说明：Date 的 getFullYear/getMonth/getDate 等取值即为本地时区语义，
 * new Date(y, m, d) 构造的也是本地时间，两者互转即得到正确的 UTC 毫秒戳。
 */
export class DateUtil {
  private static readonly MS_PER_DAY: number = 86400000;

  /** 当前 UTC 毫秒时间戳 */
  public static now(): number {
    return Date.now();
  }

  /** 本地当天 0 点的 UTC 毫秒戳 */
  public static startOfDay(ts: number): number {
    const d: Date = new Date(ts);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0).getTime();
  }

  /** 本地次日 0 点的 UTC 毫秒戳（与 startOfDay 构成左闭右开日区间） */
  public static endOfDay(ts: number): number {
    const d: Date = new Date(ts);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1, 0, 0, 0, 0).getTime();
  }

  /** 本地当月 1 日 0 点的 UTC 毫秒戳 */
  public static startOfMonth(ts: number): number {
    const d: Date = new Date(ts);
    return new Date(d.getFullYear(), d.getMonth(), 1, 0, 0, 0, 0).getTime();
  }

  /** 本地下月 1 日 0 点的 UTC 毫秒戳（月区间右端点，左闭右开） */
  public static endOfMonth(ts: number): number {
    const d: Date = new Date(ts);
    return new Date(d.getFullYear(), d.getMonth() + 1, 1, 0, 0, 0, 0).getTime();
  }

  /** 月份键：'yyyy-MM'（本地时区） */
  public static monthKey(ts: number): string {
    const d: Date = new Date(ts);
    return d.getFullYear().toString() + '-' + DateUtil.twoDigits(d.getMonth() + 1);
  }

  /** 月份键 → 该月起始时间戳；非法键返回当前月起始 */
  public static monthKeyToStart(monthKey: string): number {
    const parts: string[] = monthKey.split('-');
    if (parts.length !== 2) {
      return DateUtil.startOfMonth(DateUtil.now());
    }
    const year: number = parseInt(parts[0], 10);
    const month: number = parseInt(parts[1], 10);
    if (Number.isNaN(year) || Number.isNaN(month) || month < 1 || month > 12) {
      return DateUtil.startOfMonth(DateUtil.now());
    }
    return new Date(year, month - 1, 1, 0, 0, 0, 0).getTime();
  }

  /** 月份展示：'2026年5月' */
  public static monthLabel(ts: number): string {
    const d: Date = new Date(ts);
    return d.getFullYear().toString() + '年' + (d.getMonth() + 1).toString() + '月';
  }

  /** 日期展示：'yyyy-MM-dd' */
  public static formatDate(ts: number): string {
    const d: Date = new Date(ts);
    return d.getFullYear().toString() + '-' + DateUtil.twoDigits(d.getMonth() + 1) + '-' + DateUtil.twoDigits(d.getDate());
  }

  /** 时间展示：'HH:mm' */
  public static formatTime(ts: number): string {
    const d: Date = new Date(ts);
    return DateUtil.twoDigits(d.getHours()) + ':' + DateUtil.twoDigits(d.getMinutes());
  }

  /**
   * 是否只记录了日期（本地 0 点）。
   * 记账页只选日期，tx_date 恒为当天 0 点；此时不应展示 00:00 这类无意义时分。
   */
  public static isDateOnly(ts: number): boolean {
    return ts > 0 && DateUtil.startOfDay(ts) === ts;
  }

  /** 日期时间展示：'yyyy-MM-dd HH:mm' */
  public static formatDateTime(ts: number): string {
    return DateUtil.formatDate(ts) + ' ' + DateUtil.formatTime(ts);
  }

  /**
   * 日分组标签（明细页日头）：今天 / 昨天 / MM-DD 周X。
   * 以「本地日 0 点」为界比较，不依赖 24 小时差，避免跨月/夏令时错判。
   */
  public static dayLabel(ts: number): string {
    const todayStart: number = DateUtil.startOfDay(DateUtil.now());
    const dayStart: number = DateUtil.startOfDay(ts);
    const diffDays: number = Math.round((todayStart - dayStart) / DateUtil.MS_PER_DAY);
    if (diffDays === 0) {
      return '今天';
    }
    if (diffDays === 1) {
      return '昨天';
    }
    return DateUtil.formatDate(ts).substring(5) + ' ' + DateUtil.weekdayLabel(ts);
  }

  /** 星期标签：周日 / 周一 ... 周六 */
  public static weekdayLabel(ts: number): string {
    const dayIndex: number = new Date(ts).getDay();
    const names: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    return names[dayIndex];
  }

  /**
   * 近 N 个月的月份起始时间戳数组（升序，含当前月，长度 backN）。
   * 用于趋势折线图的 X 轴区间。
   */
  public static monthRange(backN: number): number[] {
    const result: number[] = [];
    const currentStart: number = DateUtil.startOfMonth(DateUtil.now());
    for (let i = backN - 1; i >= 0; i--) {
      result.push(DateUtil.addMonths(currentStart, -i));
    }
    return result;
  }

  /** 月份加减（跨年、大小月安全：先固定到 1 日再加减） */
  public static addMonths(ts: number, deltaMonths: number): number {
    const d: Date = new Date(DateUtil.startOfMonth(ts));
    return new Date(d.getFullYear(), d.getMonth() + deltaMonths, 1, 0, 0, 0, 0).getTime();
  }

  /** 天数加减 */
  public static addDays(ts: number, deltaDays: number): number {
    return DateUtil.startOfDay(ts) + deltaDays * DateUtil.MS_PER_DAY;
  }

  /** 是否为未来时间（记账页禁选未来日期，F-1.10） */
  public static isFuture(ts: number): boolean {
    return ts > DateUtil.now();
  }

  /** 补零到两位 */
  private static twoDigits(value: number): string {
    const s: string = value.toString();
    if (s.length >= 2) {
      return s;
    }
    return '0' + s;
  }
}
