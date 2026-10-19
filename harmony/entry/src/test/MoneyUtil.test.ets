import { describe, it, expect } from '@ohos/hypium';
import { MoneyUtil } from '../main/ets/utils/MoneyUtil';

export default function moneyUtilTest() {
  describe('MoneyUtil', () => {
    it('标准格式化：符号+货币+千分位+两位小数', 0, () => {
      expect(MoneyUtil.format(2000)).assertEqual('¥20.00');
      expect(MoneyUtil.format(-2000)).assertEqual('-¥20.00');
      expect(MoneyUtil.format(0)).assertEqual('¥0.00');
      expect(MoneyUtil.format(200000)).assertEqual('¥2,000.00');
    });

    it('正数可带+号(收入场景)', 0, () => {
      expect(MoneyUtil.format(2000, '¥', true)).assertEqual('+¥20.00');
    });

    it('元字符串解析为分，规避浮点误差(F-金额铁律)', 0, () => {
      expect(MoneyUtil.parseInput('19.99')).assertEqual(1999);
      expect(MoneyUtil.parseInput('1.5')).assertEqual(150);
      expect(MoneyUtil.parseInput('.5')).assertEqual(50);
      expect(MoneyUtil.parseInput('0.01')).assertEqual(1);
    });

    it('非法输入解析为0', 0, () => {
      expect(MoneyUtil.parseInput('')).assertEqual(0);
      expect(MoneyUtil.parseInput('abc')).assertEqual(0);
      expect(MoneyUtil.parseInput('1.2.3')).assertEqual(0);
    });

    it('CSV专用格式无符号无千分位', 0, () => {
      expect(MoneyUtil.formatNoGroup(-1234, false)).assertEqual('-12.34');
      expect(MoneyUtil.formatNoGroup(9000, true)).assertEqual('+90.00');
    });
  });
}
