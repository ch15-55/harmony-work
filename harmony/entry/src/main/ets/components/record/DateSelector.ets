/**
 * 模块职责：日期选择行（架构 T04 record/DateSelector）。
 * - 触发行：📅 + 标签 + 当前日期（DateUtil 本地时区格式化）
 * - 弹 DatePickerDialog：allowFuture=false 时 end=今天（禁未来日期，
 *   记账不可记未来账；预算等场景可放开）
 * - 选中回调 onDateChange(本地零点 UTC 毫秒戳)
 */
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';
import { DateUtil } from '../../utils/DateUtil';

@Component
export struct DateSelector {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 当前日期（UTC 毫秒戳） */
  @Prop txDate: number = 0;
  /** 是否允许选择未来日期（默认禁止） */
  @Prop allowFuture: boolean = false;
  /** 日期变更回调 */
  onDateChange?: (ts: number) => void;

  private openPicker(): void {
    const today: Date = new Date();
    // 记账不可记未来账：end 收口到今天 23:59:59 本地时区
    const maxDate: Date = this.allowFuture
      ? new Date(2100, 0, 1)
      : new Date(today.getFullYear(), today.getMonth(), today.getDate(), 23, 59, 59);
    // 防御：txDate 默认值 0 会得到 1970 年（早于 start=2000），此时回退到今天
    const selected: Date = this.txDate > 0
      ? new Date(this.txDate)
      : new Date(today.getFullYear(), today.getMonth(), today.getDate());
    DatePickerDialog.show({
      start: new Date(2000, 0, 1),
      end: maxDate,
      selected: selected,
      lunar: false,
      onDateAccept: (value: Date) => {
        // Date 构造的 month 为 0-based，与 DatePicker 返回值一致
        const picked: Date = new Date(value.getFullYear(), value.getMonth(), value.getDate());
        if (this.onDateChange !== undefined) {
          this.onDateChange(picked.getTime());
        }
      }
    });
  }

  build() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.calendar'))
        .fontSize(16)
      Text($r('app.string.record_date_label'))
        .fontSize($r('app.float.font_body'))
        .fontColor(palette(this.isDark).textSecondary)
      Text(DateUtil.formatDate(this.txDate))
        .fontSize($r('app.float.font_body'))
        .fontColor(palette(this.isDark).textPrimary)
        .layoutWeight(1)
        .textAlign(TextAlign.End)
      Text('›')
        .fontSize($r('app.float.font_title'))
        .fontColor(palette(this.isDark).textTertiary)
    }
    .width('100%')
    .height(48)
    .padding({ left: $r('app.float.card_padding'), right: $r('app.float.card_padding') })
    .borderRadius($r('app.float.radius_button'))
    .backgroundColor(palette(this.isDark).bgElevated)
    .onClick(() => {
      this.openPicker();
    })
  }
}
