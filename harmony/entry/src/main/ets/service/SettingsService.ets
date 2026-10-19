/**
 * 模块职责：Preferences 读写服务（架构 5.1 / T01）。
 * - 存放设置项、隐私同意状态、PIN 盐值与哈希、上次账户/分类等运行态
 * - **隐私同意状态必须走 Preferences 而非 RDB**：数据库初始化之前就要能读到
 *   （架构 1.3「关键顺序约束」），因此本服务必须先于 DatabaseManager 就绪
 * - init() 在 EntryAbility.onCreate 同步完成，之后全部读接口均为同步，保证
 *   隐私前置路由零等待
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConstants, AppStorageKeys, ThemeMode } from '../constants/AppConstants';
import { ErrorMessages } from '../constants/ErrorMessages';
import { LogUtil } from '../utils/LogUtil';

/** Preferences 键名（仅本服务可见的存储布局） */
export class PrefKeys {
  static readonly PRIVACY_AGREED: string = 'privacy_agreed';
  static readonly THEME_MODE: string = 'theme_mode';
  static readonly CURRENCY: string = 'currency';
  /** 外币汇率（1 单位外币 = rate 元基础货币 ¥） */
  static readonly CURRENCY_RATE_USD: string = 'currency_rate_usd';
  static readonly CURRENCY_RATE_EUR: string = 'currency_rate_eur';
  static readonly MONTH_START_DAY: string = 'month_start_day';
  static readonly LOCK_ENABLED: string = 'lock_enabled';
  static readonly PIN_HASH: string = 'pin_hash';
  static readonly PIN_SALT: string = 'pin_salt';
  /**
   * 当前格式的 PIN 凭据记录：`算法$迭代次数$盐$派生值`。
   * 单键写入保证算法、盐、派生值同时生效，避免迁移中途崩溃出现互相不匹配的残留。
   */
  static readonly PIN_V2: string = 'pin_v2';
  /** 连续校验失败次数（持久化：后台切换或重启后仍生效） */
  static readonly PIN_FAIL_COUNT: string = 'pin_fail_count';
  /** 等待期截止时间（UTC 毫秒，0 表示未锁定） */
  static readonly PIN_LOCK_UNTIL: string = 'pin_lock_until';
  static readonly LAST_ACCOUNT_ID: string = 'last_account_id';
  static readonly LAST_CATEGORY_ID: string = 'last_category_id';
  static readonly AMOUNT_HIDDEN: string = 'amount_hidden';
  static readonly LAST_BACKGROUND_AT: string = 'last_background_at';
  /** 当前账本 id（多账本 F-2.6：全局生效，切换后随 DataBus.bump 驱动全站刷新） */
  static readonly CURRENT_LEDGER_ID: string = 'current_ledger_id';
}

export class SettingsService {
  private static readonly TAG: string = 'SettingsService';
  private static pref: preferences.Preferences | null = null;
  private static ready: boolean = false;

  /**
   * 初始化（同步）。重复调用幂等。
   * 必须在 EntryAbility.onCreate 中、任何读取之前调用。
   */
  public static init(context: common.Context): void {
    if (SettingsService.ready) {
      return;
    }
    try {
      SettingsService.pref = preferences.getPreferencesSync(context, {
        name: AppConstants.PREF_NAME
      });
      SettingsService.ready = true;
      SettingsService.publishDisplay();
      LogUtil.i(SettingsService.TAG, 'preferences initialized');
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      // 初始化失败时保持 ready=false，读取接口将回退到默认值，App 仍可进入隐私页
      LogUtil.e(SettingsService.TAG, 'init failed: ' + err.message);
    }
  }

  /** 内部：取 Preferences 实例；未初始化时抛业务异常（调用方不应对未初始化状态静默） */
  private static store(): preferences.Preferences {
    if (SettingsService.pref === null) {
      throw new Error(ErrorMessages.SETTINGS_NOT_INITIALIZED);
    }
    return SettingsService.pref;
  }

