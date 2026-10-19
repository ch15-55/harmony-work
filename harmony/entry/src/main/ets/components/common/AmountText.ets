/**
 * 模块职责：等宽数字金额文本（架构 T01 components/common/AmountText.ets）。
 * - 金额一律由 MoneyUtil 格式化（÷100 铁律）
 * - 支持 hidden 掩码 ****（首页隐私眼睛，F-8.1）
 * - 符号规则：数据库 amount 恒为正；支出显示 -、收入显示 +、转账无符号
 */
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys, TxType } from '../../constants/AppConstants';
import { MoneyUtil } from '../../utils/MoneyUtil';

@Component
export struct AmountText {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 金额（分，恒为正；正负由 txType 决定） */
  @Prop amountFen: number = 0;
  /** 流水类型（TxType），决定颜色与符号 */
  @Prop txType: number = TxType.EXPENSE;
  /** 是否隐藏（掩码显示） */
  @Prop hidden: boolean = false;
  /** 字号覆盖（静态入参，非装饰器属性） */
  fontSizeValue: Resource | number = $r('app.float.font_body');
  /** 是否加粗 */
  @Prop bold: boolean = false;
  /** 颜色覆盖（默认按 txType 自动配色） */
  @Prop colorValue: string = '';
  /** 是否自动配色（支出红/收入绿/转账主色） */
  @Prop autoColor: boolean = true;

  build() {
    Text(this.displayText())
      .fontSize(this.fontSizeValue)
      .fontWeight(this.bold ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.resolveColor())
      .fontFeature('"tnum" on')
      .maxLines(1)
  }

  /** 展示文本：掩码 / 带符号金额 */
  private displayText(): string {
    if (this.hidden) {
      // 资源 → 字符串（$r 返回 Resource，此处需纯文本）
      return getContext(this).resourceManager.getStringSync($r('app.string.common_amount_mask'));
    }
    const showSign: boolean = this.txType === TxType.INCOME;
    if (this.txType === TxType.TRANSFER) {
      // 转账不计入收支，仅展示金额本体
      return MoneyUtil.display(this.amountFen, false);
    }
    return MoneyUtil.display(this.amountFen, showSign);
  }

  /** 按 txType 自动配色 */
  private resolveColor(): string {
    if (this.colorValue.length > 0) {
      return this.colorValue;
    }
    if (!this.autoColor) {
      return palette(this.isDark).textPrimary;
    }
    if (this.txType === TxType.INCOME) {
      return palette(this.isDark).income;
    }
    if (this.txType === TxType.TRANSFER) {
      return palette(this.isDark).transfer;
    }
    return palette(this.isDark).expense;
  }
}
