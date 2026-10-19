/**
 * 模块职责：记账键盘的连续运算求值（架构 T02/T03，支持 + -，左结合）。
 * 输入链路（架构 9.2）：键盘串 → evaluate() → 元（number）→ MoneyUtil → 分（整数）。
 *
 * 精度策略：内部全程以「整数分」累加，最终通过字符串重组得到元数值，
 * 全程不出现除以 100 的浮点除法（÷100 铁律只属于 MoneyUtil），
 * 也不会产生 0.1 + 0.2 = 0.30000000000000004 之类的浮点污染。
 */
import { MoneyUtil } from './MoneyUtil';

export class ExpressionEvaluator {
  /** 表达式最大长度（含运算符） */
  static readonly MAX_LENGTH: number = 20;
  /** 小数位数上限 */
  static readonly MAX_DECIMALS: number = 2;

  /**
   * 求值键盘表达式，返回元（number，最多两位小数）。
   * 支持 + -；非法输入（空、以运算符结尾、除零不可能出现）返回 0。
   * 示例：'12+8+5' → 25；'0.1+0.2' → 0.3。
   */
  public static evaluate(expr: string): number {
    const trimmed: string = expr.trim();
    if (trimmed.length === 0) {
      return 0;
    }
    let totalCents: number = 0;
    let sign: number = 1;
    let start: number = 0;
    // 逐段切分：以 + - 为分隔，段内为十进制金额串；首个段若为负则符号为 -1
    for (let i = 0; i < trimmed.length; i++) {
      const ch: string = trimmed.charAt(i);
      if (ch === '+' || ch === '-') {
        const segment: string = trimmed.substring(start, i);
        if (segment.length > 0) {
          const cents: number = ExpressionEvaluator.parseSegmentToFen(segment);
          if (cents < 0) {
            return 0;
          }
          totalCents += sign * cents;
        }
        // 每个运算符独立决定其后一段的正负（左结合）：
        // 用「取反」会在 5-3-2 / 5-3+2 这类多运算符串上算错，必须按运算符绝对赋值
        sign = (ch === '-') ? -1 : 1;
        start = i + 1;
      }
    }
    const tail: string = trimmed.substring(start);
    if (tail.length === 0) {
      // 以运算符结尾视为未完成输入，返回 0 由页面提示
      return 0;
    }
    const tailCents: number = ExpressionEvaluator.parseSegmentToFen(tail);
    if (tailCents < 0) {
      return 0;
    }
    totalCents += sign * tailCents;
    // 整数分 → 元：统一收口到 MoneyUtil（共享约定：÷100 只允许出现在 MoneyUtil）
    return MoneyUtil.fenToYuan(totalCents);
  }

