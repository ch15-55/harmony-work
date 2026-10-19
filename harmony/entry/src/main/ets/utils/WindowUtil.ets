/**
 * 模块职责：窗口与沉浸式状态栏（架构 T01 utils/WindowUtil.ets）。
 * - 冷启动即开启沉浸式全屏布局，页面自行通过 expandSafeArea / padding 处理安全区
 * - 状态栏前景色随主题（深色界面用白字，浅色界面用黑字）
 * - 不持有状态
 */
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LogUtil } from './LogUtil';
import { AppStorageKeys } from '../constants/AppConstants';

export class WindowUtil {
  private static readonly TAG: string = 'WindowUtil';

  /**
   * 开启沉浸式：全屏布局 + 透明状态栏/导航栏。
   * 同时记录状态栏高度到 AppStorage（px），供 NavTitleBar 等顶部组件避让。
   * 状态栏前景色按当前主题（ThemeStore.init 在 onCreate 已写入 IS_DARK）。
   * 失败仅记日志，不阻断启动流程（个别模拟器可能不支持）。
   */
  public static async setImmersive(windowStage: window.WindowStage): Promise<void> {
    try {
      const mainWin: window.Window = await windowStage.getMainWindow();
      await mainWin.setWindowLayoutFullScreen(true);
      WindowUtil.recordAvoidAreas(mainWin);
      const dark: boolean | undefined = AppStorage.get<boolean>(AppStorageKeys.IS_DARK);
      await WindowUtil.applyStatusBar(mainWin, dark === true);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      LogUtil.fail(WindowUtil.TAG, 'set_immersive', err);
    }
  }

  /** 状态栏 + 底部手势条避让高度（px）写入 AppStorage；失败静默（组件侧按 0 处理） */
  private static recordAvoidAreas(mainWin: window.Window): void {
    try {
      const systemArea: window.AvoidArea =
        mainWin.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      AppStorage.setOrCreate(AppStorageKeys.STATUS_BAR_HEIGHT_PX, systemArea.topRect.height);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      LogUtil.fail(WindowUtil.TAG, 'status_bar_area', err);
    }
    try {
      const navArea: window.AvoidArea =
        mainWin.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      AppStorage.setOrCreate(AppStorageKeys.NAV_INDICATOR_HEIGHT_PX, navArea.bottomRect.height);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      LogUtil.fail(WindowUtil.TAG, 'nav_indicator_area', err);
    }
  }

  /** 主题变化后更新状态栏前景色 */
  public static async applyStatusBar(mainWin: window.Window, isDark: boolean): Promise<void> {
    try {
      await mainWin.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: isDark ? '#FFFFFF' : '#1A1C25',
        navigationBarColor: '#00000000',
        navigationBarContentColor: isDark ? '#FFFFFF' : '#1A1C25'
      });
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      LogUtil.fail(WindowUtil.TAG, 'apply_status_bar', err);
    }
  }

  /** 便捷方法：从 WindowStage 取主窗口后更新状态栏 */
  public static async applyStatusBarByStage(windowStage: window.WindowStage, isDark: boolean): Promise<void> {
    try {
      const mainWin: window.Window = await windowStage.getMainWindow();
      await WindowUtil.applyStatusBar(mainWin, isDark);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      LogUtil.fail(WindowUtil.TAG, 'apply_status_bar_stage', err);
    }
  }

  /** 便捷方法：按 Context 取最近窗口更新状态栏（主题切换时 ThemeStore 调用） */
  public static async applyStatusBarByContext(context: common.Context, isDark: boolean): Promise<void> {
    try {
      const mainWin: window.Window = await window.getLastWindow(context);
      await WindowUtil.applyStatusBar(mainWin, isDark);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      LogUtil.fail(WindowUtil.TAG, 'apply_status_bar_context', err);
    }
  }
}
