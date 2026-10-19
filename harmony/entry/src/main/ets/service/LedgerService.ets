/**
 * 模块职责：账本领域服务（架构 4.2 ll_ledger / PRD F-10.2 ~ F-10.4，v1.1 开放）。
 * - list / create / rename / delete / switchTo / 当前账本解析
 * - 新建账本：同事务内仅播种 17 条系统分类（SeedDataManager.seedForLedger，架构 R3），
 *   保证新账本建完即可记账；账户不预置（PRD 5.2 裁决）
 * - 名称校验（F-10.3 规则 2）：去空格非空、长度 1~20、与现有账本重名拒绝（忽略首尾空格）
 * - 删除拦截：默认账本不可删、至少保留一本、有流水的账本不可删（与账户删除口径一致）；
 *   无流水时事务内级联清理该账本的账户/分类/预算
 * - 当前账本 id 存 Preferences（SettingsService），switchTo 后 DataBus.bump() 驱动全站刷新
 * - 只允许 throw 业务异常，禁止在 Service 内弹 Toast（架构 9.5）
 */
import { relationalStore } from '@kit.ArkData';
import { DatabaseManager } from './DatabaseManager';
import { DataBus } from './DataBus';
import { Tables } from './SchemaConstants';
import { Ledger } from '../model/Ledger';
import { AppConstants } from '../constants/AppConstants';
import { SettingsService } from './SettingsService';
import { SeedDataManager } from './SeedDataManager';
import { IconConstants } from '../constants/IconConstants';
import { DateUtil } from '../utils/DateUtil';
import { LogUtil } from '../utils/LogUtil';
import { ErrorMessages } from '../constants/ErrorMessages';

/** 新建账本取色盘（默认色循环；导出供账本管理页色点选择复用，单一真相源） */
export const LEDGER_COLOR_CHOICES: string[] = [
  '#5B67F5', '#12B76A', '#F59E0B', '#0EA5E9', '#8B5CF6', '#F5544B'
];

/** 合法颜色格式：#RRGGBB */
const HEX_COLOR_PATTERN: RegExp = /^#[0-9A-Fa-f]{6}$/;

export class LedgerService {
  private static readonly TAG: string = 'LedgerService';

  /** 全部账本（按 sort_order、id 升序） */
  public static async list(): Promise<Ledger[]> {
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(Tables.LEDGER);
    predicates.orderByAsc('sort_order');
    predicates.orderByAsc('id');
    const resultSet: relationalStore.ResultSet = await store.query(predicates);
    const list: Ledger[] = [];
    try {
      while (resultSet.goToNextRow()) {
        list.push(Ledger.fromRow(resultSet));
      }
    } finally {
      resultSet.close();
    }
    return list;
  }

  /** 按 id 查单条；不存在返回 null */
  public static async getById(id: number): Promise<Ledger | null> {
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    const resultSet: relationalStore.ResultSet =
      await store.querySql('SELECT * FROM ' + Tables.LEDGER + ' WHERE id = ?', [id]);
    let ledger: Ledger | null = null;
    try {
      if (resultSet.goToFirstRow()) {
        ledger = Ledger.fromRow(resultSet);
      }
    } finally {
      resultSet.close();
    }
    return ledger;
  }

  /** 账本总数（删除拦截与我的页汇总用） */
  public static async countAll(): Promise<number> {
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    const resultSet: relationalStore.ResultSet = await store.querySql(
      'SELECT COUNT(*) AS cnt FROM ' + Tables.LEDGER);
    let count: number = 0;
    try {
      if (resultSet.goToFirstRow()) {
        count = resultSet.getLong(resultSet.getColumnIndex('cnt'));
      }
    } finally {
      resultSet.close();
    }
    return count;
  }

  /**
   * 解析当前账本（HomeViewModel.load 等入口调用一次，其余 service 同步读 SettingsService）。
   * 持久化的 id 已不存在（如清库后残留）时回退默认账本并修正持久化值。
   */
  public static async resolveCurrent(): Promise<Ledger> {
    const savedId: number = SettingsService.getCurrentLedgerId();
    const ledger: Ledger | null = await LedgerService.getById(savedId);
    if (ledger !== null) {
      return ledger;
    }
    const fallback: Ledger | null = await LedgerService.getById(AppConstants.DEFAULT_LEDGER_ID);
    SettingsService.setCurrentLedgerId(AppConstants.DEFAULT_LEDGER_ID);
    if (fallback !== null) {
      return fallback;
    }
    // 极端兜底（库被手工清空且未跑 seed）：抛业务异常交页面 ErrorState
    throw new Error(ErrorMessages.LEDGER_NOT_FOUND);
  }

