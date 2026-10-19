/**
 * 模块职责：摘要、密钥派生与随机数（架构 1.1 选型：@kit.CryptoArchitectureKit cryptoFramework）。
 * - 应用锁 PIN：PBKDF2(SHA-256) 派生，替代历史的单次 SHA-256；旧格式仍可校验并在成功时迁移
 * - 随机盐来自系统密码学随机源
 * 本文件不持有状态，所有方法均为纯函数式调用。
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { LogUtil } from './LogUtil';

export class CryptoUtil {
  /** 随机盐字节长度（十六进制串为其 2 倍长） */
  static readonly SALT_BYTES: number = 16;
  /** PIN 派生算法标识（写入凭据记录，用于识别版本） */
  static readonly PIN_KDF_ALGO: string = 'pbkdf2-sha256';
  /** PBKDF2 迭代次数（只提升单次尝试成本，不能弥补 4 位 PIN 的固有空间） */
  static readonly PIN_KDF_ITERATIONS: number = 100000;
  /** 派生密钥长度（字节） */
  static readonly PIN_KDF_KEY_BYTES: number = 32;

  /**
   * 计算文本的 SHA-256 十六进制摘要。
   * 抛出的异常由调用方（AppLockService / 设置页）捕获并转为业务结果。
   */
  public static async sha256Hex(text: string): Promise<string> {
    const encoder: util.TextEncoder = new util.TextEncoder();
    const bytes: Uint8Array = encoder.encodeInto(text);
    const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
    await md.update({ data: bytes });
    const digest: cryptoFramework.DataBlob = await md.digest();
    return CryptoUtil.toHex(digest.data);
  }

  /**
   * 生成指定字节长度的随机盐（十六进制串）。
   * 使用系统密码学安全随机源，不涉及任何设备标识符。
   */
  public static async randomHex(byteLength: number): Promise<string> {
    const rand: cryptoFramework.Random = cryptoFramework.createRandom();
    const blob: cryptoFramework.DataBlob = await rand.generateRandom(byteLength);
    return CryptoUtil.toHex(blob.data);
  }

  /**
   * PIN 加盐哈希（历史格式，单次 SHA-256）。
   * 仅用于校验升级前的既有凭据；新凭据一律走 derivePin。
   */
  public static async hashPin(pin: string, salt: string): Promise<string> {
    return await CryptoUtil.sha256Hex(salt + pin);
  }

  /**
   * PIN 派生（当前格式）：PBKDF2(SHA-256) → 32 字节十六进制。
   * @param salt 十六进制盐串（与历史格式共用同一盐值）
   */
  public static async derivePin(pin: string, salt: string, iterations: number = CryptoUtil.PIN_KDF_ITERATIONS): Promise<string> {
    const encoder: util.TextEncoder = new util.TextEncoder();
    let saltBytes: Uint8Array = CryptoUtil.hexToBytes(salt);
    if (saltBytes.length === 0) {
      // 盐不是合法十六进制时退回按文本取字节，保证仍可派生而不是静默失败
      saltBytes = encoder.encodeInto(salt);
    }
    const kdf: cryptoFramework.Kdf = cryptoFramework.createKdf('PBKDF2|SHA256');
    const spec: cryptoFramework.PBKDF2Spec = {
      algName: 'PBKDF2',
      password: encoder.encodeInto(pin),
      salt: saltBytes,
      iterations: iterations,
      keySize: CryptoUtil.PIN_KDF_KEY_BYTES
    };
    const secret: cryptoFramework.DataBlob = await kdf.generateSecret(spec);
    return CryptoUtil.toHex(secret.data);
  }

  /** 校验随机数生成等系统能力是否可用（供设置页做能力预检） */
  public static isCryptoAvailable(): boolean {
    try {
      cryptoFramework.createMd('SHA256');
      return true;
    } catch (e) {
      LogUtil.w('CryptoUtil', 'crypto capability check failed');
      return false;
    }
  }

  /** 十六进制串 → 字节数组；含非法字符或长度为奇数时返回空数组（由调用方回退） */
  private static hexToBytes(hex: string): Uint8Array {
    if (hex.length === 0 || hex.length % 2 !== 0) {
      return new Uint8Array(0);
    }
    const bytes: Uint8Array = new Uint8Array(hex.length / 2);
    for (let i = 0; i < bytes.length; i++) {
      const high: number = CryptoUtil.hexValue(hex.charAt(i * 2));
      const low: number = CryptoUtil.hexValue(hex.charAt(i * 2 + 1));
      if (high < 0 || low < 0) {
        return new Uint8Array(0);
      }
      bytes[i] = high * 16 + low;
    }
    return bytes;
  }

  private static hexValue(ch: string): number {
    const code: number = ch.charCodeAt(0);
    if (code >= 48 && code <= 57) {
      return code - 48;
    }
    if (code >= 97 && code <= 102) {
      return code - 87;
    }
    if (code >= 65 && code <= 70) {
      return code - 55;
    }
    return -1;
  }

  /** Uint8Array → 十六进制小写串 */
  private static toHex(bytes: Uint8Array): string {    const hexChars: string = '0123456789abcdef';
    let result: string = '';
    for (let i = 0; i < bytes.length; i++) {
      const b: number = bytes[i];
      result += hexChars.charAt((b >> 4) & 0x0F);
      result += hexChars.charAt(b & 0x0F);
    }
    return result;
  }
}
