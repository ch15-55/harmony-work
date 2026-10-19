/**
 * 模块职责：Canvas 图表公共工具（架构 T04 components/chart/ChartCanvasBase.ets）。
 * 非组件文件，只导出工具函数与动画票券：
 * - dp2px / px2dp：画布坐标换算（Canvas 以 px 绘制，手势事件为 vp）
 * - animProgress：入场动画补间（基于 setInterval 16ms；返回 cancel 票券，
 *   页面 onPageHide / 组件 aboutToDisappear 必须调用，避免后台空转）
 * - hexToRgba：色值转透明色（渐变填充用）
 * - drawRoundRect / niceMax
 * 取色一律来自 ThemeConstants 色板，本文件不含任何硬编码业务色。
 */
import { display } from '@kit.ArkUI';

/** 动画票券：调用 cancel() 终止补间 */
export interface AnimTicket {
  cancel: () => void;
}

/** dp → px（画布绘制坐标） */
export function dp2px(dp: number): number {
  const density: number = display.getDefaultDisplaySync().densityPixels;
  return dp * density;
}

/** px → dp（手势命中坐标换算） */
export function px2dp(px: number): number {
  const density: number = display.getDefaultDisplaySync().densityPixels;
  if (density <= 0) {
    return px;
  }
  return px / density;
}

/**
 * 补间动画（ease-out cubic：600ms 进度环 / 400ms 折线揭示）。
 * @param onUpdate 每帧回调，传入当前插值
 * @returns cancel 票券，务必在组件销毁或页面隐藏时调用
 */
export function animProgress(from: number, to: number, duration: number,
  onUpdate: (value: number) => void): AnimTicket {
  const startTime: number = Date.now();
  let finished: boolean = false;
  const timerId: number = setInterval(() => {
    if (finished) {
      return;
    }
    const elapsed: number = Date.now() - startTime;
    const t: number = duration <= 0 ? 1 : Math.min(1, elapsed / duration);
    const eased: number = 1 - Math.pow(1 - t, 3);
    onUpdate(from + (to - from) * eased);
    if (t >= 1) {
      finished = true;
      clearInterval(timerId);
    }
  }, 16);
  return {
    cancel: (): void => {
      finished = true;
      clearInterval(timerId);
    }
  };
}

/** '#RRGGBB' → 'rgba(r,g,b,a)'；非法输入返回原串（深色叠加兜底） */
export function hexToRgba(hex: string, alpha: number): string {
  if (hex.length < 7 || hex.charAt(0) !== '#') {
    return hex;
  }
  const r: number = parseInt(hex.substring(1, 3), 16);
  const g: number = parseInt(hex.substring(3, 5), 16);
  const b: number = parseInt(hex.substring(5, 7), 16);
  if (Number.isNaN(r) || Number.isNaN(g) || Number.isNaN(b)) {
    return hex;
  }
  const clamped: number = Math.max(0, Math.min(1, alpha));
  return 'rgba(' + r.toString() + ',' + g.toString() + ',' + b.toString() + ',' + clamped.toFixed(2) + ')';
}

/** 圆角矩形路径（图表底板 / 气泡） */
export function drawRoundRect(ctx: CanvasRenderingContext2D, x: number, y: number,
  width: number, height: number, radius: number): void {
  const r: number = Math.min(radius, width / 2, height / 2);
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.lineTo(x + width - r, y);
  ctx.arcTo(x + width, y, x + width, y + r, r);
  ctx.lineTo(x + width, y + height - r);
  ctx.arcTo(x + width, y + height, x + width - r, y + height, r);
  ctx.lineTo(x + r, y + height);
  ctx.arcTo(x, y + height, x, y + height - r, r);
  ctx.lineTo(x, y + r);
  ctx.arcTo(x, y, x + r, y, r);
  ctx.closePath();
}

/**
 * 坐标轴上限取整（nice number）：在 1/2/5 × 10^n 步长族中选不小于 value 的档位。
 * 例：8200 → 10000；4500 → 5000；780 → 1000。
 */
export function niceMax(value: number): number {
  if (value <= 0) {
    return 100;
  }
  const exponent: number = Math.floor(Math.log10(value));
  const base: number = Math.pow(10, exponent);
  const fraction: number = value / base;
  let niceFraction: number = 10;
  if (fraction <= 1) {
    niceFraction = 1;
  } else if (fraction <= 2) {
    niceFraction = 2;
  } else if (fraction <= 5) {
    niceFraction = 5;
  }
  return niceFraction * base;
}
