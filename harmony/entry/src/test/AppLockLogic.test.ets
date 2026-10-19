import { describe, it, expect } from '@ohos/hypium';
import { AppLockLogic, LockState } from '../main/ets/utils/AppLockLogic';

export default function appLockLogicTest() {
  describe('AppLockLogic', () => {
    it('初始状态无失败无锁定', 0, () => {
      const s: LockState = AppLockLogic.initial();
      expect(s.failCount).assertEqual(0);
      expect(s.lockUntilMs).assertEqual(0);
    });

    it('连续错误达到上限后进入等待期且期间拒绝校验(F05)', 0, () => {
      const max: number = 5;
      const lockMs: number = 30000;
      const now: number = 1000000;
      let s: LockState = AppLockLogic.initial();
      for (let i = 0; i < max; i++) {
        s = AppLockLogic.registerFailure(s, now, max, lockMs);
      }
      expect(s.failCount).assertEqual(5);
      expect(AppLockLogic.isLocked(s, now + 1000)).assertTrue();
      expect(AppLockLogic.remainingMs(s, now + 1000)).assertEqual(30000 - 1000);
    });

    it('等待期内再次失败顺延截止时间(F05)', 0, () => {
      let s: LockState = AppLockLogic.initial();
      s = AppLockLogic.registerFailure(s, 1000, 5, 30000);
      s = AppLockLogic.registerFailure(s, 1001, 5, 30000);
      s = AppLockLogic.registerFailure(s, 1002, 5, 30000);
      s = AppLockLogic.registerFailure(s, 1003, 5, 30000);
      s = AppLockLogic.registerFailure(s, 1004, 5, 30000);
      expect(s.failCount).assertEqual(5);
      // 第5次失败写入截止，之后第6次失败顺延 30000ms
      s = AppLockLogic.registerFailure(s, 2000, 5, 30000);
      expect(s.lockUntilMs).assertEqual(2000 + 30000);
    });

    it('校验成功清零失败计数与等待(F05)', 0, () => {
      let s: LockState = { failCount: 3, lockUntilMs: 0 };
      s = AppLockLogic.resetOnSuccess();
      expect(s.failCount).assertEqual(0);
      expect(s.lockUntilMs).assertEqual(0);
    });

    it('等待期过期后自动归一化清零(F05)', 0, () => {
      const s: LockState = { failCount: 5, lockUntilMs: 1000 };
      const norm: LockState = AppLockLogic.normalizeExpired(s, 2000);
      expect(norm.failCount).assertEqual(0);
      expect(norm.lockUntilMs).assertEqual(0);
    });

    it('锁定态以纯数据持久化，跨后台切换/重启不丢失(F05)', 0, () => {
      // 模拟：锁定态 (failCount, lockUntilMs) 落盘后，进程重启读回同一状态
      const now: number = 5000;
      let s: LockState = AppLockLogic.initial();
      for (let i = 0; i < 5; i++) {
        s = AppLockLogic.registerFailure(s, now, 5, 30000);
      }
      const restored: LockState = { failCount: s.failCount, lockUntilMs: s.lockUntilMs };
      expect(AppLockLogic.isLocked(restored, now + 1000)).assertTrue();
      expect(AppLockLogic.remainingMs(restored, now + 1000)).assertEqual(30000 - 1000);
    });

    it('attemptsLeft 反映剩余可错次数', 0, () => {
      expect(AppLockLogic.attemptsLeft(AppLockLogic.initial(), 5)).assertEqual(5);
      expect(AppLockLogic.attemptsLeft({ failCount: 4, lockUntilMs: 0 }, 5)).assertEqual(1);
    });
  });
}
