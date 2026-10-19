/**
 * 模块职责：预置分类单点定义（架构 4.6）。
 * - 支出 11 类 + 收入 6 类，共 17 条，由 SeedDataManager 幂等写入 ll_category（is_system=1）
 * - ⚠️ 合规裁决 D2：PRD 原文收入分类第 3 条已更名为「利息」，
 *   全站分类名、按钮文案、提示语、关于页文本一律执行金融敏感词禁用清单
 *   （PRD F-9.6 / 架构 2.6，逐字清单见 PRD，不在代码注释中复述以免扫描命中）。
 *   分类名修改只需改本文件，改名零成本。
 * 本文件只允许数据，禁止任何逻辑。
 */

/** 预置分类条目结构 */
export interface CategoryPreset {
  /** 分类名 */
  name: string;
  /** 图标标识（映射见 IconConstants；v1.0 图标资源未产出时用字符兜底） */
  icon: string;
  /** 分类色值 */
  color: string;
  /** 排序号（同类型内递增） */
  sortOrder: number;
}

/** 支出分类 11 类（F-1.5） */
export const EXPENSE_CATEGORY_PRESETS: CategoryPreset[] = [
  { name: '餐饮', icon: 'ic_cat_food', color: '#F5544B', sortOrder: 1 },
  { name: '交通', icon: 'ic_cat_traffic', color: '#5B67F5', sortOrder: 2 },
  { name: '购物', icon: 'ic_cat_shop', color: '#8B5CF6', sortOrder: 3 },
  { name: '居住', icon: 'ic_cat_house', color: '#F59E0B', sortOrder: 4 },
  { name: '娱乐', icon: 'ic_cat_game', color: '#EC4899', sortOrder: 5 },
  { name: '医疗', icon: 'ic_cat_medical', color: '#06B6D4', sortOrder: 6 },
  { name: '教育', icon: 'ic_cat_edu', color: '#3B82F6', sortOrder: 7 },
  { name: '人情', icon: 'ic_cat_gift', color: '#F97316', sortOrder: 8 },
  { name: '通讯', icon: 'ic_cat_phone', color: '#14B8A6', sortOrder: 9 },
  { name: '日用', icon: 'ic_cat_daily', color: '#84CC16', sortOrder: 10 },
  { name: '其他', icon: 'ic_cat_more', color: '#8A8F9E', sortOrder: 11 }
];

/** 收入分类 6 类（第 3 条按 D2 裁决定名为「利息」） */
export const INCOME_CATEGORY_PRESETS: CategoryPreset[] = [
  { name: '工资', icon: 'ic_cat_salary', color: '#12B76A', sortOrder: 1 },
  { name: '兼职', icon: 'ic_cat_parttime', color: '#22C55E', sortOrder: 2 },
  { name: '利息', icon: 'ic_cat_interest', color: '#10B981', sortOrder: 3 },
  { name: '红包', icon: 'ic_cat_redpacket', color: '#EF4444', sortOrder: 4 },
  { name: '报销', icon: 'ic_cat_reimburse', color: '#0EA5E9', sortOrder: 5 },
  { name: '其他', icon: 'ic_cat_more', color: '#8A8F9E', sortOrder: 6 }
];

/** 环形图尾部合并（占比 < 2%）后的聚合切片显示名（文案单一真相源在此） */
export const MERGED_OTHER_LABEL: string = '其他';
/** 合并切片的图标与色值（中性灰，与预置「其他」一致） */
export const MERGED_OTHER_ICON: string = 'ic_cat_more';
export const MERGED_OTHER_COLOR: string = '#8A8F9E';
