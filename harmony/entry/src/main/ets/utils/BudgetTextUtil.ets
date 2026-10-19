/**
 * 模块职责：预算占比文案（纯函数，便于单测）。
 *
 * 从 BudgetProgressCard.usedPercentText 抽取而来，逻辑完全等价：
 * - 未设预算 / 已用为 0 → '0%'
 * - 真实占比 < 1% → '<1%'（修复 F03：0.02 元 / 200 元 = 0.01%，原先 Math.ceil 会显示 1%）
 * - 1% ~ 100% → 保留一位小数，整数时不显示 .0
 * - 超支 → 整数百分比
 */
export class BudgetTextUtil {
  /**
   * 计算已用占比文案。
   * @param used 已用金额（分，可正可负；负数视作 0 展示）
   * @param total 预算总额（分，<=0 视为未设预算）
   */
  public static percentText(used: number, total: number): string {
    if (total <= 0 || used <= 0) {
      return '0%';
    }
    const percent: number = used / total * 100;
    if (percent < 1) {
      return '<1%';
    }
    if (percent < 100) {
      const fixed: string = percent.toFixed(1);
      const trimmed: string = fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
      return trimmed + '%';
    }
    return Math.round(percent).toString() + '%';
  }
}
