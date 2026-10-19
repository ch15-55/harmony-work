/**
 * 模块职责：环形图（架构 T04 DonutChart，F-4.2 分类占比 / F-3.3 预算进度环）。
 * - Canvas 自绘：arc() 逐扇区，400ms 逐扇区展开动画（ease-out）
 * - 点击命中：极坐标反算（半径 + 角度 → 扇区索引），回调 onSliceClick(categoryId)
 * - 中心文字用原生 Text 叠层（Stack 居中），空数据画灰色底环 +「暂无数据」（禁止白屏）
 * - 复用为预算进度：传单扇区 + backgroundRemain（剩余部分画底环）
 * 取色全部来自 palette(isDark)（数据驱动），页面 onPageHide 时由父级调用 stopAnim()。
 */
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';
import { CategorySlice } from '../../model/StatsModels';
import { AnimTicket, animProgress, canvasPxPerVp } from './ChartCanvasBase';

@Component
export struct DonutChart {
  /**
   * 主题监听：Canvas 为命令式绘制，切换深色模式时 onReady 不会再次触发，
   * 不监听会导致底环/空态环停留在旧主题色，与中心文字配色不一致。
   */
  @StorageLink(AppStorageKeys.IS_DARK) @Watch('onThemeChanged') isDark: boolean = false;
  /** 分类切片（空数组 → 空态底环）；变化后触发重绘 */
  @Prop @Watch('onDataChanged') slices: CategorySlice[] = [];
  /** 进度环模式下的剩余量（画底环用；分类图传 0）；变化后触发重绘 */
  @Prop @Watch('onDataChanged') backgroundRemain: number = 0;
  /**
   * 最小可见弧长占比（0~1，仅进度环模式生效）。
   * 极小占比时按真实比例几乎不可见，这里只放大图形，中心文字仍用真实比例。
   */
  @Prop @Watch('onDataChanged') minArcRatio: number = 0;
  /** 中心主文本（页面拼装，可含金额或百分比）；变化后触发重绘 */
  @Prop @Watch('onDataChanged') centerText: string = '';
  /** 中心副文本（可选）；变化后触发重绘 */
  @Prop @Watch('onDataChanged') centerSubText: string = '';
  /** 是否播放入场动画 */
  @Prop animate: boolean = true;
  /** 扇区点击回调（categoryId<=0 表示不可下钻） */
  onSliceClick?: (categoryId: number) => void;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  /** 入场进度 0~1 */
  @State private progress: number = 0;
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
    // 必须取消动画，避免页面隐藏后后台空转（架构 1.5 动画约定）
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
    Stack() {
      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .onReady(() => {
          this.draw();
        })
        // 尺寸变化后按新尺寸重绘（首次布局 / 容器尺寸变化），避免停留在旧坐标系
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
              this.hitTest(this.vpx(finger.localX), this.vpx(finger.localY));
            }
          }))

      // 中心文字改用原生 Text 叠层：布局引擎精确居中，规避 Canvas 字体基线估算偏差；
      // Transparent 保证点击穿透到 Canvas 的扇区命中手势
      Column({ space: 2 }) {
        if (this.centerText.length > 0) {
          Text(this.centerText)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(palette(this.isDark).textPrimary)
            .fontFeature('"tnum" on')
            .maxLines(1)
            .maxFontSize(16)
            .minFontSize(11)
            .textAlign(TextAlign.Center)
        }
        if (this.centerSubText.length > 0) {
          Text(this.centerSubText)
            .fontSize(11)
            .fontColor(palette(this.isDark).textSecondary)
            .fontFeature('"tnum" on')
            .maxLines(1)
            .maxFontSize(11)
            .minFontSize(9)
            .textAlign(TextAlign.Center)
        }
      }
      .width('60%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .alignContent(Alignment.Center)
    .width('100%')
    .height('100%')
  }

  /** 数据属性变化回调：Canvas 为命令式绘制，@Prop 更新后须主动重绘（draw 内有尺寸守卫，onReady 前触发安全） */
  private onDataChanged(): void {
    this.draw();
  }

  /** 主题变化回调：重新取色并重绘（draw 内有尺寸守卫，onReady 前触发安全） */
  private onThemeChanged(): void {
    this.draw();
  }

  /** 绘制（px 坐标系） */
  private draw(): void {
    const ctx: CanvasRenderingContext2D = this.ctx;
    const width: number = ctx.width;
    const height: number = ctx.height;
    if (width <= 0 || height <= 0) {
      return;
    }
    ctx.clearRect(0, 0, width, height);
    const cx: number = width / 2;
    const cy: number = height / 2;
    const outer: number = this.outerRadius(width, height);
    const thickness: number = this.ringThickness(outer);
    const radius: number = outer - thickness / 2;

    const totalUsed: number = this.sumSlices();
    const total: number = totalUsed + Math.max(0, this.backgroundRemain);

    // 底环：进度模式画剩余部分，分类模式画空数据底色
    if (this.backgroundRemain > 0 || totalUsed <= 0) {
      ctx.beginPath();
      ctx.lineWidth = thickness;
      ctx.strokeStyle = palette(this.isDark).chartEmpty;
      ctx.arc(cx, cy, radius, 0, Math.PI * 2);
      ctx.stroke();
    }
    if (totalUsed <= 0) {
      return;
    }

    // 扇区：按 sweep 全角 × progress 裁剪，实现逐扇区展开
    const fullAngle: number = Math.PI * 2 * this.progress;
    let startAngle: number = -Math.PI / 2;
    for (let i = 0; i < this.slices.length; i++) {
      const slice: CategorySlice = this.slices[i];
      let sweep: number = (slice.amount / total) * Math.PI * 2;
      // 进度环：占比极小时给一个最小可见弧度，避免看起来「完全没有进度」
      if (this.minArcRatio > 0 && this.backgroundRemain > 0 && this.slices.length === 1) {
        sweep = Math.max(sweep, this.minArcRatio * Math.PI * 2);
      }
      const drawSweep: number = Math.min(sweep, Math.max(0, fullAngle - (startAngle + Math.PI / 2)));
      if (drawSweep > 0) {
        ctx.beginPath();
        ctx.lineWidth = thickness;
        ctx.strokeStyle = slice.color;
        ctx.arc(cx, cy, radius, startAngle, startAngle + drawSweep);
        ctx.stroke();
      }
      startAngle += sweep;
    }
  }

  /** 环外半径（draw / hitTest 共用） */
  private outerRadius(width: number, height: number): number {
    return Math.min(width, height) / 2 - this.vpx(6);
  }

  /** 环厚度（与外半径同源，保证内径推算与扇区绘制一致） */
  private ringThickness(outer: number): number {
    return outer * 0.34;
  }

  /** 极坐标命中：半径在环带内且角度落在某扇区 → 回调 categoryId */
  private hitTest(px: number, py: number): void {
    const width: number = this.ctx.width;
    const height: number = this.ctx.height;
    if (width <= 0 || height <= 0) {
      return;
    }
    const cx: number = width / 2;
    const cy: number = height / 2;
    const outer: number = this.outerRadius(width, height);
    const thickness: number = this.ringThickness(outer);
    const radius: number = outer - thickness / 2;
    const dx: number = px - cx;
    const dy: number = py - cy;
    const dist: number = Math.sqrt(dx * dx + dy * dy);
    if (dist < radius - thickness / 2 || dist > radius + thickness / 2) {
      return;
    }
    const total: number = this.sumSlices() + Math.max(0, this.backgroundRemain);
    if (total <= 0) {
      return;
    }
    // 与绘制同起点（-90°），atan2 结果归一到 [0, 2π)
    let angle: number = Math.atan2(dy, dx) + Math.PI / 2;
    if (angle < 0) {
      angle += Math.PI * 2;
    }
    let cursor: number = 0;
    for (let i = 0; i < this.slices.length; i++) {
      const sweep: number = (this.slices[i].amount / total) * Math.PI * 2;
      if (angle >= cursor && angle < cursor + sweep) {
        if (this.onSliceClick !== undefined && this.slices[i].categoryId > 0) {
          this.onSliceClick(this.slices[i].categoryId);
        }
        return;
      }
      cursor += sweep;
    }
  }

  /** 切片金额合计 */
  private sumSlices(): number {
    let sum: number = 0;
    for (let i = 0; i < this.slices.length; i++) {
      sum += this.slices[i].amount;
    }
    return sum;
  }
}