  /**
   * 键盘按键追加逻辑。
   * @param current 当前表达式
   * @param input 按键：'0'-'9' / '00' / '.' / '+' / '-'
   * @returns 新表达式（超长或非法输入时返回原表达式）
   */
  public static appendToken(current: string, input: string): string {
    // 「00」键：当前段非空且为数字时追加两个 0，否则忽略（架构 T04 约束 3）
    if (input === '00') {
      if (current.length + 2 > ExpressionEvaluator.MAX_LENGTH) {
        return current;
      }
      const segStart0: number = ExpressionEvaluator.lastSegmentStart(current);
      const segment0: string = current.substring(segStart0);
      const dotIdx0: number = segment0.indexOf('.');
      if (dotIdx0 >= 0 &&
        segment0.length - dotIdx0 - 1 + 2 > ExpressionEvaluator.MAX_DECIMALS) {
        return current;
      }
      // 空段（开头/紧跟运算符）或段为单个 '0' 时忽略，避免 '000' / '000.00' 前导零
      if (segment0.length === 0 || segment0 === '0') {
        return current;
      }
      return current + input;
    }
    if (input.length !== 1) {
      return current;
    }
    // 长度上限
    if (current.length + 1 > ExpressionEvaluator.MAX_LENGTH) {
      return current;
    }
    const isDigit: boolean = input >= '0' && input <= '9';
    const lastChar: string = current.length > 0 ? current.charAt(current.length - 1) : '';

    if (isDigit) {
      // 当前段小数位已满两位则忽略
      const segStart: number = ExpressionEvaluator.lastSegmentStart(current);
      const segment: string = current.substring(segStart);
      const dotIndex: number = segment.indexOf('.');
      if (dotIndex >= 0 && segment.length - dotIndex - 1 >= ExpressionEvaluator.MAX_DECIMALS) {
        return current;
      }
      // 前导 0：'0' 后直接跟数字则替换（'00'、'01' 均不允许）
      if (segment === '0') {
        return current.substring(0, segStart) + input;
      }
      return current + input;
    }

    if (input === '.') {
      // 当前段为空或刚输入运算符时不允许开头小数点（避免 '.5' 歧义）
      if (lastChar === '' || lastChar === '+' || lastChar === '-') {
        return current;
      }
      // 当前段已有小数点则忽略
      const segStart2: number = ExpressionEvaluator.lastSegmentStart(current);
      if (current.substring(segStart2).indexOf('.') >= 0) {
        return current;
      }
      return current + input;
    }

    if (input === '+' || input === '-') {
      // 空表达式或以运算符结尾时不允许再输运算符
      if (current.length === 0) {
        return current;
      }
      if (lastChar === '+' || lastChar === '-') {
        return current;
      }
      return current + input;
    }
    return current;
  }

  /** 退格：删除末位一个字符 */
  public static backspace(current: string): string {
    if (current.length === 0) {
      return current;
    }
    return current.substring(0, current.length - 1);
  }

  /** 清空表达式 */
  public static clear(): string {
    return '';
  }

  /** 最后一个数字段的起始下标 */
  private static lastSegmentStart(expr: string): number {
    let start: number = 0;
    for (let i = 0; i < expr.length; i++) {
      const ch: string = expr.charAt(i);
      if (ch === '+' || ch === '-') {
        start = i + 1;
      }
    }
    return start;
  }

  /**
   * 单段十进制金额串 → 分（整数）。
   * 超过两位小数截断（键盘层已限制不会出现）；非法段返回 -1。
   */
  private static parseSegmentToFen(segment: string): number {
    const s: string = segment.trim();
    if (s.length === 0) {
      return -1;
    }
    const dotIndex: number = s.indexOf('.');
    let intPart: string = s;
    let decPart: string = '';
    if (dotIndex >= 0) {
      // 多个小数点视为非法
      if (s.indexOf('.', dotIndex + 1) >= 0) {
        return -1;
      }
      intPart = s.substring(0, dotIndex);
      decPart = s.substring(dotIndex + 1);
    }
    if (intPart.length === 0 && decPart.length === 0) {
      return -1;
    }
    let yuan: number = 0;
    for (let i = 0; i < intPart.length; i++) {
      const d: number = intPart.charCodeAt(i) - 48;
      if (d < 0 || d > 9) {
        return -1;
      }
      yuan = yuan * 10 + d;
    }
    let cent: number = 0;
    for (let i = 0; i < ExpressionEvaluator.MAX_DECIMALS; i++) {
      // 小数位不足两位按 0 补齐（'1.5' → 150 分）；break 会让 '1.5' 变成 105 分
      let d2: number = 0;
      if (i < decPart.length) {
        d2 = decPart.charCodeAt(i) - 48;
        if (d2 < 0 || d2 > 9) {
          return -1;
        }
      }
      cent = cent * 10 + d2;
    }
    // 小数超出两位（理论不会出现，兜底）：截断而非舍入，避免静默放大
    if (decPart.length > ExpressionEvaluator.MAX_DECIMALS) {
      return -1;
    }
    return yuan * 100 + cent;
  }
}
