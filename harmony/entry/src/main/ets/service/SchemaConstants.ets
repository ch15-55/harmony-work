/**
 * 模块职责：数据库 DDL、索引与 schema 版本常量（架构 4.2 / T02）。
 * - 金额字段全部 INTEGER（单位：分）；时间字段全部 INTEGER（UTC 毫秒）
 * - 索引共 7 个（流水表 4 个），克制设计，不加更多（架构 4.2 索引说明）
 * - DDL 只在本文件维护，由 DatabaseManager 按序执行
 */

/** 当前 schema 版本。任何表结构变更必须 +1，并在 MIGRATIONS 追加一级迁移。 */
export const CURRENT_SCHEMA_VERSION: number = 1;

/** ll_meta 键：schema 版本（不用 PRAGMA user_version，理由见架构 4.5） */
export const META_KEY_SCHEMA_VERSION: string = 'schema_version';
/** ll_meta 键：最近一次迁移时间（UTC 毫秒） */
export const META_KEY_LAST_MIGRATE_AT: string = 'last_migrate_at';

/** 表名常量 */
export class Tables {
  static readonly META: string = 'll_meta';
  static readonly LEDGER: string = 'll_ledger';
  static readonly ACCOUNT: string = 'll_account';
  static readonly CATEGORY: string = 'll_category';
  static readonly TRANSACTION: string = 'll_transaction';
  static readonly BUDGET: string = 'll_budget';
  static readonly BUDGET_ITEM: string = 'll_budget_item';
}

/** 全部业务表名（clearAllData 按序清空，不 DROP，保留 schema） */
export const BUSINESS_TABLES: string[] = [
  Tables.TRANSACTION,
  Tables.BUDGET_ITEM,
  Tables.BUDGET,
  Tables.CATEGORY,
  Tables.ACCOUNT,
  Tables.LEDGER
];

/** 元数据表（必须最先创建，否则无法读取 schema 版本） */
export const CREATE_META_TABLE: string = `CREATE TABLE IF NOT EXISTS ll_meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
)`;

/** 6 张业务表 DDL（首次安装全量执行） */
export const CREATE_TABLES: string[] = [
  // 1. 账本
  `CREATE TABLE IF NOT EXISTS ll_ledger (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL,
    icon        TEXT    NOT NULL DEFAULT 'book',
    color       TEXT    NOT NULL DEFAULT '#5B67F5',
    currency    TEXT    NOT NULL DEFAULT 'CNY',
    is_default  INTEGER NOT NULL DEFAULT 0,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
  )`,
  // 2. 账户（余额实时计算，不冗余存储）
  `CREATE TABLE IF NOT EXISTS ll_account (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    ledger_id        INTEGER NOT NULL DEFAULT 1,
    name             TEXT    NOT NULL,
    type             INTEGER NOT NULL DEFAULT 0,
    icon             TEXT    NOT NULL DEFAULT 'wallet',
    color            TEXT    NOT NULL DEFAULT '#5B67F5',
    initial_balance  INTEGER NOT NULL DEFAULT 0,
    credit_limit     INTEGER NOT NULL DEFAULT 0,
    is_archived      INTEGER NOT NULL DEFAULT 0,
    sort_order       INTEGER NOT NULL DEFAULT 0,
    created_at       INTEGER NOT NULL,
    updated_at       INTEGER NOT NULL
  )`,
  // 3. 分类（parent_id 预留二级分类，v1.0 恒为 0）
  `CREATE TABLE IF NOT EXISTS ll_category (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    ledger_id   INTEGER NOT NULL DEFAULT 1,
    name        TEXT    NOT NULL,
    type        INTEGER NOT NULL,
    parent_id   INTEGER NOT NULL DEFAULT 0,
    icon        TEXT    NOT NULL DEFAULT 'more',
    color       TEXT    NOT NULL DEFAULT '#F5544B',
    sort_order  INTEGER NOT NULL DEFAULT 0,
    is_system   INTEGER NOT NULL DEFAULT 0,
    is_hidden   INTEGER NOT NULL DEFAULT 0,
    use_count   INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
  )`,
  // 4. 流水（核心表；转账用 related_tx_id 同表互指，不建独立表）
  `CREATE TABLE IF NOT EXISTS ll_transaction (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    ledger_id      INTEGER NOT NULL DEFAULT 1,
    type           INTEGER NOT NULL,
    amount         INTEGER NOT NULL,
    account_id     INTEGER NOT NULL,
    to_account_id  INTEGER NOT NULL DEFAULT 0,
    category_id    INTEGER NOT NULL DEFAULT 0,
    related_tx_id  INTEGER NOT NULL DEFAULT 0,
    note           TEXT    NOT NULL DEFAULT '',
    image_paths    TEXT    NOT NULL DEFAULT '',
    tx_date        INTEGER NOT NULL,
    created_at     INTEGER NOT NULL,
    updated_at     INTEGER NOT NULL
  )`,
  // 5. 预算
  `CREATE TABLE IF NOT EXISTS ll_budget (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    ledger_id     INTEGER NOT NULL DEFAULT 1,
    month         TEXT    NOT NULL,
    total_amount  INTEGER NOT NULL DEFAULT 0,
    carry_over    INTEGER NOT NULL DEFAULT 0,
    created_at    INTEGER NOT NULL,
    updated_at    INTEGER NOT NULL
  )`,
  // 6. 分类预算项（v1.0 建表预留，v1.1 启用）
  `CREATE TABLE IF NOT EXISTS ll_budget_item (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    budget_id    INTEGER NOT NULL,
    category_id  INTEGER NOT NULL,
    amount       INTEGER NOT NULL DEFAULT 0
  )`
];

/** 7 个索引（流水表 4 个；克制设计，勿增删） */
export const CREATE_INDEXES: string[] = [
  // ★ 月度收支/分类聚合主力索引：WHERE ledger_id=? AND type=? AND tx_date BETWEEN ?
  `CREATE INDEX IF NOT EXISTS idx_tx_ledger_type_date ON ll_transaction(ledger_id, type, tx_date)`,
  // ★ 月度全量列表 / 趋势 / CSV 导出（不指定 type 的区间查询）
  `CREATE INDEX IF NOT EXISTS idx_tx_ledger_date ON ll_transaction(ledger_id, tx_date)`,
  // ★ 账户余额计算 / 账户流水
  `CREATE INDEX IF NOT EXISTS idx_tx_account ON ll_transaction(account_id)`,
  // ★ 转账配对删除：WHERE id=? OR related_tx_id=?
  `CREATE INDEX IF NOT EXISTS idx_tx_related ON ll_transaction(related_tx_id)`,
  // 账户列表排序
  `CREATE INDEX IF NOT EXISTS idx_account_ledger ON ll_account(ledger_id, is_archived, sort_order)`,
  // 分类列表排序
  `CREATE INDEX IF NOT EXISTS idx_category_ledger_type ON ll_category(ledger_id, type, is_hidden, sort_order)`,
  // 预算按月唯一（UPSERT 语义支撑）
  `CREATE UNIQUE INDEX IF NOT EXISTS uk_budget_ledger_month ON ll_budget(ledger_id, month)`
];
