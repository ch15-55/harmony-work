/**
 * 模块职责：月份切换头（架构 T04 list/MonthSwitcher）。
 * - 「‹ 2026年5月 ›」+ 该月支出/收入/结余三数字
 * - 月份文案由 monthKey('yyyy-MM') 本地拼装（年/月后缀走资源，
 *   数字用 getStringSync 取后缀，避免组件内硬编码中文）
 */
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';
import { MonthSummary } from '../../model/StatsModels';
import { MoneyUtil } from '../../utils/MoneyUtil';
import { common } from '@kit.AbilityKit';

@Component
export struct MonthSwitcher {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 当前月份键 'yyyy-MM' */
  @Prop monthKey: string = '';
  /** 该月收支汇总 */
  @Prop summary: MonthSummary = new MonthSummary();
  /** 上一月回调 */
  onPrev?: () => void;
  /** 下一月回调 */
  onNext?: () => void;

  /** 资源后缀缓存：monthTitle 在 build 内高频调用，避免每次同步读资源管理器 */
  private cachedYearSuffix: string = '';
  private cachedMonthSuffix: string = '';

  /** 'yyyy-MM' → 'yyyy年M月'（后缀取自资源，保证多语言一致） */
  private monthTitle(): string {
    if (this.monthKey.length < 7) {
      return this.monthKey;
    }
    if (this.cachedYearSuffix.length === 0) {
      const context: common.Context = getContext(this) as common.Context;
      this.cachedYearSuffix =
        context.resourceManager.getStringSync($r('app.string.common_year_suffix'));
      this.cachedMonthSuffix =
        context.resourceManager.getStringSync($r('app.string.common_month_suffix'));
    }
    const year: string = this.monthKey.substring(0, 4);
    // 去掉前导零：不用正则字面量（ArkTS strict 不支持 /^0/ 语法）
    const mm: string = this.monthKey.substring(5);
    const month: string = mm.charAt(0) === '0' ? mm.substring(1) : mm;
    return year + this.cachedYearSuffix + month + this.cachedMonthSuffix;
  }

  /** 汇总金额字号随文本长度自适应（单元格约 1/3 行宽，超长金额缩字保证完整显示） */
  private amountFontSize(fen: number): number {
    const len: number = MoneyUtil.display(fen).length;
    if (len <= 10) {
      return 14;
    }
    if (len <= 12) {
      return 12;
    }
    return 10;
  }

  /**
   * 汇总金额单元格（无参 Builder：直接绑定 this.summary.*）。
   * ⚠️ ArkUI 铁律：@Builder 按值传参后状态变化不触发内部刷新，必须引用 this.* 保持响应式。
   */
  @Builder
  private totalCell(labelRes: Resource, kind: string) {
    Column({ space: 2 }) {
      Text(labelRes)
        .fontSize($r('app.float.font_aux'))
        .fontColor(palette(this.isDark).textSecondary)
      if (kind === 'expense') {
        Text(MoneyUtil.display(this.summary.expense))
          .fontSize(this.amountFontSize(this.summary.expense))
          .fontColor(this.summary.expense === 0 ?
            palette(this.isDark).textSecondary : palette(this.isDark).expense)
          .fontFeature('"tnum" on')
          .maxLines(1)
      } else if (kind === 'income') {
        Text(MoneyUtil.display(this.summary.income))
          .fontSize(this.amountFontSize(this.summary.income))
          .fontColor(this.summary.income === 0 ?
            palette(this.isDark).textSecondary : palette(this.isDark).income)
          .fontFeature('"tnum" on')
          .maxLines(1)
      } else {
        Text(MoneyUtil.display(this.summary.net))
          .fontSize(this.amountFontSize(this.summary.net))
          .fontColor(this.summary.net === 0 ? palette(this.isDark).textSecondary :
            (this.summary.net < 0 ? palette(this.isDark).expense : palette(this.isDark).primary))
          .fontFeature('"tnum" on')
          .maxLines(1)
      }
    }
    .layoutWeight(1)
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 16 }) {
        Text('‹')
          .fontSize($r('app.float.font_amount'))
          .fontColor(palette(this.isDark).textPrimary)
          // 触控热区补到 ~44vp（原上下各 4vp 太窄，容易点不中）
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .onClick(() => {
            if (this.onPrev !== undefined) {
              this.onPrev();
            }
          })

        Text(this.monthTitle())
          .fontSize($r('app.float.font_title'))
          .fontWeight(FontWeight.Medium)
          .fontColor(palette(this.isDark).textPrimary)

        Text('›')
          .fontSize($r('app.float.font_amount'))
          .fontColor(palette(this.isDark).textPrimary)
          // 触控热区补到 ~44vp
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .onClick(() => {
            if (this.onNext !== undefined) {
              this.onNext();
            }
          })
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')

      Row({ space: 8 }) {
        this.totalCell($r('app.string.list_month_expense'), 'expense')
        this.totalCell($r('app.string.list_month_income'), 'income')
        this.totalCell($r('app.string.list_month_net'), 'net')
      }
      .width('100%')
    }
    .width('100%')
  }
}
