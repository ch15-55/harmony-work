/**
 * 模块职责：全局常量单点定义（架构文档 4.4 节）。
 * - 业务枚举：流水类型 / 分类类型 / 账户类型 / 主题模式 / 预算分级
 * - AppStorage 键名（全项目仅 3 个键，见架构 1.4）
 * - 阈值与默认值
 * 本文件只允许常量与类型定义，禁止任何业务逻辑。
 */

/** 流水类型：数据库 ll_transaction.type */
export enum TxType {
  EXPENSE = 0,
  INCOME = 1,
  TRANSFER = 2
}

/** 分类类型：数据库 ll_category.type */
export enum CategoryType {
  EXPENSE = 0,
  INCOME = 1
}

/** 账户类型：数据库 ll_account.type */
export enum AccountType {
  CASH = 0,
  DEBIT = 1,
  CREDIT = 2,
  ALIPAY = 3,
  WECHAT = 4,
  OTHER = 5
}

/** 主题模式：Preferences 中存储的取值 */
export enum ThemeMode {
  SYSTEM = 0,
  LIGHT = 1,
  DARK = 2
}

/** 预算消耗分级：正常 / 80% 预警 / 超支 */
export enum BudgetLevel {
  NORMAL = 0,
  WARN = 1,
  OVER = 2
}

/** AppStorage 全局键（架构 1.4） */
export class AppStorageKeys {
  /** 当前是否深色，由 ThemeStore 数据驱动写入，全站组件只读 */
  static readonly IS_DARK: string = 'isDark';
  /** 数据版本号：任何写库操作后 +1，页面 @Watch 重载（架构唯一刷新机制） */
  static readonly DATA_VERSION: string = 'dataVersion';
  /** 当前可见 Tab 下标（Index.onChange 写入）：bump 唤醒所有 Tab 时，
   *  仅当前可见 Tab 真正重载，其余置脏标记、切到才加载，避免保存瞬间并发全量 SQL 卡顿 */
  static readonly ACTIVE_TAB: string = 'activeTab';
  /** 应用锁是否处于锁定态 */
  static readonly LOCKED: string = 'locked';
  /** 状态栏高度（单位 px，WindowUtil 冷启动写入，沉浸式避让用；未取到时为 0） */
  static readonly STATUS_BAR_HEIGHT_PX: string = 'statusBarHeightPx';
  /** 底部手势条高度（单位 px，WindowUtil 冷启动写入，沉浸式避让用；未取到时为 0） */
  static readonly NAV_INDICATOR_HEIGHT_PX: string = 'navIndicatorHeightPx';
  /**
   * 当前展示币种符号（SettingsService 写入）。
   * 列表项等长生命周期组件订阅此键，切币种后无需整页重建即可刷新金额文案。
   */
  static readonly DISPLAY_CURRENCY: string = 'displayCurrency';
  /** 当前展示币种汇率（1 单位展示币 = 多少元基础货币；随币种/汇率修改同步写入） */
  static readonly DISPLAY_RATE: string = 'displayRate';
}

/** 项目级常量与阈值 */
export class AppConstants {
  /** v1.0 唯一账本 id（数据模型预留 ledger_id，UI 不开放切换） */
  static readonly DEFAULT_LEDGER_ID: number = 1;

  /** RDB 数据库文件名 */
  static readonly DB_NAME: string = 'lifeledger.db';
  /** Preferences 文件名（隐私同意状态等，须在 RDB 之前可读） */
  static readonly PREF_NAME: string = 'lifeledger_settings';

  /** 备注输入上限（字符） */
  static readonly MAX_NOTE_LENGTH: number = 100;
  /** 单笔凭证图片上限（v1.1 启用） */
  static readonly MAX_IMAGE_COUNT: number = 3;
  /** 预算黄色预警阈值（已用占比） */
  static readonly BUDGET_WARN_RATIO: number = 0.8;
  /** 后台超时重锁时长（毫秒） */
  static readonly LOCK_TIMEOUT_MS: number = 30000;
  /** PIN 密码位数 */
  static readonly PIN_LENGTH: number = 4;
  /** 连续错误达到该次数后进入等待期 */
  static readonly PIN_MAX_FAILURES: number = 5;
  /** PIN 等待期时长（毫秒）：连续错误达到上限后必须等待，期间不接受校验 */
  static readonly PIN_LOCKOUT_MS: number = 30000;

  /** 默认货币符号 */
  static readonly DEFAULT_CURRENCY: string = '¥';
  /** 默认货币代码 */
  static readonly DEFAULT_CURRENCY_CODE: string = 'CNY';
  /** 外币默认汇率（1 单位外币 = 多少元 ¥），用户可在设置中修改 */
  static readonly DEFAULT_RATE_USD: number = 7.2;
  static readonly DEFAULT_RATE_EUR: number = 7.8;
  /** 首页最近流水条数 */
  static readonly RECENT_COUNT: number = 5;
  /** 趋势图月数（齐活林拍板：折线图进 v1.0） */
  static readonly TREND_MONTHS: number = 6;
  /** 环形图尾部合并阈值：占比低于该值合并为「其他」 */
  static readonly SLICE_MERGE_RATIO: number = 0.02;
  /** 键盘表达式最大长度 */
  static readonly MAX_EXPRESSION_LENGTH: number = 20;
  /** 金额字段的统一上限（分）：防止超大数字在换算或累计时失去整数精度。 */
  static readonly MAX_MONEY_FEN: number = 9000000000;
  /** 手工外币汇率的合理边界，避免异常偏好值影响全部金额展示。 */
  static readonly MIN_CURRENCY_RATE: number = 0.0001;
  static readonly MAX_CURRENCY_RATE: number = 1000000;

  /** 预置分类数量（支出 11 + 收入 6） */
  static readonly PRESET_CATEGORY_COUNT: number = 17;
  /** 预置账户数量（1 条「现金」，is_system=0，用户可删除修改） */
  static readonly PRESET_ACCOUNT_COUNT: number = 1;

  // ---------- v1.1 多账本 / 备份 / 提醒（架构 R3 / R5 / R10） ----------

  /** 账本名称长度上限（去空格后 1~20 字符，F-10.3 规则 2） */
  static readonly LEDGER_NAME_MAX_LENGTH: number = 20;
  /** 备份文件名前缀（完整名：前缀 + yyyyMMdd_HHmmss + .json，架构 R5） */
  static readonly BACKUP_FILE_PREFIX: string = '轻账本_备份_';
  /** 备份 JSON meta.app 标识（校验备份归属，架构 1.2） */
  static readonly BACKUP_APP_NAME: string = 'lightledger';
  /** 备份文件格式版本：当前支持恢复的 schema 上限（架构 R9：≤ CURRENT_SCHEMA_VERSION=1） */
  static readonly BACKUP_SUPPORTED_SCHEMA_VERSION: number = 1;
}

/** 统一结果对象（架构 9.5）：Service 只 throw，ViewModel 返回该结构，Page 据此 Toast 或渲染异常态 */
export interface Result<T> {
  ok: boolean;
  data?: T;
  message?: string;
  /** 失败详情（BusinessError.code + message），供页面精确展示诊断信息 */
  detail?: string;
}
