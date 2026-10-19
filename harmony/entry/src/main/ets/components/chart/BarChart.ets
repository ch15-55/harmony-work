/**
 * 模块职责：双柱状趋势图（F-4.4 收支趋势，替代早期折线版：柱状对月份对比更直观）。
 * - Canvas 自绘：支出/收入双柱并排 + 网格 + X 轴月份标签
 * - 400ms 生长动画（柱高按 progress 从底部升起）
 * - 点击柱组：取最近月份，画布内绘制数值气泡（不用系统 Popup）
 * - Y 轴上限用 niceMax 取整，双序列取同一上限保证可比
 * 取色来自 palette(isDark)；aboutToDisappear 与 stopAnim 取消动画。
 */
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';
import { MonthTrendPoint } from '../../model/StatsModels';
import { MoneyUtil } from '../../utils/MoneyUtil';
import { DateUtil } from '../../utils/DateUtil';
import { AnimTicket, animProgress, canvasPxPerVp, niceMax } from './ChartCanvasBase';

@Component
export struct BarChart {
  /**
   * 主题监听：Canvas 为命令式绘制，切换深色模式时 build 虽会重跑，但 onReady 不会再次触发，
   * 不监听会导致柱体/网格/轴标签停留在旧主题色。
   */
  @StorageLink(AppStorageKeys.IS_DARK) @Watch('onThemeChanged') isDark: boolean = false;
  /** 趋势数据点（升序月份）；变化后触发重绘 */
  @Prop @Watch('onDataChanged') points: MonthTrendPoint[] = [];
  /** 是否播放入场动画 */
  @Prop animate: boolean = true;
  onPointClick?: (monthKey: string) => void;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  @State private progress: number = 0;
  /** 点击选中的月份下标（-1 未选中） */
  @State private selectedIndex: number = -1;
  private ticket: AnimTicket | null = null;
  /** 组件实测宽度（vp，onAreaChange 写入）：自推导画布比例尺用 */
  private areaWidthVp: number = 0;

  /** vp → 画布 px：用实测组件宽推导比例尺（规避 display 密度不一致环境的坐标错位） */
  private vpx(dp: number): number {
    return dp * canvasPxPerVp(this.ctx.width, this.areaWidthVp);
  }

  aboutToAppear(): void {
    if (this.animate) {
      this.progress = 0;
      this.ticket = animProgress(0, 1, 400, (value: number) => {
        this.progress = value;
        this.draw();
      });
    } else {
      this.progress = 1;
    }
  }

  aboutToDisappear(): void {
    this.stopAnim();
  }

  /** 供页面 onPageHide 主动取消动画 */
  public stopAnim(): void {
    if (this.ticket !== null) {
      this.ticket.cancel();
      this.ticket = null;
    }
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .onReady(() => {
        this.draw();
      })
      // 尺寸变化（Tabs 切换 / 首次布局 / 旋转）后按新尺寸重绘，保证图表始终铺满容器
      .onAreaChange((oldArea: Area, newArea: Area) => {
        const w: number = Number(newArea.width);
        if (w > 0 && w !== this.areaWidthVp) {
          this.areaWidthVp = w;
          this.draw();
        }
      })
      .gesture(TapGesture({ fingers: 1 })
        .onAction((event: GestureEvent) => {
          if (event !== undefined && event.fingerList.length > 0) {
            const finger: FingerInfo = event.fingerList[0];
            this.pickNearest(this.vpx(finger.localX));
          }
        }))
  }

  /** 数据属性变化回调：Canvas 为命令式绘制，@Prop 更新后须主动重绘（draw 内有尺寸守卫，onReady 前触发安全） */
  private onDataChanged(): void {
    this.draw();
  }

  /** 主题变化回调：重新取色并重绘（draw 内有尺寸守卫，onReady 前触发安全） */
  private onThemeChanged(): void {
    this.draw();
  }

