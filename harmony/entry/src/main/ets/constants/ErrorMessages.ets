/**
 * 模块职责：业务异常与校验文案单一真相源（架构 2.5 错误处理分层的落地件）。
 * - Service 层 throw 的业务异常、ViewModel 校验提示，一律引用本文件常量，
 *   禁止在各文件内散落字符串字面量（改名/纠错只改这一处）
 * - ⚠️ 合规：本文件所有文案已过禁用词扫描（不得出现金融敏感词/绝对化用语）
 * - i18n 说明：v1.0 错误 Toast 仅中文（文案在此集中，T05 如需多语言
 *   可按 code→Resource 映射替换，页面层无需改动）
 */
export class ErrorMessages {
  // ── 通用 ──
  /** 未知错误兜底（catch 分支） */
  static readonly UNKNOWN: string = '操作失败，请重试';
  static readonly SAVE_FAILED: string = '保存失败，请重试';
  static readonly EXPORT_FAILED: string = '导出失败，请重试';
  static readonly CLEAR_FAILED: string = '清空数据失败，请重试';

  // ── 数据库 ──
  static readonly DB_INIT_FAILED: string = '数据库初始化失败：';
  static readonly DB_NOT_INITIALIZED: string = '数据库尚未初始化，请先调用 DatabaseManager.init(context)';
  static readonly DB_READ_ONLY: string = '数据库处于只读模式，无法写入';
  static readonly DB_CLEAR_FAILED: string = '清空数据失败：';

  // ── 设置 ──
  static readonly SETTINGS_NOT_INITIALIZED: string = 'SettingsService 未初始化，请先调用 init(context)';

  // ── 账户 ──
  static readonly ACCOUNT_NAME_EMPTY: string = '账户名称不能为空';
  static readonly ACCOUNT_NOT_FOUND: string = '账户不存在';
  static readonly ACCOUNT_HAS_TX: string = '该账户已有流水记录，请先归档而不是删除';

  // ── 分类 ──
  static readonly CATEGORY_NAME_EMPTY: string = '分类名称不能为空';
  static readonly CATEGORY_NOT_FOUND: string = '分类不存在';

  // ── 预算 ──
  static readonly BUDGET_NEGATIVE: string = '预算金额不能为负数';
  static readonly AMOUNT_INVALID: string = '请输入正确的金额';
  static readonly CURRENCY_RATE_INVALID: string = '请输入正确的汇率';

  // ── 账本 ──
  static readonly LEDGER_NAME_EMPTY: string = '账本名称不能为空';
  static readonly LEDGER_NOT_FOUND: string = '账本不存在';
  static readonly LEDGER_DEFAULT_DELETE_BLOCKED: string = '默认账本不能删除';
  static readonly LEDGER_LAST_DELETE_BLOCKED: string = '至少保留一个账本';
  static readonly LEDGER_HAS_TX: string = '该账本已有流水记录，不能删除';
  static readonly LEDGER_NAME_TOO_LONG: string = '账本名称不能超过 20 个字符';
  static readonly LEDGER_NAME_DUPLICATED: string = '已存在同名账本，请换一个名称';

  // ── 备份与恢复（v1.1 F-10.5 / F-10.6） ──
  static readonly BACKUP_INVALID: string = '备份文件已损坏或格式不正确';
  static readonly BACKUP_VERSION_INCOMPATIBLE: string = '备份文件版本过高，请先升级应用后再恢复';
  static readonly RESTORE_FAILED: string = '恢复失败，原数据未受影响，请重试';

  // ── 流水 ──
  static readonly AMOUNT_POSITIVE: string = '金额必须大于零';
  static readonly TX_ACCOUNT_REQUIRED: string = '请选择账户';
  static readonly TX_CATEGORY_REQUIRED: string = '请选择分类';
  static readonly TX_USE_ADD_TRANSFER: string = '请使用 addTransfer 记录转账';
  static readonly TX_TRANSFER_ACCOUNTS_REQUIRED: string = '请选择转出与转入账户';
  static readonly TX_TRANSFER_SAME_ACCOUNT: string = '转出与转入账户不能相同';
  static readonly TX_NOT_FOUND: string = '流水不存在';
  static readonly TX_TRANSFER_EDIT_BLOCKED: string = '转账记录请在删除后重新记录';
  static readonly TX_NOT_FOUND_OR_DELETED: string = '流水不存在或已被删除';
  static readonly TX_FUTURE_DATE: string = '记账日期不能晚于今天';
  static readonly TX_NO_ACCOUNT: string = '请先在 我的 → 账户管理 中添加账户';
  static readonly TX_AMOUNT_INVALID: string = '请输入正确的金额';
  static readonly TX_DATE_INVALID: string = '记账日期不正确';
  static readonly TX_NOTE_TOO_LONG: string = '备注不能超过 100 个字符';
  static readonly TX_INVALID_TYPE: string = '流水类型不正确';

  // ── 应用锁 ──
  static readonly PIN_FORMAT_INVALID: string = '密码格式不正确';

  // ── 功能占位 ──
  static readonly IMAGE_NOT_ENABLED: string = '图片凭证功能尚未启用，计划随 v1.1 提供';
}
