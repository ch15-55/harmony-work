/**
 * 模块职责：设置聚合模型（架构 4.3 AppSettings）。
 * 与 SettingsService 的 Preferences 键一一对应，供「我的」页一次性读取展示。
 */
import { ThemeMode } from '../constants/AppConstants';

export class AppSettings {
  /** 主题模式（ThemeMode） */
  public themeMode: number = ThemeMode.SYSTEM;
  /** 货币符号 */
  public currency: string = '¥';
  /** 每月账期起始日（1-28） */
  public monthStartDay: number = 1;
  /** 应用锁开关 */
  public lockEnabled: boolean = false;
  /** PIN 哈希（不对外展示，仅存在性判断） */
  public pinHash: string = '';
  /** PIN 盐值 */
  public pinSalt: string = '';
  /** 上次记账使用的账户 */
  public lastAccountId: number = 0;
  /** 上次记账使用的分类 */
  public lastCategoryId: number = 0;
  /** 隐私政策是否已同意 */
  public privacyAgreed: boolean = false;
  /** 金额是否隐藏（首页眼睛按钮） */
  public amountHidden: boolean = false;

  /** 是否已设置 PIN */
  public hasPin(): boolean {
    return this.pinSalt.length > 0 && this.pinHash.length > 0;
  }
}
