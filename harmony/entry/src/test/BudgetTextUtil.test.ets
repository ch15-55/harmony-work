import { describe, it, expect } from '@ohos/hypium';
import { BudgetTextUtil } from '../main/ets/utils/BudgetTextUtil';

export default function budgetTextUtilTest() {
  describe('BudgetTextUtil', () => {
    it('未设预算或已用为0显示0%(F03)', 0, () => {
      expect(BudgetTextUtil.percentText(0, 0)).assertEqual('0%');
      expect(BudgetTextUtil.percentText(100, 0)).assertEqual('0%');
      expect(BudgetTextUtil.percentText(0, 20000)).assertEqual('0%');
    });

    it('真实占比低于1%显示<1%而非1%(F03)', 0, () => {
      // 0.02 元 / 200 元 = 0.01%，旧逻辑 Math.ceil 会显示 1%
      expect(BudgetTextUtil.percentText(2, 20000)).assertEqual('<1%');
      expect(BudgetTextUtil.percentText(1, 20000)).assertEqual('<1%');
    });

    it('1%~100%保留一位小数且整数不显示.0', 0, () => {
      expect(BudgetTextUtil.percentText(5000, 20000)).assertEqual('25%');
      expect(BudgetTextUtil.percentText(500, 20000)).assertEqual('2.5%');
      expect(BudgetTextUtil.percentText(1500, 20000)).assertEqual('7.5%');
    });

    it('超支按整数百分比展示', 0, () => {
      expect(BudgetTextUtil.percentText(30000, 20000)).assertEqual('150%');
      expect(BudgetTextUtil.percentText(25000, 20000)).assertEqual('125%');
    });
  });
}
