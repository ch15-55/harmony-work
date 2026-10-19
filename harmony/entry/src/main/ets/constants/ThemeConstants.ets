/**
 * 模块职责：色板系统（架构 9.3，21 键对照表）。
 * 深浅色切换必须数据驱动：组件只写 palette(this.isDark).xxx，
 * 严禁在组件内写 if (isDark) A else B 或硬编码色值。
 * Canvas 无法使用 $r()，图表取色同样从本文件 TS 色板获取。
 */

/** 主题色板结构（键与架构 9.3 对照表一一对应） */
export interface Palette {
  /** 页面背景 */
  bgPage: string;
  /** 卡片背景 */
  bgCard: string;
  /** 弹层 / 悬浮 */
  bgElevated: string;
  /** 主色渐变起点 */
  gradStart: string;
  /** 主色渐变终点 */
  gradEnd: string;
  /** 主按钮 / 强调 */
  primary: string;
  /** 支出 */
  expense: string;
  /** 收入 */
  income: string;
  /** 转账 */
  transfer: string;
  /** 预算 80% 预警 */
  warning: string;
  /** 超支 / 危险操作 */
  danger: string;
  /** 主文本 */
  textPrimary: string;
  /** 次文本 */
  textSecondary: string;
  /** 辅助文本 */
  textTertiary: string;
  /** 分割线 */
  divider: string;
  /** 遮罩 */
  mask: string;
  /** 图表网格 */
  chartGrid: string;
  /** 坐标轴文字 */
  chartAxis: string;
  /** 空数据底环 */
  chartEmpty: string;
  /** 阴影色（深色模式改用描边，此值失效） */
  shadow: string;
  /** 深色模式卡片描边 / 浅色模式辅助底色 */
  border: string;
}

/** 浅色色板（PRD 5.1 设计语言） */
export const LIGHT_PALETTE: Palette = {
  bgPage: '#F5F6FA',
  bgCard: '#FFFFFF',
  bgElevated: '#FFFFFF',
  gradStart: '#5B67F5',
  gradEnd: '#8B5CF6',
  primary: '#5B67F5',
  expense: '#F5544B',
  income: '#12B76A',
  transfer: '#5B67F5',
  warning: '#F59E0B',
  danger: '#F5544B',
  textPrimary: '#1A1C25',
  textSecondary: '#8A8F9E',
  textTertiary: '#B4B9C7',
  divider: '#EEF0F5',
  mask: '#80000000',
  chartGrid: '#EEF0F5',
  chartAxis: '#8A8F9E',
  chartEmpty: '#EEF0F5',
  shadow: '#0F000000',
  border: '#EEF0F5'
};

/** 深色色板（PRD 5.1：背景 #12141A / 卡片 #1C1F27，支出收入独立色） */
export const DARK_PALETTE: Palette = {
  bgPage: '#12141A',
  bgCard: '#1C1F27',
  bgElevated: '#252932',
  gradStart: '#5B67F5',
  gradEnd: '#8B5CF6',
  primary: '#7B85F7',
  expense: '#FF6B61',
  income: '#3DDC97',
  transfer: '#7B85F7',
  warning: '#FBBF24',
  danger: '#FF6B61',
  textPrimary: '#EDEEF2',
  textSecondary: '#9BA1B0',
  textTertiary: '#6B7280',
  divider: '#2A2E38',
  mask: '#B3000000',
  chartGrid: '#2A2E38',
  chartAxis: '#6B7280',
  chartEmpty: '#2A2E38',
  shadow: '#00000000',
  border: '#2A2E38'
};

/**
 * 按当前深浅状态返回色板。
 * 全站统一入口：palette(this.isDark).bgCard。
 */
export function palette(isDark: boolean): Palette {
  return isDark ? DARK_PALETTE : LIGHT_PALETTE;
}