  private draw(): void {
    const ctx: CanvasRenderingContext2D = this.ctx;
    const width: number = ctx.width;
    const height: number = ctx.height;
    if (width <= 0 || height <= 0 || this.points.length === 0) {
      return;
    }
    ctx.clearRect(0, 0, width, height);

    const padLeft: number = this.vpx(44);
    const padRight: number = this.vpx(10);
    const padTop: number = this.vpx(12);
    const padBottom: number = this.vpx(22);
    const plotWidth: number = width - padLeft - padRight;
    const plotHeight: number = height - padTop - padBottom;
    if (plotWidth <= 0 || plotHeight <= 0) {
      return;
    }

    // Y 轴上限：双序列共用（保证收支可比），niceMax 取整
    let maxValue: number = 0;
    for (let i = 0; i < this.points.length; i++) {
      maxValue = Math.max(maxValue, this.points[i].income, this.points[i].expense);
    }
    const yMax: number = niceMax(maxValue);

    // 网格与 Y 轴刻度（4 等分）；全零数据时 Y 轴只标 0，不画无意义刻度
    ctx.strokeStyle = palette(this.isDark).chartGrid;
    ctx.lineWidth = 1;
    ctx.fillStyle = palette(this.isDark).chartAxis;
    ctx.font = this.vpx(10).toString() + 'px sans-serif';
    ctx.textAlign = 'right';
    ctx.textBaseline = 'middle';
    for (let g = 0; g <= 4; g++) {
      const gy: number = padTop + (plotHeight * g) / 4;
      ctx.beginPath();
      ctx.moveTo(padLeft, gy);
      ctx.lineTo(width - padRight, gy);
      ctx.stroke();
      if (maxValue > 0) {
        const labelFen: number = Math.round(yMax * (4 - g) / 4);
        ctx.fillText(this.shortAmount(labelFen), padLeft - this.vpx(6), gy);
      } else if (g === 4) {
        ctx.fillText('0', padLeft - this.vpx(6), gy);
      }
    }

    // X 轴月份标签（每柱组中心）
    const monthSuffix: string =
      getContext(this).resourceManager.getStringSync($r('app.string.common_month_suffix'));
    const slotWidth: number = plotWidth / this.points.length;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';
    for (let i = 0; i < this.points.length; i++) {
      const cx: number = this.slotCenter(i, padLeft, slotWidth);
      const mm: string = this.points[i].month.substring(5);
      const monthNum: string = mm.charAt(0) === '0' ? mm.substring(1) : mm;
      ctx.fillText(monthNum + monthSuffix, cx, height - padBottom + this.vpx(6));
    }
    if (this.progress <= 0) {
      return;
    }

    // 双柱：支出/收入紧挨并排（gap=0，靠红/绿颜色区分）；组宽不超过槽位 80%，月份之间仍留空隙
    const gap: number = 0;
    let barW: number = Math.min(slotWidth * 0.3, this.vpx(18));
    const maxGroupW: number = slotWidth * 0.8;
    if (barW * 2 > maxGroupW) {
      barW = maxGroupW / 2;
    }
    const groupW: number = barW * 2 + gap;
    const baselineY: number = padTop + plotHeight;
    for (let i = 0; i < this.points.length; i++) {
      const cx: number = this.slotCenter(i, padLeft, slotWidth);
      const expH: number = this.barHeight(this.points[i].expense, yMax, plotHeight);
      const incH: number = this.barHeight(this.points[i].income, yMax, plotHeight);
      // 支出柱（左）
      ctx.fillStyle = palette(this.isDark).expense;
      ctx.fillRect(cx - groupW / 2, baselineY - expH, barW, expH);
      // 收入柱（右）
      ctx.fillStyle = palette(this.isDark).income;
      ctx.fillRect(cx - groupW / 2 + barW + gap, baselineY - incH, barW, incH);
    }

    // 选中气泡（画布内绘制，不用系统 Popup）
    if (this.selectedIndex >= 0 && this.selectedIndex < this.points.length) {
      this.drawBubble(ctx, padLeft, padTop, plotHeight, slotWidth, yMax, this.selectedIndex);
    }
  }

