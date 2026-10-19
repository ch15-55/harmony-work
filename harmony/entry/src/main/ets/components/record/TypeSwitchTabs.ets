/**
 * 模块职责：支出/收入/转账 三态切换胶囊（架构 T04 record/TypeSwitchTabs）。
 * 选中态填充对应类型色（数据驱动取自色板），回调 onTypeChange(TxType)。
 * 本组件不做任何业务，仅负责三态视觉与切换事件。
 */
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys, TxType } from '../../constants/AppConstants';

@Component
export struct TypeSwitchTabs {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 当前选中类型（TxType 值） */
  @Prop selected: number = TxType.EXPENSE;
  /** 是否显示「转账」选项（编辑模式隐藏：Service 层禁止把既有流水改成转账，须删后重记） */
  @Prop showTransfer: boolean = true;
  /** 类型切换回调 */
  onTypeChange?: (txType: number) => void;

  /** 选项列表（ArkTS 不支持在 ForEach 里直接写字面量数组） */
  private typeOptions(): number[] {
    const opts: number[] = [TxType.EXPENSE, TxType.INCOME];
    if (this.showTransfer) {
      opts.push(TxType.TRANSFER);
    }
    return opts;
  }

  /** 类型 → 文案资源 */
  private labelRes(txType: number): Resource {
    if (txType === TxType.INCOME) {
      return $r('app.string.record_type_income');
    }
    if (txType === TxType.TRANSFER) {
      return $r('app.string.record_type_transfer');
    }
    return $r('app.string.record_type_expense');
  }

  /** 类型 → 强调色（选中胶囊填充色） */
  private accentColor(txType: number): string {
    if (txType === TxType.INCOME) {
      return palette(this.isDark).income;
    }
    if (txType === TxType.TRANSFER) {
      return palette(this.isDark).transfer;
    }
    return palette(this.isDark).expense;
  }

  build() {
    Row({ space: 12 }) {
      ForEach(this.typeOptions(), (txType: number) => {
        Text(this.labelRes(txType))
          .fontSize($r('app.float.font_body'))
          .fontWeight(txType === this.selected ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(txType === this.selected ? '#FFFFFF' : palette(this.isDark).textSecondary)
          .textAlign(TextAlign.Center)
          .padding({ left: 20, right: 20, top: 8, bottom: 8 })
          .borderRadius($r('app.float.radius_button'))
          .backgroundColor(txType === this.selected
            ? this.accentColor(txType)
            : palette(this.isDark).bgElevated)
          // 切换时填充色/字重平滑过渡（180ms EaseOut）
          .animation({ duration: 180, curve: Curve.EaseOut })
          .onClick(() => {
            if (this.onTypeChange !== undefined && txType !== this.selected) {
              this.onTypeChange(txType);
            }
          })
      }, (txType: number) => 'tab_' + txType.toString())
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
  }
}
