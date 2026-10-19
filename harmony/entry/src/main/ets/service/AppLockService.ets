/**
 * 模块职责：应用锁服务（架构 T03 / 2.4）。
 * - PIN 设置：随机盐 + PBKDF2(SHA-256) 派生，凭据记录单键写入 Preferences（零权限、纯本地）
 * - 兼容迁移：升级前 `sha256(salt + pin)` 的旧凭据仍可校验，校验成功后自动升级为新格式
 * - 校验 / 锁定态：lock/unlock 只写 AppStorage('locked')，UI 层 PinLockOverlay 响应
 * - 重试节制：连续错误 PIN_MAX_FAILURES 次后进入 PIN_LOCKOUT_MS 等待期；
 *   失败次数与截止时间均持久化在 Preferences，后台切换或重启不会清除
 * - 忘记密码：唯一重置途径是清空全部数据（由调用方二次确认后执行）
 */
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConstants, AppStorageKeys } from '../constants/AppConstants';
import { CryptoUtil } from '../utils/CryptoUtil';
import { SettingsService } from './SettingsService';
import { LogUtil } from '../utils/LogUtil';
import { ErrorMessages } from '../constants/ErrorMessages';

/** 已持久化的 PIN 凭据（算法、迭代次数、盐、派生值） */
class PinCredential {
  public algo: string = '';
  public iterations: number = 0;
  public salt: string = '';
  public hash: string = '';
}

export class AppLockService {
  private static readonly TAG: string = 'AppLockService';

  /** 是否已开启应用锁（有开关且已设置 PIN） */
  public static isEnabled(): boolean {
    return SettingsService.isLockEnabled() && SettingsService.hasPin();
  }

  /** 是否处于锁定态 */
  public static isLocked(): boolean {
    const value: boolean | undefined = AppStorage.get<boolean>(AppStorageKeys.LOCKED);
    return value === true;
  }

  /** 是否已解锁 */
  public static isUnlocked(): boolean {
    return !AppLockService.isLocked();
  }

  /**
   * 设置 / 修改 PIN：生成盐 → PBKDF2 派生 → 单键持久化 → 开启应用锁。
   * 同时清除升级前的旧格式盐与哈希，避免弱哈希残留。
   * @param pin 4 位数字密码
   */
  public static async setPin(pin: string): Promise<void> {
    if (!AppLockService.isValidPin(pin)) {
      throw new Error(ErrorMessages.PIN_FORMAT_INVALID);
    }
    const salt: string = await CryptoUtil.randomHex(CryptoUtil.SALT_BYTES);
    const hash: string = await CryptoUtil.derivePin(pin, salt);
    const record: string = AppLockService.encodeCredential(
      CryptoUtil.PIN_KDF_ALGO, CryptoUtil.PIN_KDF_ITERATIONS, salt, hash);
    SettingsService.setPinV2(record);
    SettingsService.setPinSalt('');
    SettingsService.setPinHash('');
    SettingsService.setLockEnabled(true);
    // 重设 PIN 视为凭据变更，失败计数与等待状态一并清零
    SettingsService.resetPinAttempts();
    LogUtil.i(AppLockService.TAG, 'pin updated');
  }

  /** 关闭应用锁（清除凭据） */
  public static disable(): void {
    SettingsService.clearPin();
    AppStorage.setOrCreate(AppStorageKeys.LOCKED, false);
  }

  /**
   * 校验 PIN（PinLockOverlay 回调 / 修改 PIN 流程内旧密码校验）。
   * - 当前格式：PBKDF2 派生后比对
   * - 升级前格式：单次 SHA-256 比对，成功后立即写入新格式并清除旧哈希（兼容迁移）
   * 等待期内直接拒绝，不做任何派生；校验成功清零失败计数与等待状态。
   */
  public static async verifyPin(pin: string): Promise<boolean> {
    AppLockService.normalizeExpiredLockout();
    if (AppLockService.getLockoutRemainMs() > 0) {
      return false;
    }
    if (!SettingsService.hasPin()) {
      return false;
    }
    const credential: PinCredential | null = AppLockService.parseCredential(SettingsService.getPinV2());
    if (credential !== null) {
      try {
        const hash: string = await CryptoUtil.derivePin(pin, credential.salt, credential.iterations);
        if (hash === credential.hash) {
          SettingsService.resetPinAttempts();
          return true;
        }
        AppLockService.registerFailure();
        return false;
      } catch (e) {
        LogUtil.fail(AppLockService.TAG, 'verify_pin_v2', e as BusinessError);
        return false;
      }
    }
    return await AppLockService.verifyLegacyPin(pin);
  }

