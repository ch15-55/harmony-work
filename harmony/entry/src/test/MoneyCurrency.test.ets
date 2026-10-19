import { describe, it, expect } from '@ohos/hypium';
import { MoneyUtil } from '../main/ets/utils/MoneyUtil';

export default function moneyCurrencyTest() {
  describe('MoneyUtil 多币种(F04)', () => {
    it('展示由基础金额换算得出，但绝不回写/改动基础金额', 0, () => {
      const baseFen: number = 7200; // 库中恒为基础货币：¥72.00
      const snapshot: number = baseFen;
      const usd: string = MoneyUtil.displayIn(baseFen, '$', 7.2); // 1 USD = 7.2 CNY
      // 基础金额作为唯一数据源，切币种/汇率只影响展示，不改写自身
      expect(baseFen).assertEqual(snapshot);
      expect(usd).assertEqual('$10.00');
      const cny: string = MoneyUtil.displayIn(baseFen, '¥', 1);
      expect(cny).assertEqual('¥72.00');
    });

    it('同一基础金额在不同币种下保持一致换算口径', 0, () => {
      const base: number = 12345; // ¥123.45
      expect(MoneyUtil.displayIn(base, '¥', 1)).assertEqual('¥123.45');
      expect(MoneyUtil.displayIn(base, '$', 7.2)).assertEqual('$17.15');
    });

    it('非法汇率回退为1，避免 Infinity', 0, () => {
      // 7200 分 = ¥72.00；rate 非法(0/-2)按 1 处理，故直接视作 7200 分 → $72.00
      expect(MoneyUtil.displayIn(7200, '$', 0)).assertEqual('$72.00');
      expect(MoneyUtil.displayIn(7200, '$', -2)).assertEqual('$72.00');
    });
  });
}
