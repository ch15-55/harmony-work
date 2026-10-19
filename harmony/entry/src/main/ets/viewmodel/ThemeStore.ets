/**
 * 模块职责：主题中枢（架构 5.1 viewmodel/ThemeStore.ets）。
 * - 持久化主题模式（浅色/深色/跟随系统）并即时应用到窗口 colorMode
 * - 计算当前 isDark 并写入 AppStorage，全站组件通过
 *   @StorageLink(AppConstants.KEY_IS_DARK) + palette(this.isDark) 数据驱动取色，
 *   严禁组件内写 if (isDark) 硬编码分支
 * - 系统深色变化由 EntryAbility.onConfigurationUpdate 通知本类重算
 * - 幂等约束：setColorMode 与 AppStorage 写入均带变更检测，
 *   阻断「apply → setColorMode → onConfigurationUpdate → apply」的递归重入死循环
 */
import { common, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { AppStorageKeys, ThemeMode } from '../constants/AppConstants';
import { LogUtil } from '../utils/LogUtil';
import { SettingsService } from '../service/SettingsService';
import { WindowUtil } from '../utils/WindowUtil';

export class ThemeStore {
  private static readonly TAG: string = 'ThemeStore';
  /** UIAbility 上下文（用于 setColorMode 与读取 config.colorMode） */
  private static context: common.UIAbilityContext | null = null;
  /** 上次实际应用到 ApplicationContext 的 colorMode；null 表示尚未应用过（冷启动首次必应用） */
  private static lastAppliedColorMode: number | null = null;

  /** 初始化：绑定上下文并应用已保存的主题。在 EntryAbility.onCreate 调用。 */
  public static init(context: common.UIAbilityContext): void {
    ThemeStore.context = context;
    ThemeStore.apply(null);
  }

  /** 当前持久化的主题模式 */
  public static currentMode(): number {
    return SettingsService.getThemeMode();
  }

  /** 切换主题模式并立即生效（T05 主题设置页调用） */
  public static setMode(mode: number): void {
    SettingsService.setThemeMode(mode);
    ThemeStore.apply(null);
  }

  /** 当前是否深色（与 AppStorage 同源） */
  public static isDark(): boolean {
    const value: boolean | undefined = AppStorage.get<boolean>(AppStorageKeys.IS_DARK);
    if (value === undefined) {
      return false;
    }
    return value;
  }

  /** 系统深浅模式变化回调（EntryAbility.onConfigurationUpdate） */
  public static onConfigurationUpdate(config: Configuration): void {
    // 仅跟随系统模式下才需要重算；config.colorMode 可能为 undefined，此时按浅色处理
    if (ThemeStore.currentMode() !== ThemeMode.SYSTEM) {
      return;
    }
    const configDark: boolean = config !== undefined && config !== null
      && config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    // 变更检测：回调里算出的深浅与 AppStorage 现值一致，说明是 setColorMode 自身
    // 触发的回声回调而非真实系统变化，直接忽略，避免 apply 重入
    if (configDark !== ThemeStore.isDark()) {
      ThemeStore.apply(configDark);
    }
  }

  /** 应用系统当前深浅模式（架构 T01 施工清单命名 applySystemMode） */
  public static applySystemMode(): void {
    ThemeStore.apply(null);
  }

  /**
   * 内部：应用主题到窗口并同步 AppStorage（幂等：值未变化时跳过底层调用）。
   * @param systemDarkOverride 系统深浅覆盖值：onConfigurationUpdate 路径直接传入
   *   回调参数算出的深浅（避免读 ctx.config 在极端情况下尚未刷新导致滞后）；
   *   其余路径传 null，按原逻辑读 ctx.config
   */
  private static apply(systemDarkOverride: boolean | null): void {
    const mode: number = SettingsService.getThemeMode();
    let dark: boolean = false;
    if (mode === ThemeMode.DARK) {
      dark = true;
    } else if (mode === ThemeMode.SYSTEM) {
      dark = systemDarkOverride !== null ? systemDarkOverride : ThemeStore.isSystemDark();
    }
    // 变更检测：AppStorage 现值相同则跳过写入，避免无谓的全站刷新
    const currentDark: boolean | undefined = AppStorage.get<boolean>(AppStorageKeys.IS_DARK);
    if (currentDark !== dark) {
      AppStorage.setOrCreate(AppStorageKeys.IS_DARK, dark);
    }

    const ctx: common.UIAbilityContext | null = ThemeStore.context;
    if (ctx === null) {
      return;
    }
    // 目标 colorMode 映射：深色/浅色/跟随系统
    let target: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (mode === ThemeMode.DARK) {
      target = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } else if (mode === ThemeMode.LIGHT) {
      target = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    // 幂等：仅当目标值与上次实际应用值不同才调用 setColorMode，
    // 调用成功后记录，从源头阻断 setColorMode → onConfigurationUpdate → apply 的循环
    if (ThemeStore.lastAppliedColorMode !== target) {
      try {
        const appContext: common.ApplicationContext = ctx.getApplicationContext();
        appContext.setColorMode(target);
        ThemeStore.lastAppliedColorMode = target;
      } catch (e) {
        LogUtil.e(ThemeStore.TAG, 'setColorMode failed');
      }
    }
    // 状态栏前景色随主题（深色白字/浅色黑字）；取不到窗口时静默（冷启动早期由 setImmersive 兜底）
    WindowUtil.applyStatusBarByContext(ctx, dark);
    LogUtil.d(ThemeStore.TAG, 'theme applied, isDark=' + dark.toString());
  }

  /** 读取系统当前深色状态 */
  private static isSystemDark(): boolean {
    const ctx: common.UIAbilityContext | null = ThemeStore.context;
    if (ctx === null) {
      return false;
    }
    try {
      const config: Configuration | undefined = ctx.config;
      if (config === undefined || config === null) {
        return false;
      }
      return config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } catch (e) {
      return false;
    }
  }
}
