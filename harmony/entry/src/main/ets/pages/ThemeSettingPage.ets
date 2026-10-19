/**
 * 模块职责：主题与货币设置页（架构 T05 / PRD F-7.1 / F-7.2）。
 * - 外观：跟随系统 / 浅色 / 深色 三选一（ThemeStore.setMode 即时生效）
 * - 货币：¥ / $ / € 选择 + 外币汇率编辑（手动汇率，App 无联网）；
 *   切换/改汇率后 DataBus.bump 驱动全站金额按新币种刷新
 * - 文案全走 $r；取色全走 palette；无网络、无第三方
 */
import { router } from '@kit.ArkUI';
import { palette } from '../constants/ThemeConstants';
import { AppStorageKeys, ThemeMode } from '../constants/AppConstants';
import { ThemeStore } from '../viewmodel/ThemeStore';
import { SettingsService } from '../service/SettingsService';
import { DataBus } from '../service/DataBus';
import { NavTitleBar } from '../components/common/NavTitleBar';
import { CardContainer } from '../components/common/CardContainer';
import { ErrorMessages } from '../constants/ErrorMessages';
import { ToastUtil } from '../utils/ToastUtil';
import { MoneyUtil } from '../utils/MoneyUtil';

@Entry
@Component
struct ThemeSettingPage {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  @State private mode: number = ThemeMode.SYSTEM;
  @State private currency: string = '¥';
  /** 当前币种汇率输入框内容（¥ 币种下不渲染输入行） */
  @State private rateText: string = '';

  aboutToAppear(): void {
    this.mode = ThemeStore.currentMode();
    this.currency = SettingsService.getCurrency();
    this.rateText = SettingsService.getCurrencyRate(this.currency).toString();
  }

  private onSelectMode(mode: number): void {
    if (mode === this.mode) {
      return;
    }
    this.mode = mode;
    ThemeStore.setMode(mode);
  }

  private onSelectCurrency(currency: string): void {
    if (currency === this.currency) {
      return;
    }
    this.currency = currency;
    SettingsService.setCurrency(currency);
    this.rateText = SettingsService.getCurrencyRate(currency).toString();
    // 全站金额展示随新币种刷新
    DataBus.bump();
  }

  /** 汇率输入（仅存偏好，失焦时统一 bump 刷新，避免逐键全站重载） */
  private onRateChange(text: string): void {
    this.rateText = text;
    const rate: number | null = this.parseRate(text);
    if (rate !== null) {
      SettingsService.setCurrencyRate(this.currency, rate);
    }
  }

  private onRateBlur(): void {
    const rate: number | null = this.parseRate(this.rateText);
    if (rate === null) {
      // 非法输入回填当前生效值
      this.rateText = SettingsService.getCurrencyRate(this.currency).toString();
      ToastUtil.show(ErrorMessages.CURRENCY_RATE_INVALID);
      return;
    }
    DataBus.bump();
  }

  /** 汇率使用严格金额解析，拒绝如 7abc、Infinity 等部分匹配或异常输入。 */
  private parseRate(text: string): number | null {
    const strict: number | null = MoneyUtil.parseStrictInput(text);
    if (strict === null) {
      return null;
    }
    const rate: number = MoneyUtil.fenToYuan(strict);
    return SettingsService.isValidCurrencyRate(rate) ? rate : null;
  }

  build() {
    Column() {
      NavTitleBar({
        title: $r('app.string.page_theme_setting_title'),
        showBack: true,
        onBack: (): void => {
          router.back();
        }
      })

      Scroll() {
        Column({ space: 12 }) {
          this.groupTitle($r('app.string.theme_mode_label'))
          CardContainer() {
            this.modeOptions()
          }
          this.groupTitle($r('app.string.theme_currency_label'))
          CardContainer() {
            this.currencyOptions()
          }
        }
        .width('100%')
        .padding({ top: 8, bottom: 16 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).bgPage)
  }

  @Builder
  private groupTitle(title: Resource) {
    Text(title)
      .fontSize($r('app.float.font_aux'))
      .fontColor(palette(this.isDark).textSecondary)
      .width('100%')
      .padding({ left: 4, top: 8, bottom: 4 })
  }

  @Builder
  private modeOptions() {
    Column() {
      this.modeRow($r('app.string.mine_theme_system'), ThemeMode.SYSTEM, false)
      this.modeRow($r('app.string.mine_theme_light'), ThemeMode.LIGHT, false)
      this.modeRow($r('app.string.mine_theme_dark'), ThemeMode.DARK, true)
    }
    .width('100%')
  }

  @Builder
  private currencyOptions() {
    Column() {
      this.currencyRow($r('app.string.theme_currency_yuan'), '¥', false)
      this.currencyRow($r('app.string.theme_currency_usd'), '$', false)
      this.currencyRow($r('app.string.theme_currency_euro'), '€', true)
      // 外币选中时显示手动汇率编辑（App 纯本地，无实时汇率）
      if (this.currency !== '¥') {
        Divider()
          .color(palette(this.isDark).divider)
          .strokeWidth(1)
        Row({ space: 12 }) {
          Text($r('app.string.theme_currency_rate_label'))
            .fontSize($r('app.float.font_aux'))
            .fontColor(palette(this.isDark).textSecondary)
            .layoutWeight(1)
          TextInput({ text: this.rateText, placeholder: '7.2' })
            .type(InputType.NUMBER_DECIMAL)
            .fontSize($r('app.float.font_body'))
            .fontColor(palette(this.isDark).textPrimary)
            .textAlign(TextAlign.End)
            .width(120)
            .height(40)
            .backgroundColor(palette(this.isDark).bgPage)
            .borderRadius($r('app.float.radius_tag'))
            .onChange((text: string): void => {
              this.onRateChange(text);
            })
            .onBlur((): void => {
              this.onRateBlur();
            })
        }
        .width('100%')
        .padding({ top: 12, bottom: 12, left: 4, right: 4 })
      }
    }
    .width('100%')
  }

/** 主题单行（选中态内部比较 this.mode，响应式；last 控制分割线） */
  @Builder
  private modeRow(label: Resource, value: number, last: boolean) {
    Row() {
      Text(label)
        .fontSize($r('app.float.font_body'))
        .fontColor(palette(this.isDark).textPrimary)
        .layoutWeight(1)
      if (this.mode === value) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([palette(this.isDark).primary])
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 4, right: 4 })
    .onClick((): void => { this.onSelectMode(value); })

    if (!last) {
      Divider()
        .color(palette(this.isDark).divider)
        .strokeWidth(1)
    }
  }

  /** 币种单行（选中态内部比较 this.currency，响应式） */
  @Builder
  private currencyRow(label: Resource, value: string, last: boolean) {
    Row() {
      Text(label)
        .fontSize($r('app.float.font_body'))
        .fontColor(palette(this.isDark).textPrimary)
        .layoutWeight(1)
      if (this.currency === value) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([palette(this.isDark).primary])
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 4, right: 4 })
    .onClick((): void => { this.onSelectCurrency(value); })

    if (!last) {
      Divider()
        .color(palette(this.isDark).divider)
        .strokeWidth(1)
    }
  }
}
