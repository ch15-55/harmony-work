/**
 * 模块职责：应用锁「重试节制」纯逻辑（F05）。
 * - 把失败计数、等待期计算从 AppLockService 中抽取为无副作用的纯函数，
 *   不涉及 Preferences / AppStorage / 加密库，可在本地单测中直接驱动。
 * - 行为契约（团队标尺「测试保障」维度要求可测）：
 *   1) 连续错误达到 PIN_MAX_FAILURES 次后进入等待期，期间任何校验都直接拒绝；
 *   2) 失败计数与等待截止时间均可被调用方持久化，因此跨后台切换 / 进程重启不丢失；
 *   3) 校验成功后清零失败计数与等待状态；
 *   4) 等待期过期后再次校验会自动归一化（清零），无需人工重置。
 * 注意：本文件只做「给定当前状态，算出下一状态」，持久化由 AppLockService 负责。
 */
import { AppConstants } from '../constants/AppConstants';

/** 锁屏状态（与持久化字段一一对应，毫秒时间戳） */
export interface LockState {
  /** 当前连续失败次数 */
  failCount: number;
  /** 等待期截止毫秒戳（0 表示无等待） */
  lockUntilMs: number;
}

export class AppLockLogic {
  /** 默认连续错误上限（来自架构常量） */
  public static readonly DEFAULT_MAX_FAILURES: number = AppConstants.PIN_MAX_FAILURES;
  /** 默认等待期时长（来自架构常量，毫秒） */
  public static readonly DEFAULT_LOCKOUT_MS: number = AppConstants.PIN_LOCKOUT_MS;

  /** 初始（空闲）状态 */
  public static initial(): LockState {
    return { failCount: 0, lockUntilMs: 0 };
  }

  /** 当前是否处于等待期（nowMs 之后锁定即失效） */
  public static isLocked(state: LockState, nowMs: number): boolean {
    return state.lockUntilMs > 0 && state.lockUntilMs > nowMs;
  }

  /** 等待期剩余毫秒（已过期或无障碍返回 0） */
  public static remainingMs(state: LockState, nowMs: number): number {
    if (state.lockUntilMs <= 0) {
      return 0;
    }
    const remain: number = state.lockUntilMs - nowMs;
    return remain > 0 ? remain : 0;
  }

  /**
   * 记录一次失败，返回新状态（不修改入参）。
   * 达到上限即写入 lockUntilMs = nowMs + lockoutMs，使后续校验在锁定期内一律被拒。
   * 已在锁定期内再次失败会继续顺延截止时间（与线上行为一致）。
   * @param maxFailures 连续错误上限（默认 5）
   * @param lockoutMs 等待期时长（默认 30000）
   */
  public static registerFailure(
    state: LockState,
    nowMs: number,
    maxFailures: number = AppLockLogic.DEFAULT_MAX_FAILURES,
    lockoutMs: number = AppLockLogic.DEFAULT_LOCKOUT_MS
  ): LockState {
    const nextCount: number = state.failCount + 1;
    let lockUntilMs: number = state.lockUntilMs;
    if (nextCount >= maxFailures) {
      lockUntilMs = nowMs + lockoutMs;
    }
    return { failCount: nextCount, lockUntilMs: lockUntilMs };
  }

  /** 校验成功：清零失败计数与等待状态（返回新状态） */
  public static resetOnSuccess(): LockState {
    return { failCount: 0, lockUntilMs: 0 };
  }

  /** 等待期过期时归一化：若 lockUntilMs 已到期则清零失败计数（返回新状态，否则原样） */
  public static normalizeExpired(state: LockState, nowMs: number): LockState {
    if (state.lockUntilMs > 0 && state.lockUntilMs <= nowMs) {
      return { failCount: 0, lockUntilMs: 0 };
    }
    return { failCount: state.failCount, lockUntilMs: state.lockUntilMs };
  }

  /** 还可失败几次才会被锁（用于「还可错 N 次」提示） */
  public static attemptsLeft(state: LockState, maxFailures: number = AppLockLogic.DEFAULT_MAX_FAILURES): number {
    return Math.max(0, maxFailures - state.failCount);
  }
}
