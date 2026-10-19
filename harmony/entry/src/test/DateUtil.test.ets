import { describe, it, expect } from '@ohos/hypium';
import { DateUtil } from '../main/ets/utils/DateUtil';

export default function dateUtilTest() {
  describe('DateUtil', () => {
    it('isDateOnly 准确识别仅日期时间戳', 0, () => {
      const dayStart: number = new Date(2026, 4, 19, 0, 0, 0, 0).getTime();
      const noon: number = new Date(2026, 4, 19, 13, 30, 0, 0).getTime();
      expect(DateUtil.isDateOnly(dayStart)).assertTrue();
      expect(DateUtil.isDateOnly(noon)).assertFalse();
    });

    it('formatDate/formatTime 按本地时区格式化', 0, () => {
      const ts: number = new Date(2026, 4, 19, 13, 5, 0, 0).getTime();
      expect(DateUtil.formatDate(ts)).assertEqual('2026-05-19');
      expect(DateUtil.formatTime(ts)).assertEqual('13:05');
    });

    it('monthKey 与 monthLabel 正确', 0, () => {
      const ts: number = new Date(2026, 4, 19, 0, 0, 0, 0).getTime();
      expect(DateUtil.monthKey(ts)).assertEqual('2026-05');
      expect(DateUtil.monthLabel(ts)).assertEqual('2026年5月');
    });

    it('startOfMonth/endOfMonth 构成左闭右开月区间', 0, () => {
      const ts: number = new Date(2026, 4, 19, 0, 0, 0, 0).getTime();
      const start: number = DateUtil.startOfMonth(ts);
      const end: number = DateUtil.endOfMonth(ts);
      expect(DateUtil.formatDate(start)).assertEqual('2026-05-01');
      expect(DateUtil.formatDate(end)).assertEqual('2026-06-01');
    });
  });
}
