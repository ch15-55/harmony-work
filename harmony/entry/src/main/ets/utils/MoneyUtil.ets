/**
 * 模块职责：金额换算与格式化（架构 9.2 金额铁律的唯一执行点）。
 * - 数据库金额一律 INTEGER，单位：分（¥20.00 → 2000）
 * - 全项目整数运算，禁止浮点金额运算
 * - **÷100 只允许出现在本文件内**，其他任何位置不得出现除以 100 的换算
 * - 数据库 amount 恒为正，方向由 type 决定；展示符号由本文件拼装
 * - 多币种（v1.1）：库中恒存基础货币（¥ 分）；展示按设置币种汇率换算，
 *   录入按展示币种换算回基础货币。换算精度统一 Math.round 后仍为整数分。
 */
import { SettingsService } from '../service/SettingsService';
import { AppConstants } from '../constants/AppConstants';

export class MoneyUtil {
  /** 默认货币符号（基础货币） */
  static readonly DEFAULT_CURRENCY: string = '¥';

  /** 当前展示货币符号（设置未就绪时回退 ¥） */
  public static displayCurrency(): string {
    return SettingsService.getCurrency();
  }

  /** 当前展示汇率（1 单位展示币 = 多少元基础货币 ¥；¥ 恒 1） */
  public static displayRate(): number {
    return SettingsService.getCurrencyRate(MoneyUtil.displayCurrency());
  }

  /**
   * 展示格式化：基础货币分 → 按当前币种汇率换算并带符号。
   * 全站列表/卡片/统计的金额展示统一入口；¥ 币种下输出与 format 等价。
   */
  public static display(fen: number, showSign: boolean = false): string {
    return MoneyUtil.displayIn(fen, MoneyUtil.displayCurrency(), MoneyUtil.displayRate(), showSign);
  }

  /**
   * 指定币种与汇率的展示格式化（响应式组件用）。
   * 与 display 共用同一换算与格式规则，保证汇总、列表、明细、详情口径一致。
   * 汇率非法（<=0）时按 1 处理，避免出现 Infinity。
   */
  public static displayIn(fen: number, currency: string, rate: number, showSign: boolean = false): string {
    const safeRate: number = Number.isFinite(rate) && rate > 0 ? rate : 1;
    return MoneyUtil.format(Math.round(fen / safeRate), currency, showSign);
  }

  /** 展示货币分 → 基础货币分（录入链路：键盘按展示币输入，入库前换算） */
  public static displayFenToBaseFen(displayFen: number): number {
    return Math.round(displayFen * MoneyUtil.displayRate());
  }

  /** 基础货币分 → 展示货币分（编辑回填：库中金额转为输入框数值） */
  public static baseFenToDisplayFen(baseFen: number): number {
    return Math.round(baseFen / MoneyUtil.displayRate());
  }

  /**
   * 分 → 元（浮点展示用，非精确场景）。
   * 这是全项目唯一的「分转元」除法点。
   */
  public static fenToYuan(fen: number): number {
    const sign: number = fen < 0 ? -1 : 1;
    const abs: number = Math.abs(Math.round(fen));
    return sign * (abs / 100);
  }

  /**
   * 元（number）→ 分（整数）。
   * 先转字符串再按位拆解，规避 19.99 * 100 = 1998.9999 这类浮点误差。
   */
  public static yuanToFen(yuan: number): number {
    if (Number.isNaN(yuan) || !Number.isFinite(yuan)) {
      return 0;
    }
    return MoneyUtil.parseYuanToIntFen(yuan.toFixed(2));
  }

  /**
   * 键盘输入串 → 分（架构 9.2 输入链路终点）。
   * 输入链路：键盘串 → ExpressionEvaluator.evaluate()（元）→ 本方法（分）。
   * 非法输入返回 0，由调用方校验金额有效性后提示。
   */
  public static parseInput(text: string): number {
    return MoneyUtil.parseYuanToIntFen(text);
  }

  /** 严格解析输入金额。格式不完整、包含额外字符或超出安全范围时返回 null。 */
  public static parseStrictInput(text: string): number | null {
    const trimmed: string = text.trim();
    if (trimmed.length === 0) {
      return null;
    }
    const fen: number = MoneyUtil.parseYuanToIntFen(trimmed);
    if (!MoneyUtil.isStrictYuanText(trimmed) || !Number.isSafeInteger(fen)) {
      return null;
    }
    return fen;
  }

  /**
   * 标准格式化：符号 + 货币 + 千分位 + 两位小数。
   * @param fen 金额（分），可正可负
   * @param currency 货币符号，默认 ¥
   * @param showSign 正数是否显示 + 号（收入场景使用）
   */
  public static format(fen: number, currency: string = MoneyUtil.DEFAULT_CURRENCY, showSign: boolean = false): string {
    const sign: string = fen < 0 ? '-' : (showSign ? '+' : '');
    const abs: number = Math.abs(Math.round(fen));
    const yuanPart: number = Math.floor(abs / 100);
    const centPart: number = abs % 100;
    return sign + currency + MoneyUtil.groupThousands(yuanPart) + '.' + MoneyUtil.twoDigits(centPart);
  }

