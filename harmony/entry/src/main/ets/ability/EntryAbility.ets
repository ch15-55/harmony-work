/**
 * 模块职责：应用入口 Ability（架构 2.4 / 5.1 / T01）。
 * 核心职责（按生命周期顺序）：
 * ① onCreate：SettingsService（Preferences）初始化 —— 必须先于 RDB，
 *    隐私同意状态在数据库初始化之前就要能读到（架构 1.3 关键顺序约束）；
 *    ThemeStore 初始化：读主题模式并应用 colorMode；
 * ② onWindowStageCreate：隐私弹窗前置路由 —— 依据 Preferences 的同意状态决定
 *    loadContent('pages/PrivacyPage') 还是 'pages/Index'；
 *    未同意时数据库完全不初始化，杜绝「先渲染主界面再补弹窗」的绕过口子；
 * ③ onForeground / onBackground：应用锁 30 秒超时重锁（AppStorage 'locked'）；
 * ④ onConfigurationUpdate：系统深浅色变化时同步主题。
 */
import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants, AppStorageKeys } from '../constants/AppConstants';
import { RouteConstants } from '../constants/RouteConstants';
import { SettingsService } from '../service/SettingsService';
import { DatabaseManager } from '../service/DatabaseManager';
import { ThemeStore } from '../viewmodel/ThemeStore';
import { WindowUtil } from '../utils/WindowUtil';
import { LogUtil } from '../utils/LogUtil';

export default class EntryAbility extends UIAbility {
  private static readonly TAG: string = 'EntryAbility';
  /** 最近一次切后台的时间戳（应用锁超时判断） */
  private lastBackgroundAt: number = 0;

  /** ① 创建：初始化 Preferences 与主题（顺序不可颠倒） */
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    LogUtil.i(EntryAbility.TAG, 'onCreate');
    // AppStorage 全局键预置，保证首帧前全部就绪
    AppStorage.setOrCreate(AppStorageKeys.DATA_VERSION, 0);
    AppStorage.setOrCreate(AppStorageKeys.LOCKED, false);
    AppStorage.setOrCreate(AppStorageKeys.IS_DARK, false);
    AppStorage.setOrCreate(AppStorageKeys.ACTIVE_TAB, 0);
    // Preferences 先行（不依赖 RDB）
    SettingsService.init(this.context);
    // 主题随后：读 themeMode → setColorMode → 写 isDark
    ThemeStore.init(this.context);
  }

  /** ② 窗口就绪：隐私前置路由 */
  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    LogUtil.i(EntryAbility.TAG, 'onWindowStageCreate');
    await WindowUtil.setImmersive(windowStage);

    // 应用锁冷启动判定：已开启应用锁时直接进入锁定态（PinLockOverlay 覆盖）
    if (SettingsService.isLockEnabled() && SettingsService.hasPin()) {
      AppStorage.setOrCreate(AppStorageKeys.LOCKED, true);
    }

    const agreed: boolean = SettingsService.isPrivacyAgreed();
    if (!agreed) {
      // 首次启动：只加载隐私页。数据库初始化延后到 PrivacyPage「同意并继续」时执行，
      // 保证不同意退出前不产生任何数据落盘
      try {
        await windowStage.loadContent(RouteConstants.PRIVACY);
      } catch (e) {
        const err: BusinessError = e as BusinessError;
        hilog.error(0x5B67, 'EntryAbility', 'loadContent privacy failed: %{public}s', err.message);
      }
      return;
    }

    // 已同意：先初始化数据库（建表/迁移/预置），成功后再进主界面
    try {
      await DatabaseManager.getInstance().init(this.context);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      LogUtil.e(EntryAbility.TAG, 'database init failed: ' + err.message);
      // 初始化失败仍进入主界面，由页面自身的 ErrorState 呈现重试入口，避免白屏
    }
    try {
      await windowStage.loadContent(RouteConstants.INDEX);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.error(0x5B67, 'EntryAbility', 'loadContent index failed: %{public}s', err.message);
    }
  }

  onWindowStageDestroy(): void {
    LogUtil.i(EntryAbility.TAG, 'onWindowStageDestroy');
  }

  /** ④ 切前台：超过 LOCK_TIMEOUT_MS 则重锁 */
  onForeground(): void {
    LogUtil.d(EntryAbility.TAG, 'onForeground');
    if (!SettingsService.isLockEnabled()) {
      return;
    }
    if (this.lastBackgroundAt <= 0) {
      return;
    }
    const awayMs: number = Date.now() - this.lastBackgroundAt;
    if (awayMs > AppConstants.LOCK_TIMEOUT_MS) {
      AppStorage.setOrCreate(AppStorageKeys.LOCKED, true);
    }
  }

  /** ③ 切后台：记录时间戳供 onForeground 判定 */
  onBackground(): void {
    LogUtil.d(EntryAbility.TAG, 'onBackground');
    this.lastBackgroundAt = Date.now();
  }

  /** 系统配置变化：深浅色跟随系统时重算主题 */
  onConfigurationUpdate(newConfig: Configuration): void {
    ThemeStore.onConfigurationUpdate(newConfig);
  }

  onDestroy(): void {
    LogUtil.i(EntryAbility.TAG, 'onDestroy');
    DatabaseManager.getInstance().close();
  }
}