  /**
   * 持久化提交。putSync 已写入内存缓存，flush 异步落盘；
   * 失败仅记日志——设置项丢失只影响体验，不应阻断业务流程。
   */
  private static commit(): void {
    try {
      SettingsService.store().flush();
    } catch (e) {
      LogUtil.w(SettingsService.TAG, 'flush failed');
    }
  }

  // ---------- 隐私同意（隐私前置路由依赖，必须同步可读） ----------

  public static isPrivacyAgreed(): boolean {
    if (!SettingsService.ready) {
      // 未初始化（如异常场景）按未同意处理，走隐私弹窗，宁可多弹不可跳过
      return false;
    }
    return SettingsService.store().getSync(PrefKeys.PRIVACY_AGREED, false) as boolean;
  }

  public static setPrivacyAgreed(agreed: boolean): void {
    SettingsService.store().putSync(PrefKeys.PRIVACY_AGREED, agreed);
    SettingsService.commit();
  }

  // ---------- 主题 ----------

  public static getThemeMode(): number {
    if (!SettingsService.ready) {
      return ThemeMode.SYSTEM;
    }
    const value: number = SettingsService.store().getSync(PrefKeys.THEME_MODE, ThemeMode.SYSTEM) as number;
    return value;
  }

  public static setThemeMode(mode: number): void {
    SettingsService.store().putSync(PrefKeys.THEME_MODE, mode);
    SettingsService.commit();
  }

  // ---------- 货币 / 账期 ----------

  public static getCurrency(): string {
    if (!SettingsService.ready) {
      return AppConstants.DEFAULT_CURRENCY;
    }
    return SettingsService.store().getSync(PrefKeys.CURRENCY, AppConstants.DEFAULT_CURRENCY) as string;
  }

  public static setCurrency(currency: string): void {
    SettingsService.store().putSync(PrefKeys.CURRENCY, currency);
    SettingsService.commit();
    SettingsService.publishDisplay();
  }

  /**
   * 把当前展示币种与汇率写入 AppStorage。
   * 订阅了 DISPLAY_CURRENCY / DISPLAY_RATE 的组件（如最近记录条目）据此刷新金额文案，
   * 只影响展示，不触碰数据库中的基准货币金额。
   */
  private static publishDisplay(): void {
    try {
      const currency: string = SettingsService.getCurrency();
      AppStorage.setOrCreate(AppStorageKeys.DISPLAY_CURRENCY, currency);
      AppStorage.setOrCreate(AppStorageKeys.DISPLAY_RATE, SettingsService.getCurrencyRate(currency));
    } catch (e) {
      LogUtil.w(SettingsService.TAG, 'publish display failed');
    }
  }

  /**
   * 取币种汇率（1 单位该币 = 多少元基础货币 ¥）。
   * ¥ 为基础货币恒 1；$ / € 读偏好，默认 7.2 / 7.8，用户可在主题设置页修改。
   */
  public static getCurrencyRate(currency: string): number {
    if (!SettingsService.ready || currency === AppConstants.DEFAULT_CURRENCY) {
      return 1;
    }
    if (currency === '$') {
      const rate: number = SettingsService.store().getSync(PrefKeys.CURRENCY_RATE_USD,
        AppConstants.DEFAULT_RATE_USD) as number;
      return SettingsService.isValidCurrencyRate(rate) ? rate : AppConstants.DEFAULT_RATE_USD;
    }
    if (currency === '€') {
      const rate: number = SettingsService.store().getSync(PrefKeys.CURRENCY_RATE_EUR,
        AppConstants.DEFAULT_RATE_EUR) as number;
      return SettingsService.isValidCurrencyRate(rate) ? rate : AppConstants.DEFAULT_RATE_EUR;
    }
    return 1;
  }

