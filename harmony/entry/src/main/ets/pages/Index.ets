/**
 * 模块职责：主容器（架构 T01 骨架 / T05 交互，PRD 5.2）。
 * - 底部 5 Tab：首页 / 明细 / ＋ / 统计 / 我的；中间「＋」是功能按钮而非页面，
 *   onChange 拦截 index===2 强制回弹并全屏拉起记账页（架构 T05 关键约束 1）
 * - 根布局 Stack 顶层挂载 PinLockOverlay：locked=true 时覆盖全屏（架构 2.4）
 * - 本阶段 Tab 页为占位骨架（T05 填充业务 UI），容器交互已完整可用
 */
import { router } from '@kit.ArkUI';
import { palette } from '../constants/ThemeConstants';
import { AppStorageKeys } from '../constants/AppConstants';
import { RouteConstants } from '../constants/RouteConstants';
import { HomePage } from './HomePage';
import { RecordsPage } from './RecordsPage';
import { PlaceholderPage } from './PlaceholderPage';
import { StatisticsPage } from './StatisticsPage';
import { MinePage } from './MinePage';
import { RecordEditParams } from './RecordEditPage';
import { PinLockOverlay } from '../components/common/PinLockOverlay';
import { ConfirmDialog } from '../components/common/ConfirmDialog';
import { AppLockService } from '../service/AppLockService';
import { MineViewModel } from '../viewmodel/MineViewModel';
import { LogUtil } from '../utils/LogUtil';

@Entry
@Component
struct Index {
  /** 页面转场：被二级页覆盖时轻微视差左移（v1.2 美化，呼应二级页右滑入） */
  pageTransition() {
    PageTransitionExit({ type: RouteType.Push, duration: 300, curve: Curve.EaseOut })
      .translate({ x: '-10%' })
    PageTransitionEnter({ type: RouteType.Pop, duration: 280, curve: Curve.EaseIn })
      .translate({ x: '0%' })
  }

