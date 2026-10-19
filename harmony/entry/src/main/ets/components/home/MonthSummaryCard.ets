/**
 * 模块职责：月度收支结余卡（架构 T04 home/MonthSummaryCard）。
 * - 三列：本月支出 / 本月收入 / 结余（负数红色提示）；极简风：无图表装饰
 */
import { palette, cardShadow, cardBorderWidth } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';
import { MonthSummary } from '../../model/StatsModels';
import { MoneyUtil } from '../../utils/MoneyUtil';

@Component
export struct MonthSummaryCard {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 月度汇总 */
  @Prop summary: MonthSummary = new MonthSummary();
  /** 月份标签（页面格式化传入，如「5月」） */
  @Prop monthLabel: string = '';

  /** 汇总金额字号随文本长度自适应。 */
  private amountFontSize(fen: number): number {
    const len: number = MoneyUtil.display(fen).length;
    if (len <= 8) {
      return 24;
    }
    if (len <= 10) {
      return 19;
    }
    if (len <= 12) {
      return 15;
    }
    if (len <= 15) {
      return 11;
    }
    return 9;
  }

  /**
   * 金额单元格（无参 Builder：直接绑定 this.summary.*）。
   * ⚠️ ArkUI 铁律：@Builder 按值传参后状态变化不触发内部刷新（记账后收入/结余不更新的根因），
   * 必须无参引用 this.* 保持响应式；kind 取 'expense' | 'income' | 'net'。
   */
  @Builder
  private summaryCell(label: Resource, kind: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize($r('app.float.font_aux'))
        .fontColor(palette(this.isDark).textSecondary)
      if (kind === 'expense') {
        Text(MoneyUtil.display(this.summary.expense))
          .fontSize(this.amountFontSize(this.summary.expense))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.summary.expense === 0 ?
            palette(this.isDark).textSecondary : palette(this.isDark).expense)
          .fontFeature('"tnum" on')
          .width('100%')
          .maxLines(1)
      } else if (kind === 'income') {
        Text(MoneyUtil.display(this.summary.income))
          .fontSize(this.amountFontSize(this.summary.income))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.summary.income === 0 ?
            palette(this.isDark).textSecondary : palette(this.isDark).income)
          .fontFeature('"tnum" on')
          .width('100%')
          .maxLines(1)
      } else {
        Text(MoneyUtil.display(this.summary.net))
          .fontSize(this.amountFontSize(this.summary.net))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.summary.net === 0 ? palette(this.isDark).textSecondary :
            (this.summary.net < 0 ? palette(this.isDark).expense : palette(this.isDark).primary))
          .fontFeature('"tnum" on')
          .width('100%')
          .maxLines(1)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width(0)
    .layoutWeight(1)
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        // 卡头只渲染月份标签：Resource 不能与 string 用 + 拼接，标签由页面按资源格式化后传入
        Text(this.monthLabel)
          .fontSize($r('app.float.font_body'))
          .fontWeight(FontWeight.Bold)
          .fontColor(palette(this.isDark).textPrimary)
      }
      .width('100%')

      Row({ space: 8 }) {
        this.summaryCell($r('app.string.list_month_expense'), 'expense')
        this.summaryCell($r('app.string.list_month_income'), 'income')
        this.summaryCell($r('app.string.list_month_net'), 'net')
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding($r('app.float.card_padding'))
    .borderRadius($r('app.float.radius_card'))
    .backgroundColor(palette(this.isDark).bgCard)
    .borderWidth(cardBorderWidth(this.isDark))
    .borderColor(palette(this.isDark).border)
    .shadow(cardShadow(this.isDark))
  }
}