  /**
   * 切换当前账本（F-10.4 规则 1，架构 4.1 时序）：
   * 校验存在 → 持久化当前 id → DataBus.bump() 驱动全站按新账本重载。
   */
  public static async switchTo(id: number): Promise<void> {
    const ledger: Ledger | null = await LedgerService.getById(id);
    if (ledger === null) {
      throw new Error(ErrorMessages.LEDGER_NOT_FOUND);
    }
    SettingsService.setCurrentLedgerId(id);
    DataBus.bump();
    LogUtil.d(LedgerService.TAG, 'switched to ledger, id=' + id.toString());
  }

  /**
   * 新建账本：账本行 + 播种（仅 17 条系统分类）同一事务（架构 R3）。
   * 名称校验：去空格非空 + 长度 1~20 + 与现有账本重名拒绝（忽略首尾空格）。
   * 图标不在 LEDGER_ICON_KEYS 内回退默认图标；颜色非合法 #RRGGBB 回退色盘循环。
   * 排序取现有最大值 +1；事务内重名校验保证并发下不产生重名。
   */
  public static async create(name: string, icon: string, color: string): Promise<number> {
    const trimmed: string = name.trim();
    if (trimmed.length === 0) {
      throw new Error(ErrorMessages.LEDGER_NAME_EMPTY);
    }
    if (trimmed.length > AppConstants.LEDGER_NAME_MAX_LENGTH) {
      throw new Error(ErrorMessages.LEDGER_NAME_TOO_LONG);
    }
    const safeIcon: string = LedgerService.normalizeIcon(icon);
    const db: DatabaseManager = DatabaseManager.getInstance();
    const now: number = DateUtil.now();
    const newId: number = await db.runInTransaction<number>(async (store: relationalStore.RdbStore) => {
      if (await LedgerService.nameExistsIn(store, trimmed, 0)) {
        throw new Error(ErrorMessages.LEDGER_NAME_DUPLICATED);
      }
      const count: number = await LedgerService.countAllIn(store);
      const maxSort: number = await LedgerService.maxSortOrder(store);
      const ledger: Ledger = new Ledger();
      ledger.name = trimmed;
      ledger.icon = safeIcon;
      ledger.color = LedgerService.normalizeColor(color, count);
      ledger.currency = AppConstants.DEFAULT_CURRENCY_CODE;
      ledger.isDefault = false;
      ledger.sortOrder = maxSort + 1;
      ledger.createdAt = now;
      ledger.updatedAt = now;
      const rowId: number = await store.insert(Tables.LEDGER, ledger.toValuesBucket());
      await SeedDataManager.seedForLedger(store, rowId, now);
      return rowId;
    });
    DataBus.bump();
    LogUtil.d(LedgerService.TAG, 'ledger created, id=' + newId.toString());
    return newId;
  }

  /**
   * 重命名 + 改图标/颜色（QA M2：重命名模式下图标/颜色选择一并落库，不再静默丢弃）。
   * 名称校验口径与 create 一致：非空 + 长度 + 重名（排除自身）；
   * 图标/颜色复用 normalizeIcon/normalizeColor 校验回退逻辑。
   */
  public static async rename(id: number, name: string, icon: string, color: string): Promise<void> {
    const trimmed: string = name.trim();
    if (trimmed.length === 0) {
      throw new Error(ErrorMessages.LEDGER_NAME_EMPTY);
    }
    if (trimmed.length > AppConstants.LEDGER_NAME_MAX_LENGTH) {
      throw new Error(ErrorMessages.LEDGER_NAME_TOO_LONG);
    }
    const ledger: Ledger | null = await LedgerService.getById(id);
    if (ledger === null) {
      throw new Error(ErrorMessages.LEDGER_NOT_FOUND);
    }
    const safeIcon: string = LedgerService.normalizeIcon(icon);
    const safeColor: string = LedgerService.normalizeColor(color, 0);
    const db: DatabaseManager = DatabaseManager.getInstance();
    await db.runInTransaction<void>(async (store: relationalStore.RdbStore) => {
      if (await LedgerService.nameExistsIn(store, trimmed, id)) {
        throw new Error(ErrorMessages.LEDGER_NAME_DUPLICATED);
      }
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(Tables.LEDGER);
      predicates.equalTo('id', id);
      const patch: relationalStore.ValuesBucket = {
        'name': trimmed,
        'icon': safeIcon,
        'color': safeColor,
        'updated_at': DateUtil.now()
      };
      await store.update(patch, predicates);
    });
    DataBus.bump();
  }

