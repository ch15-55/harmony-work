import { describe, it, expect } from '@ohos/hypium';
import { ServiceLocator } from '../main/ets/service/ServiceLocator';
import { ISettingsService } from '../main/ets/service/ServiceContracts';

/**
 * 内存版 Settings 桩：实现 ISettingsService 全部契约，状态只存于内存，
 * 不触碰 Preferences / 加密库，用于证明服务层可被注入替换、从而脱离设备单测。
 */
class MemorySettingsStub implements ISettingsService {
  private currency: string = '$';
  private rate: number = 7.2;
  private monthStartDay: number = 1;
  private privacyAgreed: boolean = true;
  private themeMode: number = 0;
  private lockEnabled: boolean = false;
  private pinExists: boolean = false;
  private failCount: number = 0;
  private lockUntil: number = 0;
  private amountHidden: boolean = false;
  private ledgerId: number = 1;

  getCurrency(): string { return this.currency; }
  setCurrency(currency: string): void { this.currency = currency; }
  getCurrencyRate(_currency: string): number { return this.rate; }
  setCurrencyRate(_currency: string, rate: number): void { this.rate = rate; }
  isValidCurrencyRate(rate: number): boolean { return Number.isFinite(rate) && rate > 0; }
  getMonthStartDay(): number { return this.monthStartDay; }
  isPrivacyAgreed(): boolean { return this.privacyAgreed; }
  setPrivacyAgreed(agreed: boolean): void { this.privacyAgreed = agreed; }
  getThemeMode(): number { return this.themeMode; }
  setThemeMode(mode: number): void { this.themeMode = mode; }
  isLockEnabled(): boolean { return this.lockEnabled; }
  hasPin(): boolean { return this.pinExists; }
  getPinFailCount(): number { return this.failCount; }
  getPinLockUntil(): number { return this.lockUntil; }
  resetPinAttempts(): void { this.failCount = 0; this.lockUntil = 0; }
  clearPin(): void { this.pinExists = false; }
  isAmountHidden(): boolean { return this.amountHidden; }
  getCurrentLedgerId(): number { return this.ledgerId; }
}

export default function serviceLocatorTest() {
  describe('ServiceLocator 依赖注入(DI)', () => {
    it('默认绑定指向真实实现且纯函数服务可直接驱动', 0, () => {
      // 金额/日期服务均基于纯函数（MoneyUtil/DateUtil），不依赖 Preferences
      expect(ServiceLocator.money.format(2000)).assertEqual('¥20.00');
      expect(ServiceLocator.date.formatDate(new Date(2026, 4, 19).getTime())).assertEqual('2026-05-19');
    });

    it('可注入内存桩，脱离 Preferences/加密库即可验证', 0, () => {
      const stub = new MemorySettingsStub();
      ServiceLocator.useSettings(stub);
      expect(ServiceLocator.settings.getCurrency()).assertEqual('$');
      expect(ServiceLocator.settings.getCurrencyRate('$')).assertEqual(7.2);
      expect(ServiceLocator.settings.isPrivacyAgreed()).assertTrue();
      ServiceLocator.reset();
    });

    it('reset 恢复真实实现（未初始化时回退默认货币 ¥）', 0, () => {
      const stub = new MemorySettingsStub();
      ServiceLocator.useSettings(stub);
      ServiceLocator.reset();
      // 真实 SettingsService 未初始化时回退 AppConstants.DEFAULT_CURRENCY
      expect(ServiceLocator.settings.getCurrency()).assertEqual('¥');
      // money/date 绑定始终可用，验证 reset 未破坏其它服务
      expect(ServiceLocator.money.format(200000)).assertEqual('¥2,000.00');
    });
  });
}
