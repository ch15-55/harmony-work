/**
 * 模块职责：色板系统（架构 9.3，21 键对照表）。
 * 深浅色切换必须数据驱动：组件只写 palette(this.isDark).xxx，
 * 严禁在组件内写 if (isDark) A else B 或硬编码色值。
 * Canvas 无法使用 $r()，图表取色同样从本文件 TS 色板获取。
 * v1.2 美化：新增渐变卡文字色、按压态、功能色淡底与卡片阴影收口（cardShadow）。
 */

/** 卡片阴影取值（结构对齐 ArkUI ShadowOptions，便于统一收口） */
export interface CardShadowValue {
  radius: number;
  color: string;
  offsetX: number;
  offsetY: number;
}

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
  /** 渐变卡（资产大卡）上的主文字色 */
  textOnGradient: string;
  /** 渐变卡上的辅助文字色 */
  textOnGradientSecondary: string;
  /** 按压态背景（按钮/条目按下反馈） */
  bgPress: string;
  /** 主色淡底（选中胶囊/次要按钮底色） */
  primarySoft: string;
  /** 支出淡底（收支徽章/淡色块） */
  expenseSoft: string;
  /** 收入淡底 */
  incomeSoft: string;
  /** 预警淡底 */
  warningSoft: string;
}

/** 浅色色板（极简黑白灰：页面与卡片同色、无阴影、发丝线分层；红绿仅用于金额语义） */
export const LIGHT_PALETTE: Palette = {
  bgPage: '#FFFFFF',
  bgCard: '#FFFFFF',
  bgElevated: '#F4F4F6',
  gradStart: '#1A1C25',
  gradEnd: '#2E313B',
  primary: '#1A1C25',
  expense: '#F5544B',
  income: '#12B76A',
  transfer: '#1A1C25',
  warning: '#F59E0B',
  danger: '#F5544B',
  textPrimary: '#1A1C25',
  textSecondary: '#8A8F9E',
  textTertiary: '#B4B9C7',
  divider: '#EFEFF1',
  mask: '#80000000',
  chartGrid: '#EFEFF1',
  chartAxis: '#8A8F9E',
  chartEmpty: '#EFEFF1',
  shadow: '#00000000',
  border: '#EFEFF1',
  textOnGradient: '#FFFFFF',
  textOnGradientSecondary: '#AEB2BC',
  bgPress: '#ECECEF',
  primarySoft: '#F0F0F2',
  expenseSoft: '#FDEBEA',
  incomeSoft: '#E4F8EF',
  warningSoft: '#FEF4E2'
};

/** 深色色板（同构极简：卡片与页面同色，主色反转为近白） */
export const DARK_PALETTE: Palette = {
  bgPage: '#12141A',
  bgCard: '#12141A',
  bgElevated: '#1E222A',
  gradStart: '#2E323C',
  gradEnd: '#3A3F4C',
  primary: '#EDEEF2',
  expense: '#FF6B61',
  income: '#3DDC97',
  transfer: '#EDEEF2',
  warning: '#FBBF24',
  danger: '#FF6B61',
  textPrimary: '#EDEEF2',
  textSecondary: '#9BA1B0',
  textTertiary: '#6B7280',
  divider: '#262A31',
  mask: '#B3000000',
  chartGrid: '#262A31',
  chartAxis: '#6B7280',
  chartEmpty: '#262A31',
  shadow: '#00000000',
  border: '#262A31',
  textOnGradient: '#FFFFFF',
  textOnGradientSecondary: '#9BA1B0',
  bgPress: '#2A2E38',
  primarySoft: '#262A31',
  expenseSoft: '#3A2523',
  incomeSoft: '#17352A',
  warningSoft: '#3A2E17'
};

/**
 * 按当前深浅状态返回色板。
 * 全站统一入口：palette(this.isDark).bgCard。
 */
export function palette(isDark: boolean): Palette {
  return isDark ? DARK_PALETTE : LIGHT_PALETTE;
}

/**
 * 卡片阴影统一收口（极简风：全面取消投影，层次靠发丝线与留白表达）。
 * 保留函数签名兼容既有调用，恒返回透明值。
 */
export function cardShadow(isDark: boolean): CardShadowValue {
  return { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 };
}

/** 卡片描边宽度统一收口（极简风：无描边，靠 divider 发丝线分层） */
export function cardBorderWidth(isDark: boolean): number {
  return 0;
}