  /**
   * 删除账本（拦截口径见文件头注释）：
   * 默认账本不可删；至少保留一本；有流水不可删（提示口径与账户一致，不静默级联删流水）。
   * 通过后事务内级联清理该账本的预算项/预算/分类/账户，最后删账本行。
   * 若删的是当前账本，回切默认账本。
   */
  public static async delete(id: number): Promise<void> {
    const ledger: Ledger | null = await LedgerService.getById(id);
    if (ledger === null) {
      throw new Error(ErrorMessages.LEDGER_NOT_FOUND);
    }
    if (ledger.isDefault) {
      throw new Error(ErrorMessages.LEDGER_DEFAULT_DELETE_BLOCKED);
    }
    if (await LedgerService.countAll() <= 1) {
      throw new Error(ErrorMessages.LEDGER_LAST_DELETE_BLOCKED);
    }
    if (await LedgerService.hasTransactions(id)) {
      throw new Error(ErrorMessages.LEDGER_HAS_TX);
    }
    const db: DatabaseManager = DatabaseManager.getInstance();
    await db.runInTransaction<void>(async (store: relationalStore.RdbStore) => {
      await store.executeSql('DELETE FROM ' + Tables.BUDGET_ITEM +
        ' WHERE budget_id IN (SELECT id FROM ' + Tables.BUDGET + ' WHERE ledger_id = ?)', [id]);
      await store.executeSql('DELETE FROM ' + Tables.BUDGET + ' WHERE ledger_id = ?', [id]);
      await store.executeSql('DELETE FROM ' + Tables.CATEGORY + ' WHERE ledger_id = ?', [id]);
      await store.executeSql('DELETE FROM ' + Tables.ACCOUNT + ' WHERE ledger_id = ?', [id]);
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(Tables.LEDGER);
      predicates.equalTo('id', id);
      await store.delete(predicates);
    });
    if (SettingsService.getCurrentLedgerId() === id) {
      SettingsService.setCurrentLedgerId(AppConstants.DEFAULT_LEDGER_ID);
    }
    DataBus.bump();
    LogUtil.d(LedgerService.TAG, 'ledger deleted, id=' + id.toString());
  }

  /** 该账本名下是否有流水（删除拦截依据） */
  public static async hasTransactions(id: number): Promise<boolean> {
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    const resultSet: relationalStore.ResultSet = await store.querySql(
      'SELECT COUNT(*) AS cnt FROM ' + Tables.TRANSACTION + ' WHERE ledger_id = ?', [id]);
    let count: number = 0;
    try {
      if (resultSet.goToFirstRow()) {
        count = resultSet.getLong(resultSet.getColumnIndex('cnt'));
      }
    } finally {
      resultSet.close();
    }
    return count > 0;
  }

  /** 图标键归一化：不在账本可选集合内时回退默认图标 */
  public static normalizeIcon(icon: string): string {
    if (IconConstants.LEDGER_ICON_KEYS.indexOf(icon) >= 0) {
      return icon;
    }
    return IconConstants.DEFAULT_LEDGER_ICON_KEY;
  }

  /** 颜色归一化：非法格式回退色盘循环取色 */
  public static normalizeColor(color: string, existingCount: number): string {
    if (HEX_COLOR_PATTERN.test(color)) {
      return color;
    }
    return LEDGER_COLOR_CHOICES[existingCount % LEDGER_COLOR_CHOICES.length];
  }

  /** 事务内重名校验（忽略首尾空格；excludeId > 0 时排除自身，重命名用） */
  private static async nameExistsIn(store: relationalStore.RdbStore,
    name: string, excludeId: number): Promise<boolean> {
    let sql: string = 'SELECT COUNT(*) AS cnt FROM ' + Tables.LEDGER + ' WHERE name = ?';
    const params: Array<number | string> = [name];
    if (excludeId > 0) {
      sql += ' AND id <> ?';
      params.push(excludeId);
    }
    const resultSet: relationalStore.ResultSet = await store.querySql(sql, params);
    let count: number = 0;
    try {
      if (resultSet.goToFirstRow()) {
        count = resultSet.getLong(resultSet.getColumnIndex('cnt'));
      }
    } finally {
      resultSet.close();
    }
    return count > 0;
  }

  /** 事务内计数（create 用，避免重复开查询连接语义歧义） */
  private static async countAllIn(store: relationalStore.RdbStore): Promise<number> {
    const resultSet: relationalStore.ResultSet = await store.querySql(
      'SELECT COUNT(*) AS cnt FROM ' + Tables.LEDGER);
    let count: number = 0;
    try {
      if (resultSet.goToFirstRow()) {
        count = resultSet.getLong(resultSet.getColumnIndex('cnt'));
      }
    } finally {
      resultSet.close();
    }
    return count;
  }

  /** 事务内取最大 sort_order */
  private static async maxSortOrder(store: relationalStore.RdbStore): Promise<number> {
    const resultSet: relationalStore.ResultSet = await store.querySql(
      'SELECT COALESCE(MAX(sort_order), 0) AS max_sort FROM ' + Tables.LEDGER);
    let maxSort: number = 0;
    try {
      if (resultSet.goToFirstRow()) {
        maxSort = resultSet.getLong(resultSet.getColumnIndex('max_sort'));
      }
    } finally {
      resultSet.close();
    }
    return maxSort;
  }
}
