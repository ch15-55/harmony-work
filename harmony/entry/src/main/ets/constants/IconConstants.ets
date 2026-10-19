/**
 * 模块职责：图标标识 → 视觉资源的映射（架构 3 节 constants/IconConstants.ets）。
 *
 * ⚠️ v1.0 现状说明（对应架构 R10 风险项）：
 * 分类/账户 PNG 图标资源尚未产出（设计侧交付物）。为避免引用不存在的
 * $r('app.media.xxx') 造成编译失败，本版本采用架构 R10 允许的兜底方案——
 * 「色块 + 字符」：iconGlyph() 返回一个单字符符号，由组件在圆形色块上渲染。
 *
 * 图标键名与 CategoryPresets / AccountPresets 中的 icon 字段保持一致；
 * 待设计侧产出 PNG 后，仅需将 glyphMap 的取值替换为 $r('app.media.xxx')
 * 并把返回类型改为 Resource，业务代码零改动。
 */
export class IconConstants {

  /** 图标键 → 兜底字符映射（覆盖 17 个预置分类 + 6 类账户 + 通用） */
  private static readonly GLYPH_MAP: Map<string, string> = new Map([
    // 支出分类
    ['ic_cat_food', '🍜'],
    ['ic_cat_traffic', '🚇'],
    ['ic_cat_shop', '🛍️'],
    ['ic_cat_house', '🏠'],
    ['ic_cat_game', '🎮'],
    ['ic_cat_medical', '💊'],
    ['ic_cat_edu', '📚'],
    ['ic_cat_gift', '🎁'],
    ['ic_cat_phone', '📱'],
    ['ic_cat_daily', '🧴'],
    ['ic_cat_more', '⋯'],
    // 收入分类
    ['ic_cat_salary', '💼'],
    ['ic_cat_parttime', '🧰'],
    ['ic_cat_interest', '🪙'],
    ['ic_cat_redpacket', '🧧'],
    ['ic_cat_reimburse', '🧾'],
    // 自定义分类/实体默认键（model/Category 构造默认值 'more'，无图形时与「其他」一致）
    ['more', '⋯'],
    // 账户类型
    ['ic_acc_cash', '💵'],
    ['ic_acc_debit', '💳'],
    ['ic_acc_credit', '🏧'],
    ['ic_acc_alipay', '🅰️'],
    ['ic_acc_wechat', '💬'],
    ['ic_acc_other', '🗂️'],
    // 通用
    ['ic_common_book', '📒'],
    ['ic_common_wallet', '👛'],
    ['ic_common_none', '·']
  ]);

  /** 分类/账户图标默认兜底键 */
  static readonly DEFAULT_ICON_KEY: string = 'ic_common_none';

  /**
   * 账本可选图标键集合（v1.1 F-10.3，架构 T01）。
   * 从现有通用/账户图标中圈定 8 个，新建与重命名账本时供图标网格选用；
   * LedgerService.create 对不在集合内的取值回退到首个键，保证数据合法。
   */
  static readonly LEDGER_ICON_KEYS: string[] = [
    'ic_common_book',
    'ic_common_wallet',
    'ic_acc_cash',
    'ic_acc_debit',
    'ic_acc_credit',
    'ic_acc_alipay',
    'ic_acc_wechat',
    'ic_acc_other'
  ];

  /** 账本图标默认键（create 入参非法时回退） */
  static readonly DEFAULT_LEDGER_ICON_KEY: string = 'ic_common_book';

  /**
   * 返回图标键对应的兜底字符。
   * 未知键一律返回 DEFAULT_ICON_KEY 的字符，保证 UI 不出现空白。
   */
  static iconGlyph(iconKey: string): string {
    const glyph: string | undefined = IconConstants.GLYPH_MAP.get(iconKey);
    if (glyph !== undefined) {
      return glyph;
    }
    return IconConstants.GLYPH_MAP.get(IconConstants.DEFAULT_ICON_KEY) as string;
  }

  /** 键是否为已登记图标 */
  static hasIcon(iconKey: string): boolean {
    return IconConstants.GLYPH_MAP.has(iconKey);
  }
}