  private static readonly TAG: string = 'Index';
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 应用锁锁定态（EntryAbility 冷启动/超时写入） */
  @StorageLink(AppStorageKeys.LOCKED) locked: boolean = false;
  /** 状态栏/手势条高度（px，WindowUtil 冷启动写入），沉浸式布局下 Tab 区避让 */
  @StorageLink(AppStorageKeys.STATUS_BAR_HEIGHT_PX) statusBarHeightPx: number = 0;
  @StorageLink(AppStorageKeys.NAV_INDICATOR_HEIGHT_PX) navIndicatorHeightPx: number = 0;
  /** 当前选中 Tab（0/1/3/4；2 为记账按钮不落位） */
  @State private currentIndex: number = 0;
  private tabsController: TabsController = new TabsController();
  /** 忘记密码确认弹窗 */
  private forgotDialog: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({
      title: $r('app.string.lock_forgot'),
      message: $r('app.string.lock_forgot_message'),
      confirmText: $r('app.string.lock_btn_reset'),
      danger: true,
      onConfirmed: (): void => {
        this.resetByClearData();
      }
    }),
    autoCancel: false,
    customStyle: false
  });

  /** Tab 符号：鸿蒙系统线条风格符号（SymbolGlyph 渲染） */
  private tabSymbol(index: number): Resource {
    if (index === 0) {
      return $r('sys.symbol.house');
    }
    if (index === 1) {
      return $r('sys.symbol.list_bullet');
    }
    if (index === 2) {
      return $r('sys.symbol.plus');
    }
    if (index === 3) {
      return $r('sys.symbol.data_line');
    }
    return $r('sys.symbol.person');
  }

  aboutToAppear(): void {
    // 预置当前可见 Tab（默认首页），供各 Tab 页在 bump 时判断是否真正需要重载
    AppStorage.setOrCreate(AppStorageKeys.ACTIVE_TAB, this.currentIndex);
  }

  /** 「＋」按钮：强制回弹当前 Tab 并全屏拉起记账页 */
  private openRecordEdit(): void {
    router.pushUrl({
      url: RouteConstants.RECORD_EDIT,
      params: { mode: 'add' } as RecordEditParams
    }).catch((e: Object) => {
      LogUtil.e(Index.TAG, 'pushUrl failed');
    });
  }

  /** PIN 校验（PinLockOverlay 回调）：逻辑收口在 AppLockService（T03 迁入） */
  private async onPinSubmit(pin: string): Promise<boolean> {
    const passed: boolean = await AppLockService.verifyPin(pin);
    if (passed) {
      AppLockService.unlock();
    }
    return passed;
  }

  /** 忘记密码：唯一重置途径是清空全部数据（架构 2.4，明确告知不可恢复） */
  private async resetByClearData(): Promise<void> {
    const result = await MineViewModel.clearAllData();
    if (!result.ok) {
      LogUtil.e(Index.TAG, 'clearAllData failed');
    }
  }

  /** 自绘 Tab 项 */
  @Builder
  tabBuilder(index: number) {
    Column({ space: 3 }) {
      if (index === 2) {
        // 中置「＋」圆钮：主色渐变（Stack 默认中心对齐，保证符号在圆钮正中）
        Stack() {
          SymbolGlyph(this.tabSymbol(2))
            .fontSize(22)
            .fontWeight(FontWeight.Medium)
            .fontColor(['#FFFFFF'])
        }
        .width(44)
        .height(44)
        .borderRadius($r('app.float.radius_circle'))
        .linearGradient({
          angle: 135,
          colors: [[palette(this.isDark).gradStart, 0], [palette(this.isDark).gradEnd, 1]]
        })
        .shadow({
          radius: 8,
          color: palette(this.isDark).shadow,
          offsetY: 2
        })
      } else {
        SymbolGlyph(this.tabSymbol(index))
          .fontSize(22)
          .fontColor([this.currentIndex === index ?
          palette(this.isDark).primary : palette(this.isDark).textSecondary])
        Text(this.tabLabel(index))
          .fontSize(10)
          .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.currentIndex === index ?
          palette(this.isDark).primary : palette(this.isDark).textSecondary)
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  /** Tab 文案（资源引用） */
  private tabLabel(index: number): Resource {
    if (index === 0) {
      return $r('app.string.tab_home');
    }
    if (index === 1) {
      return $r('app.string.tab_records');
    }
    if (index === 3) {
      return $r('app.string.tab_statistics');
    }
    return $r('app.string.tab_mine');
  }

  build() {
    Stack() {
      Column() {
        Tabs({
        barPosition: BarPosition.End,
        index: this.currentIndex,
        controller: this.tabsController
      }) {
        TabContent() {
          HomePage()
        }
        .tabBar(this.tabBuilder(0))

        TabContent() {
          RecordsPage()
        }
        .tabBar(this.tabBuilder(1))

        // 第 3 位是「＋」按钮占位：onChange 中拦截，永不真正切到此页
        TabContent() {
          PlaceholderPage()
        }
        .tabBar(this.tabBuilder(2))

        TabContent() {
          StatisticsPage()
        }
        .tabBar(this.tabBuilder(3))

        TabContent() {
          MinePage()
        }
        .tabBar(this.tabBuilder(4))
      }
      .scrollable(false)
      .animationDuration(260)
      .barHeight(64)
      .barBackgroundColor(palette(this.isDark).bgCard)
      .width('100%')
      .height('100%')
      .onChange((index: number) => {
        if (index === 2) {
          // 关键：强制回弹，防止切换到空占位 Tab
          this.tabsController.changeIndex(this.currentIndex);
          AppStorage.setOrCreate(AppStorageKeys.ACTIVE_TAB, this.currentIndex);
          this.openRecordEdit();
          return;
        }
        // 记录当前可见 Tab，各 Tab 页据此决定 bump 时是否真正重载
        AppStorage.setOrCreate(AppStorageKeys.ACTIVE_TAB, index);
        this.currentIndex = index;
      })
      }
      .width('100%')
      .height('100%')
      .padding({
        top: px2vp(this.statusBarHeightPx),
        bottom: px2vp(this.navIndicatorHeightPx)
      })
      // 锁屏时不把底层账目暴露给无障碍服务（读屏只能读到锁屏内容）
      .accessibilityLevel(this.locked ? 'no-hide-descendants' : 'auto')

      // 应用锁覆盖层（zIndex 最高）
      if (this.locked) {
        PinLockOverlay({
          onSubmit: (pin: string): Promise<boolean> => {
            return this.onPinSubmit(pin);
          },
          onForgot: (): void => {
            this.forgotDialog.open();
          },
          lockedRemainMs: (): number => AppLockService.getLockoutRemainMs()
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).bgPage)
  }
}