  /** 保存币种汇率（仅 $ / € 可改；非法值忽略） */
  public static setCurrencyRate(currency: string, rate: number): void {
    if (!SettingsService.ready || !SettingsService.isValidCurrencyRate(rate)) {
      return;
    }
    if (currency === '$') {
      SettingsService.store().putSync(PrefKeys.CURRENCY_RATE_USD, rate);
      SettingsService.commit();
      SettingsService.publishDisplay();
    } else if (currency === '€') {
      SettingsService.store().putSync(PrefKeys.CURRENCY_RATE_EUR, rate);
      SettingsService.commit();
      SettingsService.publishDisplay();
    }
  }

  /** 汇率边界由服务层最终兜底，避免绕过 UI 写入异常偏好值。 */
  public static isValidCurrencyRate(rate: number): boolean {
    return Number.isFinite(rate) && rate >= AppConstants.MIN_CURRENCY_RATE &&
      rate <= AppConstants.MAX_CURRENCY_RATE;
  }

  public static getMonthStartDay(): number {
    if (!SettingsService.ready) {
      return 1;
    }
    return SettingsService.store().getSync(PrefKeys.MONTH_START_DAY, 1) as number;
  }

  public static setMonthStartDay(day: number): void {
    SettingsService.store().putSync(PrefKeys.MONTH_START_DAY, day);
    SettingsService.commit();
  }

  // ---------- 应用锁 ----------

  public static isLockEnabled(): boolean {
    if (!SettingsService.ready) {
      return false;
    }
    return SettingsService.store().getSync(PrefKeys.LOCK_ENABLED, false) as boolean;
  }

  public static setLockEnabled(enabled: boolean): void {
    SettingsService.store().putSync(PrefKeys.LOCK_ENABLED, enabled);
    if (!enabled) {
      // 关闭应用锁时同步清除凭据，避免残留哈希
      SettingsService.store().putSync(PrefKeys.PIN_HASH, '');
      SettingsService.store().putSync(PrefKeys.PIN_SALT, '');
    }
    SettingsService.commit();
  }

  public static getPinHash(): string {
    if (!SettingsService.ready) {
      return '';
    }
    return SettingsService.store().getSync(PrefKeys.PIN_HASH, '') as string;
  }

  public static setPinHash(hash: string): void {
    SettingsService.store().putSync(PrefKeys.PIN_HASH, hash);
    SettingsService.commit();
  }

  public static getPinSalt(): string {
    if (!SettingsService.ready) {
      return '';
    }
    return SettingsService.store().getSync(PrefKeys.PIN_SALT, '') as string;
  }

  /** 当前格式凭据记录（见 PrefKeys.PIN_V2 的格式说明） */
  public static getPinV2(): string {
    if (!SettingsService.ready) {
      return '';
    }
    return SettingsService.store().getSync(PrefKeys.PIN_V2, '') as string;
  }

  public static setPinV2(record: string): void {
    SettingsService.store().putSync(PrefKeys.PIN_V2, record);
    SettingsService.commit();
  }

  public static setPinSalt(salt: string): void {
    SettingsService.store().putSync(PrefKeys.PIN_SALT, salt);
    SettingsService.commit();
  }

  /** 是否已设置过 PIN（当前格式记录，或升级前的盐 + 哈希） */
  public static hasPin(): boolean {
    if (SettingsService.getPinV2().length > 0) {
      return true;
    }
    return SettingsService.getPinSalt().length > 0 && SettingsService.getPinHash().length > 0;
  }

  // ---------- 应用锁重试节制（持久化，跨重启生效） ----------

  /** 连续校验失败次数 */
  public static getPinFailCount(): number {
    if (!SettingsService.ready) {
      return 0;
    }
    const value: number = SettingsService.store().getSync(PrefKeys.PIN_FAIL_COUNT, 0) as number;
    if (!Number.isFinite(value) || value <= 0) {
      return 0;
    }
    return Math.floor(value);
  }