  /** 不带符号的纯金额文本（列表、报表内使用，避免重复符号） */
  public static formatPlain(fen: number, currency: string = MoneyUtil.DEFAULT_CURRENCY): string {
    return MoneyUtil.format(fen, currency, false);
  }

  /**
   * CSV 导出专用：无货币符号、无千分位，正数按 showSign 加 +。
   * 例：-1234 → "-12.34"；9000, true → "+90.00"。
   */
  public static formatNoGroup(fen: number, showSign: boolean = false): string {
    const sign: string = fen < 0 ? '-' : (showSign ? '+' : '');
    const abs: number = Math.abs(Math.round(fen));
    const yuanPart: number = Math.floor(abs / 100);
    const centPart: number = abs % 100;
    return sign + yuanPart.toString() + '.' + MoneyUtil.twoDigits(centPart);
  }

  /** 金额是否为合法的记账金额：正整数分且不超过 9000000000 分（= 9000 万元/笔） */
  public static isRecordableAmount(fen: number): boolean {
    return Number.isSafeInteger(fen) && fen > 0 && fen <= AppConstants.MAX_MONEY_FEN;
  }

  /** 千分位分组（整数部分） */
  private static groupThousands(value: number): string {
    const s: string = Math.abs(Math.round(value)).toString();
    let result: string = '';
    let count: number = 0;
    for (let i = s.length - 1; i >= 0; i--) {
      result = s.charAt(i) + result;
      count++;
      if (count % 3 === 0 && i > 0) {
        result = ',' + result;
      }
    }
    return result;
  }

  /** 两位小数补零 */
  private static twoDigits(value: number): string {
    const s: string = value.toString();
    if (s.length >= 2) {
      return s;
    }
    return '0' + s;
  }

  /**
   * 元字符串 → 分（整数）。
   * 支持 "12" / "12." / "12.3" / ".5" / "-12.34"；小数第 3 位四舍五入；非法字符按 0 处理。
   */
  private static parseYuanToIntFen(text: string): number {
    let s: string = text.trim();
    if (s.length === 0) {
      return 0;
    }
    let negative: boolean = false;
    if (s.charAt(0) === '-') {
      negative = true;
      s = s.substring(1);
    } else if (s.charAt(0) === '+') {
      s = s.substring(1);
    }
    if (s.length === 0) {
      return 0;
    }
    const dotIndex: number = s.indexOf('.');
    if (dotIndex >= 0 && s.indexOf('.', dotIndex + 1) >= 0) {
      return 0;
    }
    let intPart: string = s;
    let decPart: string = '';
    if (dotIndex >= 0) {
      intPart = s.substring(0, dotIndex);
      decPart = s.substring(dotIndex + 1);
    }
    let yuan: number = 0;
    for (let i = 0; i < intPart.length; i++) {
      const d: number = MoneyUtil.digitAt(intPart, i);
      if (d < 0) {
        return 0;
      }
      yuan = yuan * 10 + d;
    }
    let cent: number = 0;
    if (decPart.length > 0) {
      // 小数位不足两位时按 0 补齐（'1.5' → 50 分），避免 '1.5' 被解析成 1.05 元
      for (let i = 0; i < decPart.length; i++) {
        if (MoneyUtil.digitAt(decPart, i) < 0) {
          return 0;
        }
      }
      const d0: number = MoneyUtil.digitAt(decPart, 0);
      const d1: number = decPart.length > 1 ? MoneyUtil.digitAt(decPart, 1) : 0;
      const d2: number = decPart.length > 2 ? MoneyUtil.digitAt(decPart, 2) : 0;
      if (d0 < 0 || d1 < 0 || d2 < 0) {
        return 0;
      }
      cent = d0 * 10 + d1 + (d2 >= 5 ? 1 : 0);
    }
    const fen: number = yuan * 100 + cent;
    if (!Number.isSafeInteger(fen)) {
      return 0;
    }
    return negative ? -fen : fen;
  }

  /** 仅允许一个可选符号、数字与一个小数点；不接受 parseFloat 的部分匹配语义。 */
  private static isStrictYuanText(text: string): boolean {
    let start: number = 0;
    if (text.charAt(0) === '-' || text.charAt(0) === '+') {
      start = 1;
    }
    if (start >= text.length) {
      return false;
    }
    let dotCount: number = 0;
    let digitCount: number = 0;
    for (let i = start; i < text.length; i++) {
      const c: string = text.charAt(i);
      if (c === '.') {
        dotCount++;
        if (dotCount > 1) {
          return false;
        }
      } else if (MoneyUtil.digitAt(text, i) >= 0) {
        digitCount++;
      } else {
        return false;
      }
    }
    return digitCount > 0;
  }

  /** 取字符串指定下标的数字，越界或非数字返回 -1（由调用方判负） */
  private static digitAt(s: string, index: number): number {
    if (index < 0 || index >= s.length) {
      return -1;
    }
    const code: number = s.charCodeAt(index) - 48;
    if (code < 0 || code > 9) {
      return -1;
    }
    return code;
  }
}