  /** 柱高：数值映射 + 生长动画缩放 */
  private barHeight(valueFen: number, yMax: number, plotHeight: number): number {
    if (yMax <= 0 || valueFen <= 0) {
      return 0;
    }
    return (valueFen / yMax) * plotHeight * this.progress;
  }

  /** 数值气泡：圆角底板 + 月份 + 收支两行 */
  private drawBubble(ctx: CanvasRenderingContext2D, padLeft: number, padTop: number,
    plotHeight: number, slotWidth: number, yMax: number, index: number): void {
    const point: MonthTrendPoint = this.points[index];
    const x: number = this.slotCenter(index, padLeft, slotWidth);
    const y: number = yMax <= 0 ? padTop : padTop + plotHeight -
      (Math.max(point.income, point.expense) / yMax) * plotHeight;

    const bw: number = this.vpx(112);
    const bh: number = this.vpx(52);
    let bx: number = x - bw / 2;
    bx = Math.max(padLeft, Math.min(bx, this.ctx.width - bw - this.vpx(4)));
    let by: number = y - bh - this.vpx(12);
    if (by < padTop) {
      by = y + this.vpx(12);
    }

    ctx.save();
    ctx.shadowColor = palette(this.isDark).shadow;
    ctx.shadowBlur = this.vpx(8);
    ctx.fillStyle = palette(this.isDark).bgElevated;
    const r: number = this.vpx(8);
    ctx.beginPath();
    ctx.moveTo(bx + r, by);
    ctx.arcTo(bx + bw, by, bx + bw, by + bh, r);
    ctx.arcTo(bx + bw, by + bh, bx, by + bh, r);
    ctx.arcTo(bx, by + bh, bx, by, r);
    ctx.arcTo(bx, by, bx + r, by, r);
    ctx.closePath();
    ctx.fill();
    ctx.restore();

    ctx.fillStyle = palette(this.isDark).textPrimary;
    ctx.font = 'bold ' + this.vpx(11).toString() + 'px sans-serif';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    const monthLabel: string = DateUtil.monthLabel(DateUtil.monthKeyToStart(point.month));
    ctx.fillText(monthLabel, bx + this.vpx(10), by + this.vpx(8));
    ctx.font = this.vpx(10).toString() + 'px sans-serif';
    ctx.fillStyle = palette(this.isDark).expense;
    ctx.fillText(MoneyUtil.display(point.expense), bx + this.vpx(10), by + this.vpx(24));
    ctx.fillStyle = palette(this.isDark).income;
    ctx.fillText(MoneyUtil.display(point.income), bx + this.vpx(58), by + this.vpx(24));
  }

  /** 点击：取最近柱组 */
  private pickNearest(px: number): void {
    if (this.points.length === 0) {
      return;
    }
    const width: number = this.ctx.width;
    const padLeft: number = this.vpx(44);
    const padRight: number = this.vpx(10);
    const plotWidth: number = width - padLeft - padRight;
    const slotWidth: number = plotWidth / this.points.length;
    let best: number = 0;
    let bestDist: number = -1;
    for (let i = 0; i < this.points.length; i++) {
      const dist: number = Math.abs(this.slotCenter(i, padLeft, slotWidth) - px);
      if (bestDist < 0 || dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    this.selectedIndex = best;
    this.draw();
    if (this.onPointClick !== undefined) {
      this.onPointClick(this.points[best].month);
    }
  }

  /** 柱组下标 → 组中心 x 坐标 */
  private slotCenter(index: number, padLeft: number, slotWidth: number): number {
    return padLeft + slotWidth * (index + 0.5);
  }

  /** Y 轴短金额（千/万缩写，避免标签过长） */
  private shortAmount(fen: number): string {
    const yuan: number = MoneyUtil.fenToYuan(fen);
    if (yuan >= 10000) {
      return Math.round(yuan / 1000).toString() + 'k';
    }
    return Math.round(yuan).toString();
  }
}