  public static setPinFailCount(count: number): void {
    SettingsService.store().putSync(PrefKeys.PIN_FAIL_COUNT, Math.max(0, Math.floor(count)));
    SettingsService.commit();
  }

  /** 等待期截止时间（UTC 毫秒；0 表示当前无等待） */
  public static getPinLockUntil(): number {
    if (!SettingsService.ready) {
      return 0;
    }
    const value: number = SettingsService.store().getSync(PrefKeys.PIN_LOCK_UNTIL, 0) as number;
    if (!Number.isFinite(value) || value <= 0) {
      return 0;
    }
    return Math.floor(value);
  }

  public static setPinLockUntil(until: number): void {
    SettingsService.store().putSync(PrefKeys.PIN_LOCK_UNTIL, Math.max(0, Math.floor(until)));
    SettingsService.commit();
  }

  /** 校验成功或重设 PIN 后清零失败次数与等待状态 */
  public static resetPinAttempts(): void {
    SettingsService.store().putSync(PrefKeys.PIN_FAIL_COUNT, 0);
    SettingsService.store().putSync(PrefKeys.PIN_LOCK_UNTIL, 0);
    SettingsService.commit();
  }

  /** 清除 PIN 凭据（忘记密码重置流程） */
  public static clearPin(): void {
    SettingsService.store().putSync(PrefKeys.PIN_HASH, '');
    SettingsService.store().putSync(PrefKeys.PIN_SALT, '');
    SettingsService.store().putSync(PrefKeys.PIN_V2, '');
    SettingsService.store().putSync(PrefKeys.LOCK_ENABLED, false);
    SettingsService.store().putSync(PrefKeys.PIN_FAIL_COUNT, 0);
    SettingsService.store().putSync(PrefKeys.PIN_LOCK_UNTIL, 0);
    SettingsService.commit();
  }

  // ---------- 记账默认值 ----------

  public static getLastAccountId(): number {
    if (!SettingsService.ready) {
      return 0;
    }
    return SettingsService.store().getSync(PrefKeys.LAST_ACCOUNT_ID, 0) as number;
  }

  public static setLastAccountId(accountId: number): void {
    SettingsService.store().putSync(PrefKeys.LAST_ACCOUNT_ID, accountId);
    SettingsService.commit();
  }

  public static getLastCategoryId(): number {
    if (!SettingsService.ready) {
      return 0;
    }
    return SettingsService.store().getSync(PrefKeys.LAST_CATEGORY_ID, 0) as number;
  }

  public static setLastCategoryId(categoryId: number): void {
    SettingsService.store().putSync(PrefKeys.LAST_CATEGORY_ID, categoryId);
    SettingsService.commit();
  }

  // ---------- 金额隐藏 ----------

  public static isAmountHidden(): boolean {
    if (!SettingsService.ready) {
      return false;
    }
    return SettingsService.store().getSync(PrefKeys.AMOUNT_HIDDEN, false) as boolean;
  }

  public static setAmountHidden(hidden: boolean): void {
    SettingsService.store().putSync(PrefKeys.AMOUNT_HIDDEN, hidden);
    SettingsService.commit();
  }

  // ---------- 当前账本（多账本 F-2.6） ----------

  /**
   * 当前账本 id（同步读，service 层查询条件使用）。
   * 未初始化或无记录时回退默认账本；id 有效性由 LedgerService.resolveCurrent 校验。
   */
  public static getCurrentLedgerId(): number {
    if (!SettingsService.ready) {
      return AppConstants.DEFAULT_LEDGER_ID;
    }
    return SettingsService.store().getSync(PrefKeys.CURRENT_LEDGER_ID,
      AppConstants.DEFAULT_LEDGER_ID) as number;
  }

  public static setCurrentLedgerId(ledgerId: number): void {
    SettingsService.store().putSync(PrefKeys.CURRENT_LEDGER_ID, ledgerId);
    SettingsService.commit();
  }

}