  /** 旧格式校验 + 成功即迁移；迁移失败不影响本次解锁结果 */
  private static async verifyLegacyPin(pin: string): Promise<boolean> {
    const salt: string = SettingsService.getPinSalt();
    const stored: string = SettingsService.getPinHash();
    if (salt.length === 0 || stored.length === 0) {
      return false;
    }
    let matched: boolean = false;
    try {
      const hash: string = await CryptoUtil.hashPin(pin, salt);
      matched = hash === stored;
    } catch (e) {
      LogUtil.fail(AppLockService.TAG, 'verify_pin_legacy', e as BusinessError);
      return false;
    }
    if (!matched) {
      AppLockService.registerFailure();
      return false;
    }
    // 迁移：沿用原盐重新派生，单键写入后清除旧哈希；任一失败都保留旧凭据可继续校验
    try {
      const upgraded: string = await CryptoUtil.derivePin(pin, salt);
      SettingsService.setPinV2(AppLockService.encodeCredential(
        CryptoUtil.PIN_KDF_ALGO, CryptoUtil.PIN_KDF_ITERATIONS, salt, upgraded));
      SettingsService.setPinHash('');
      SettingsService.setPinSalt('');
      LogUtil.i(AppLockService.TAG, 'pin credential migrated');
    } catch (e) {
      LogUtil.fail(AppLockService.TAG, 'migrate_pin', e as BusinessError);
    }
    SettingsService.resetPinAttempts();
    return true;
  }

  /** 凭据记录序列化：算法$迭代次数$盐$派生值 */
  private static encodeCredential(algo: string, iterations: number, salt: string, hash: string): string {
    return algo + '$' + iterations.toString() + '$' + salt + '$' + hash;
  }

  /** 解析凭据记录；格式不符或算法未知时返回 null（交由旧格式路径处理） */
  private static parseCredential(record: string): PinCredential | null {
    if (record.length === 0) {
      return null;
    }
    const parts: string[] = record.split('$');
    if (parts.length !== 4 || parts[0] !== CryptoUtil.PIN_KDF_ALGO) {
      return null;
    }
    const iterations: number = parseInt(parts[1], 10);
    if (!Number.isFinite(iterations) || iterations <= 0 || parts[2].length === 0 || parts[3].length === 0) {
      return null;
    }
    const credential: PinCredential = new PinCredential();
    credential.algo = parts[0];
    credential.iterations = iterations;
    credential.salt = parts[2];
    credential.hash = parts[3];
    return credential;
  }

  /**
   * 当前等待剩余毫秒（0 表示可继续校验）。
   * 读取时顺带处理已到期的等待，避免过期状态残留。
   */
  public static getLockoutRemainMs(): number {
    const until: number = SettingsService.getPinLockUntil();
    if (until <= 0) {
      return 0;
    }
    const remain: number = until - Date.now();
    return remain > 0 ? remain : 0;
  }

  /** 是否处于等待期 */
  public static isLockoutActive(): boolean {
    return AppLockService.getLockoutRemainMs() > 0;
  }

  /** 已累计的连续失败次数（仅用于提示与测试，不涉及凭据） */
  public static getFailureCount(): number {
    return SettingsService.getPinFailCount();
  }

  /** 记录一次失败：达到上限即写入等待截止时间（持久化，跨重启生效） */
  private static registerFailure(): void {
    const next: number = SettingsService.getPinFailCount() + 1;
    SettingsService.setPinFailCount(next);
    if (next >= AppConstants.PIN_MAX_FAILURES) {
      SettingsService.setPinLockUntil(Date.now() + AppConstants.PIN_LOCKOUT_MS);
    }
  }

  /** 等待期已过：清除截止时间并重新累计失败次数 */
  private static normalizeExpiredLockout(): void {
    const until: number = SettingsService.getPinLockUntil();
    if (until > 0 && until <= Date.now()) {
      SettingsService.setPinLockUntil(0);
      SettingsService.setPinFailCount(0);
    }
  }

  /** 锁定（写 AppStorage，EntryAbility 冷启动 / 前台超时调用） */
  public static lock(): void {
    AppStorage.setOrCreate(AppStorageKeys.LOCKED, true);
  }

  /** 解锁 */
  public static unlock(): void {
    AppStorage.setOrCreate(AppStorageKeys.LOCKED, false);
  }

  /** PIN 格式校验：指定位数的纯数字 */
  public static isValidPin(pin: string): boolean {
    if (pin.length !== AppConstants.PIN_LENGTH) {
      return false;
    }
    for (let i = 0; i < pin.length; i++) {
      const code: number = pin.charCodeAt(i);
      if (code < 48 || code > 57) {
        return false;
      }
    }
    return true;
  }
}
