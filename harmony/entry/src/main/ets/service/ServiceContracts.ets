/**
 * 模块职责：服务层契约（接口）。
 *
 * 架构背景：原服务均为静态类（如 SettingsService.xxx），优点是无样板代码，
 * 缺点是「无接口、无 DI」——多人并行改动同一文件易冲突，单元测试无法注入桩对象。
 *
 * 本文件只定义契约，不含实现。具体实现仍由现有静态类承担，通过 ServiceLocator
 * 以接口类型暴露，使：
 *   1) 新代码/测试可依赖接口而非具体类，降低耦合；
 *   2) 测试可通过 ServiceLocator 注入内存桩，脱离 Preferences / 加密库即可验证纯逻辑；
 *   3) 后续若需按模块拆分或替换实现，只需新增一个 implements 类并在 Locator 切换。
 *
 * 既有页面继续直接调用 SettingsService.xxx（行为不变），Locator 为可选的现代化入口。
 */
import { AppConstants, ThemeMode } from '../constants/AppConstants';

/** 设置服务契约（货币 / 账期 / 隐私 / 应用锁配置） */
export interface ISettingsService {
  getCurrency(): string;
  setCurrency(currency: string): void;
  getCurrencyRate(currency: string): number;
  setCurrencyRate(currency: string, rate: number): void;
  isValidCurrencyRate(rate: number): boolean;
  getMonthStartDay(): number;
  isPrivacyAgreed(): boolean;
  setPrivacyAgreed(agreed: boolean): void;
  getThemeMode(): number;
  setThemeMode(mode: number): void;
  isLockEnabled(): boolean;
  hasPin(): boolean;
  getPinFailCount(): number;
  getPinLockUntil(): number;
  resetPinAttempts(): void;
  clearPin(): void;
  isAmountHidden(): boolean;
  getCurrentLedgerId(): number;
}

/** 应用锁服务契约（PIN 设置 / 校验 / 重试节制） */
export interface IAppLockService {
  isEnabled(): boolean;
  isLocked(): boolean;
  isUnlocked(): boolean;
  setPin(pin: string): Promise<void>;
  disable(): void;
  verifyPin(pin: string): Promise<boolean>;
  lock(): void;
  unlock(): void;
  getLockoutRemainMs(): number;
  isLockoutActive(): boolean;
  getFailureCount(): number;
  isValidPin(pin: string): boolean;
}

/** 金额换算服务契约（纯函数，便于测试直接注入确定性汇率） */
export interface IMoneyService {
  displayCurrency(): string;
  displayRate(): number;
  display(fen: number, showSign?: boolean): string;
  displayIn(fen: number, currency: string, rate: number, showSign?: boolean): string;
  format(fen: number, currency?: string, showSign?: boolean): string;
}

/** 时间与日期服务契约（纯函数） */
export interface IDateService {
  startOfDay(ts: number): number;
  endOfDay(ts: number): number;
  startOfMonth(ts: number): number;
  endOfMonth(ts: number): number;
  monthKey(ts: number): string;
  isDateOnly(ts: number): boolean;
  formatDate(ts: number): string;
  formatTime(ts: number): string;
  addMonths(ts: number, delta: number): number;
  isFuture(ts: number): boolean;
}
