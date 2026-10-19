/**
 * 模块职责：自绘计算器键盘（架构 T04 AmountKeyboard，F-1.2）。
 * - 4×4 网格（PRD 线框）：1-9 / ⌫ / ＋ － / . 0 00 / 完成
 * - 求值统一走 ExpressionEvaluator（内部整数分累加），本组件不做金额算术
 * - 表达式实时回调 onExprChange（页面大字展示）；完成键回调 onConfirm(fen)
 * - 键盘主色随支出/收入切换（accentColor 由页面传色板值，数据驱动）
 */
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';
import { ExpressionEvaluator } from '../../utils/ExpressionEvaluator';
import { MoneyUtil } from '../../utils/MoneyUtil';

@Component
export struct AmountKeyboard {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 主色（随支出/收入切换，由页面传 palette 值） */
  @Prop accentColor: string = '#5B67F5';
  /** 表达式变化回调（含空串=清空） */
  onExprChange?: (expr: string) => void;
  /** 完成键回调（fen 为求值结果，可能为 0=无效，页面负责校验提示） */
  onConfirm?: (fen: number) => void;
  /**
   * 清空令牌：页面「再记一笔」后 +1，本组件据此清空内部表达式。
   * 父组件无法持有子组件实例引用，故用令牌代替直接调用 reset()。
   */
  @Prop @Watch('onResetTokenChanged') resetToken: number = 0;
  /** 初始表达式（编辑模式回显已有金额，仅创建时读取一次） */
  @Prop initialExpr: string = '';
  /** 当前表达式（组件内部状态） */
  @State private expr: string = '';
  /** 键盘布局（静态常量，避免 build 每次重建数组；v1.1 去 + -，确定键占 3 格） */
  private static readonly KEY_ROWS: string[][] = [
    ['1', '2', '3', 'del'],
    ['4', '5', '6', '.'],
    ['7', '8', '9', '00'],
    ['0', 'done']
  ];

  aboutToAppear(): void {
    // 编辑模式：把已有金额回灌进键盘（add 模式为空串，无副作用）。
    // 不做 @Prop 双向：后续按键仍以本组件内部 expr 为准，父页面经 onExprChange 感知。
    if (this.initialExpr.length > 0) {
      this.expr = this.initialExpr;
    }
  }

  /** 令牌变化 → 清空表达式（不回调页面，页面自身已重置金额状态） */
  private onResetTokenChanged(propName: string): void {
    this.expr = '';
  }

  build() {
    Column({ space: 10 }) {
      // 表达式回显（12+8 实时可见）
      Text(this.expr.length > 0 ? this.expr : '0')
        .fontSize($r('app.float.font_amount_large'))
        .fontWeight(FontWeight.Medium)
        .fontColor(palette(this.isDark).textPrimary)
        .fontFeature('"tnum" on')
        .maxLines(1)
        .width('100%')
        .textAlign(TextAlign.End)
        .padding({ right: 8 })

      ForEach(AmountKeyboard.KEY_ROWS, (row: string[]) => {
        Row({ space: 10 }) {
          ForEach(row, (key: string) => {
            if (key === 'done') {
              // 完成键：主色渐变，占 3 格醒目位置
              Text($r('app.string.common_confirm'))
                .fontSize($r('app.float.font_title'))
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .textAlign(TextAlign.Center)
                .layoutWeight(3)
                .height(52)
                .borderRadius($r('app.float.radius_button'))
                .linearGradient({
                  angle: 135,
                  colors: [[palette(this.isDark).gradStart, 0], [palette(this.isDark).gradEnd, 1]]
                })
                .onClick(() => {
                  this.tapDone();
                })
            } else if (key === 'del') {
              Text('⌫')
                .fontSize(22)
                .fontColor(palette(this.isDark).textPrimary)
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(52)
                .borderRadius($r('app.float.radius_button'))
                .backgroundColor(palette(this.isDark).bgElevated)
                .onClick(() => {
                  this.tapKey('del');
                })
            } else {
              Text(key)
                .fontSize(22)
                .fontColor(palette(this.isDark).textPrimary)
                .fontFeature('"tnum" on')
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(52)
                .borderRadius($r('app.float.radius_button'))
                .backgroundColor(palette(this.isDark).bgElevated)
                .onClick(() => {
                  this.tapKey(key);
                })
            }
          }, (key: string) => 'kb_' + key)
        }
        .width('100%')
      }, (row: string[], index: number) => 'kbrow_' + index.toString())
    }
    .width('100%')
  }

  /** 按键分发（含 00 键与退格） */
  private tapKey(key: string): void {
    if (key === 'del') {
      this.expr = ExpressionEvaluator.backspace(this.expr);
    } else {
      this.expr = ExpressionEvaluator.appendToken(this.expr, key);
    }
    if (this.onExprChange !== undefined) {
      this.onExprChange(this.expr);
    }
  }

  /** 完成：求值（非法输入 evaluate 返回 0，页面校验提示） */
  private tapDone(): void {
    if (this.onConfirm === undefined) {
      return;
    }
    const fen: number = this.evalFen();
    this.onConfirm(fen);
  }

  /** 供页面读取当前表达式求值结果（分） */
  public currentFen(): number {
    return this.evalFen();
  }

  public currentExpression(): string {
    return this.expr;
  }

  /** 外部清空（「再记一笔」后重置） */
  public reset(): void {
    this.expr = '';
    if (this.onExprChange !== undefined) {
      this.onExprChange(this.expr);
    }
  }

  private evalFen(): number {
    const yuan: number = ExpressionEvaluator.evaluate(this.expr);
    return MoneyUtil.yuanToFen(yuan);
  }
}
