/**
 * 模块职责：服务定位器（轻量 DI 容器）。
 *
 * - 以「接口类型」暴露各服务，默认绑定指向现有静态实现（经由适配器委托，避免
 *   arkts-no-any-unknown 对 `as unknown as` 的禁令，同时保留运行时可替换性）。
 * - 绑定可变：测试或特殊场景可替换为桩实现（如内存版 Settings），无需改动业务代码；
 * - 既有页面仍直接调用 SettingsService.xxx，本定位器为可选的依赖注入入口，行为零影响。
 *
 * 用法示例（测试）：
 *   const stub = new MemorySettingsStub();
 *   ServiceLocator.useSettings(stub);
 *   // ... 执行业务逻辑，断言结果
 *   ServiceLocator.reset();
 */
import { ISettingsService, IAppLockService, IMoneyService, IDateService } from './ServiceContracts';
import { SettingsService } from './SettingsService';
import { AppLockService } from './AppLockService';
import { MoneyUtil } from '../utils/MoneyUtil';
import { DateUtil } from '../utils/DateUtil';

/** 设置服务适配器：把静态 SettingsService 包装为 ISettingsService 实例 */
class SettingsServiceAdapter implements ISettingsService {
  getCurrency(): string { return SettingsService.getCurrency(); }
  setCurrency(currency: string): void { SettingsService.setCurrency(currency); }
  getCurrencyRate(currency: string): number { return SettingsService.getCurrencyRate(currency); }
  setCurrencyRate(currency: string, rate: number): void { SettingsService.setCurrencyRate(currency, rate); }
  isValidCurrencyRate(rate: number): boolean { return SettingsService.isValidCurrencyRate(rate); }
  getMonthStartDay(): number { return SettingsService.getMonthStartDay(); }
  isPrivacyAgreed(): boolean { return SettingsService.isPrivacyAgreed(); }
  setPrivacyAgreed(agreed: boolean): void { SettingsService.setPrivacyAgreed(agreed); }
  getThemeMode(): number { return SettingsService.getThemeMode(); }
  setThemeMode(mode: number): void { SettingsService.setThemeMode(mode); }
  isLockEnabled(): boolean { return SettingsService.isLockEnabled(); }
  hasPin(): boolean { return SettingsService.hasPin(); }
  getPinFailCount(): number { return SettingsService.getPinFailCount(); }
  getPinLockUntil(): number { return SettingsService.getPinLockUntil(); }
  resetPinAttempts(): void { SettingsService.resetPinAttempts(); }
  clearPin(): void { SettingsService.clearPin(); }
  isAmountHidden(): boolean { return SettingsService.isAmountHidden(); }
  getCurrentLedgerId(): number { return SettingsService.getCurrentLedgerId(); }
}

/** 应用锁服务适配器：把静态 AppLockService 包装为 IAppLockService 实例 */
class AppLockServiceAdapter implements IAppLockService {
  isEnabled(): boolean { return AppLockService.isEnabled(); }
  isLocked(): boolean { return AppLockService.isLocked(); }
  isUnlocked(): boolean { return AppLockService.isUnlocked(); }
  async setPin(pin: string): Promise<void> { return AppLockService.setPin(pin); }
  disable(): void { AppLockService.disable(); }
  async verifyPin(pin: string): Promise<boolean> { return AppLockService.verifyPin(pin); }
  lock(): void { AppLockService.lock(); }
  unlock(): void { AppLockService.unlock(); }
  getLockoutRemainMs(): number { return AppLockService.getLockoutRemainMs(); }
  isLockoutActive(): boolean { return AppLockService.isLockoutActive(); }
  getFailureCount(): number { return AppLockService.getFailureCount(); }
  isValidPin(pin: string): boolean { return AppLockService.isValidPin(pin); }
}

/** 金额服务适配器：纯函数包装 */
class MoneyServiceAdapter implements IMoneyService {
  displayCurrency(): string { return MoneyUtil.displayCurrency(); }
  displayRate(): number { return MoneyUtil.displayRate(); }
  display(fen: number, showSign?: boolean): string { return MoneyUtil.display(fen, showSign); }
  displayIn(fen: number, currency: string, rate: number, showSign?: boolean): string {
    return MoneyUtil.displayIn(fen, currency, rate, showSign);
  }
  format(fen: number, currency?: string, showSign?: boolean): string {
    return MoneyUtil.format(fen, currency, showSign);
  }
}

/** 时间服务适配器：纯函数包装 */
class DateServiceAdapter implements IDateService {
  startOfDay(ts: number): number { return DateUtil.startOfDay(ts); }
  endOfDay(ts: number): number { return DateUtil.endOfDay(ts); }
  startOfMonth(ts: number): number { return DateUtil.startOfMonth(ts); }
  endOfMonth(ts: number): number { return DateUtil.endOfMonth(ts); }
  monthKey(ts: number): string { return DateUtil.monthKey(ts); }
  isDateOnly(ts: number): boolean { return DateUtil.isDateOnly(ts); }
  formatDate(ts: number): string { return DateUtil.formatDate(ts); }
  formatTime(ts: number): string { return DateUtil.formatTime(ts); }
  addMonths(ts: number, delta: number): number { return DateUtil.addMonths(ts, delta); }
  isFuture(ts: number): boolean { return DateUtil.isFuture(ts); }
}

export class ServiceLocator {
  private static _settings: ISettingsService = new SettingsServiceAdapter();
  private static _appLock: IAppLockService = new AppLockServiceAdapter();
  private static _money: IMoneyService = new MoneyServiceAdapter();
  private static _date: IDateService = new DateServiceAdapter();

  /** 当前设置服务（接口类型） */
  public static get settings(): ISettingsService {
    return ServiceLocator._settings;
  }

  /** 当前应用锁服务（接口类型） */
  public static get appLock(): IAppLockService {
    return ServiceLocator._appLock;
  }

  /** 当前金额服务（接口类型） */
  public static get money(): IMoneyService {
    return ServiceLocator._money;
  }

  /** 当前时间服务（接口类型） */
  public static get date(): IDateService {
    return ServiceLocator._date;
  }

  /** 注入自定义设置服务（测试桩常用） */
  public static useSettings(svc: ISettingsService): void {
    ServiceLocator._settings = svc;
  }

  /** 注入自定义应用锁服务 */
  public static useAppLock(svc: IAppLockService): void {
    ServiceLocator._appLock = svc;
  }

  /** 注入自定义金额服务 */
  public static useMoney(svc: IMoneyService): void {
    ServiceLocator._money = svc;
  }

  /** 注入自定义时间服务 */
  public static useDate(svc: IDateService): void {
    ServiceLocator._date = svc;
  }

  /** 恢复全部默认实现 */
  public static reset(): void {
    ServiceLocator._settings = new SettingsServiceAdapter();
    ServiceLocator._appLock = new AppLockServiceAdapter();
    ServiceLocator._money = new MoneyServiceAdapter();
    ServiceLocator._date = new DateServiceAdapter();
  }
}
