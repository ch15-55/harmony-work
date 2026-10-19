/**
 * 模块职责：预算设置页（架构 T05 / PRD F-3.1 / F-3.4）。
 * - 读取当月预算（BudgetService.getByMonth），输入金额保存（UPSERT 走唯一索引）
 * - 金额仅经 MoneyUtil（÷100 铁律）；输入为「元」，保存时转分
 * - 三态：LoadingState / ErrorState / 正常；保存后 Toast 反馈
 * - 刷新：onPageShow 重读（Mine/首页改了预算回来可同步）
 */
import { router, KeyboardAvoidMode } from '@kit.ArkUI';
import { palette } from '../constants/ThemeConstants';
import { AppStorageKeys, AppConstants } from '../constants/AppConstants';
import { NavTitleBar } from '../components/common/NavTitleBar';
import { LoadingState } from '../components/common/LoadingState';
import { ErrorState } from '../components/common/ErrorState';
import { MoneyUtil } from '../utils/MoneyUtil';
import { DateUtil } from '../utils/DateUtil';
import { BudgetService } from '../service/BudgetService';
import { ErrorMessages } from '../constants/ErrorMessages';
import { ToastUtil } from '../utils/ToastUtil';

@Entry
@Component
struct BudgetSettingPage {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 底部手势条高度（px）：固定操作区避让，避免保存按钮压在手势条下 */
  @StorageLink(AppStorageKeys.NAV_INDICATOR_HEIGHT_PX) navIndicatorPx: number = 0;
  @State private loading: boolean = true;
  @State private loadFailed: boolean = false;
  /** 当前预算（分） */
  @State private currentFen: number = 0;
  /** 输入框（元，字符串） */
  @State private inputYuan: string = '';
  /** 当前基础货币分值对应的回填文本；未改金额时保留原值，避免外币换算取整漂移。 */
  private inputYuanAtLoad: string = '';
  private monthKey: string = DateUtil.monthKey(DateUtil.now());

  aboutToAppear(): void {
    // 本页高度随键盘收缩（RESIZE），固定底栏的保存按钮因此始终位于键盘上方
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    this.load();
  }

  aboutToDisappear(): void {
    // 恢复全局默认避让模式，避免影响其他页面
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET);
  }

  onPageShow(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.loadFailed = false;
    try {
      const budget = await BudgetService.getByMonth(this.monthKey);
      this.currentFen = budget !== null ? budget.totalAmount : 0;
      // 回填展示币种金额（库中为基础货币）
      this.inputYuan = this.currentFen > 0
        ? MoneyUtil.fenToYuan(MoneyUtil.baseFenToDisplayFen(this.currentFen)).toString() : '';
      this.inputYuanAtLoad = this.inputYuan;
      this.loadFailed = false;
    } catch (e) {
      this.loadFailed = true;
    }
    this.loading = false;
  }

  private async onSave(): Promise<void> {
    const displayFen: number | null = this.inputYuan.trim().length === 0 ? 0 :
      MoneyUtil.parseStrictInput(this.inputYuan);
    if (displayFen === null) {
      ToastUtil.show(ErrorMessages.AMOUNT_INVALID);
      return;
    }
    if (displayFen < 0) {
      ToastUtil.show(ErrorMessages.BUDGET_NEGATIVE);
      return;
    }
    // 外币展示分值无法与基础货币分值严格互逆。未改输入时沿用加载时的原值。
    const fen: number = this.inputYuan === this.inputYuanAtLoad
      ? this.currentFen
      : MoneyUtil.displayFenToBaseFen(displayFen);
    if (!Number.isSafeInteger(fen) || fen > AppConstants.MAX_MONEY_FEN) {
      ToastUtil.show(ErrorMessages.AMOUNT_INVALID);
      return;
    }
    try {
      await BudgetService.save(this.monthKey, fen);
      this.currentFen = fen;
      this.inputYuan = fen > 0 ? MoneyUtil.fenToYuan(MoneyUtil.baseFenToDisplayFen(fen)).toString() : '';
      this.inputYuanAtLoad = this.inputYuan;
      ToastUtil.showRes($r('app.string.budget_save_success'));
    } catch (e) {
      // 负数已在上方校验拦截；此处 catch 是写库等运行时异常，不能误报「不能为负」
      ToastUtil.show(ErrorMessages.SAVE_FAILED);
    }
  }

  build() {
    Column() {
      NavTitleBar({
        title: $r('app.string.page_budget_setting_title'),
        showBack: true,
        onBack: (): void => {
          router.back();
        }
      })

      if (this.loading) {
        LoadingState({ rows: 3 })
      } else if (this.loadFailed) {
        ErrorState({
          onRetry: (): void => { this.load(); }
        })
      } else {
        this.content()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).bgPage)
  }

  @Builder
  private content() {
    Column() {
      Scroll() {
        Column({ space: 12 }) {
          // 当前预算
          Column({ space: 6 }) {
            Text($r('app.string.budget_current_label'))
              .fontSize($r('app.float.font_aux'))
              .fontColor(palette(this.isDark).textSecondary)
              .width('100%')
            Text(this.currentFen > 0 ? MoneyUtil.display(this.currentFen) : $r('app.string.budget_not_set'))
              .fontSize($r('app.float.font_amount'))
              .fontWeight(FontWeight.Medium)
              .fontColor(palette(this.isDark).textPrimary)
              .fontFeature('"tnum" on')
              .width('100%')
          }
          .width('100%')
          .padding($r('app.float.card_padding'))
          .backgroundColor(palette(this.isDark).bgCard)
          .borderRadius($r('app.float.radius_card'))

          // 输入（保存按钮在固定操作区，避免被键盘遮挡）
          Column() {
            TextInput({ text: this.inputYuan, placeholder: $r('app.string.budget_input_hint') })
              .type(InputType.Number)
              .fontSize($r('app.float.font_body'))
              .backgroundColor(palette(this.isDark).bgPage)
              .borderRadius($r('app.float.radius_button'))
              .onChange((value: string): void => {
                this.inputYuan = value;
              })
          }
          .width('100%')
          .padding($r('app.float.card_padding'))
          .backgroundColor(palette(this.isDark).bgCard)
          .borderRadius($r('app.float.radius_card'))
        }
        .width('100%')
        .padding({ top: 8, bottom: 16 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .padding({ left: 16, right: 16 })

      // 固定操作区：页面随键盘收缩时仍位于键盘上方
      Column() {
        Text($r('app.string.common_save'))
          .fontSize($r('app.float.font_body'))
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ top: 13, bottom: 13 })
          .borderRadius($r('app.float.radius_button'))
          .linearGradient({
            angle: 135,
            colors: [[palette(this.isDark).gradStart, 0], [palette(this.isDark).gradEnd, 1]]
          })
          .onClick((): void => {
            this.onSave();
          })
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 8,
        bottom: 8 + px2vp(this.navIndicatorPx)
      })
      .backgroundColor(palette(this.isDark).bgPage)
    }
    .width('100%')
    .layoutWeight(1)
  }
}
