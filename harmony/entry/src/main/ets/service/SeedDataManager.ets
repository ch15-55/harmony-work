/**
 * 模块职责：预置数据初始化（架构 4.5 / T02 / 齐活林裁决 4）。
 * 预置内容（全部幂等，重复调用不会产生重复数据）：
 * - 1 条默认账本：id=1「个人账本」（INSERT OR IGNORE，固定主键）
 * - 17 条预置分类：支出 11 + 收入 6，is_system=1（内置不可删，但可隐藏）
 * - 1 条预置账户：「现金」，期初 0 分，is_system 语义不适用于账户表——
 *   该账户为普通数据（可删除、可修改），仅通过「无任何账户时才插入」保证幂等
 * - v1.1 多账本（F-2.5 / 架构 R3）：新建账本复用 seedForLedger，仅播种 17 条系统分类，
 *   不预置账户（PRD 5.2 裁决：账户属用户数据，全局唯一，不随账本重复预置）
 */
import { relationalStore } from '@kit.ArkData';
import { Tables } from './SchemaConstants';
import {
  CategoryPreset,
  EXPENSE_CATEGORY_PRESETS,
  INCOME_CATEGORY_PRESETS
} from '../constants/CategoryPresets';
import { ACCOUNT_PRESETS, AccountPreset } from '../constants/AccountPresets';
import { AppConstants, AccountType, CategoryType } from '../constants/AppConstants';
import { LogUtil } from '../utils/LogUtil';
import { DateUtil } from '../utils/DateUtil';

export class SeedDataManager {
  private static readonly TAG: string = 'SeedDataManager';

  /** 默认账本 id（架构 D5：数据模型 v1.0 即带 ledger_id 并写入默认账本） */
  static readonly DEFAULT_LEDGER_ID: number = AppConstants.DEFAULT_LEDGER_ID;
  /**
   * 默认账本名。
   * ⚠️ 文案位置说明（架构 2.6.1 的已知例外）：账本名属数据库种子数据，
   * 与分类名同类（分类名按架构同样定义在 constants/CategoryPresets 而非
   * string.json）；SeedDataManager 无 Context 无法读资源，故保留字面量。
   * 该词已通过 A/B/C 三级禁用词表核验。
   */
  static readonly DEFAULT_LEDGER_NAME: string = '个人账本';

  /**
   * 执行预置（须在事务内，由 MigrationManager.freshInstall / DatabaseManager.clearAllData 调用）。
   */
  public static async seed(store: relationalStore.RdbStore): Promise<void> {
    const now: number = DateUtil.now();
    await SeedDataManager.seedLedger(store, now);
    await SeedDataManager.seedCategories(store, SeedDataManager.DEFAULT_LEDGER_ID, now);
    await SeedDataManager.seedCashAccount(store, now);
    LogUtil.i(SeedDataManager.TAG, 'seed done');
  }

  /**
   * 为新建账本预置数据（LedgerService.createLedger 事务内调用）。
   * 仅补该账本的系统分类；现金账户全局唯一，不随账本重复预置。
   */
  public static async seedForLedger(store: relationalStore.RdbStore,
    ledgerId: number, now: number): Promise<void> {
    await SeedDataManager.seedCategories(store, ledgerId, now);
    LogUtil.i(SeedDataManager.TAG, 'seedForLedger done, ledgerId=' + ledgerId.toString());
  }

  /** 预置默认账本 id=1（主键固定，重复执行被 OR IGNORE 吞掉） */
  private static async seedLedger(store: relationalStore.RdbStore, now: number): Promise<void> {
    const sql: string = 'INSERT OR IGNORE INTO ll_ledger ' +
      '(id, name, icon, color, currency, is_default, sort_order, created_at, updated_at) ' +
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)';
    await store.executeSql(sql, [
      SeedDataManager.DEFAULT_LEDGER_ID,
      SeedDataManager.DEFAULT_LEDGER_NAME,
      'ic_common_book',
      '#5B67F5',
      AppConstants.DEFAULT_CURRENCY_CODE,
      1,
      0,
      now,
      now
    ]);
  }

  /** 预置 17 条分类（is_system=1）；该账本已有任一系统分类时跳过 */
  private static async seedCategories(store: relationalStore.RdbStore,
    ledgerId: number, now: number): Promise<void> {
    const count: number = await SeedDataManager.countRows(store, Tables.CATEGORY,
      'ledger_id = ' + ledgerId.toString() + ' AND is_system = 1');
    if (count > 0) {
      return;
    }
    await SeedDataManager.insertPresets(store, ledgerId, EXPENSE_CATEGORY_PRESETS, CategoryType.EXPENSE, now);
    await SeedDataManager.insertPresets(store, ledgerId, INCOME_CATEGORY_PRESETS, CategoryType.INCOME, now);
  }

  /**
   * 预置 1 条「现金」账户（期初 0）。
   * 裁决 4 / D9：该账户是普通数据，用户可删除、可修改——账户表 DDL（架构 4.2）
   * 本身无 is_system 列，任何账户均可删除，天然满足 is_system=0 语义；
   * 幂等性通过「账户表为空才插入」保证，用户删除后不会被重新插入。
   * 账户名引用 AccountPresets（文案单一真相源，架构 2.6.1）。
   */
  private static async seedCashAccount(store: relationalStore.RdbStore, now: number): Promise<void> {
    const count: number = await SeedDataManager.countRows(store, Tables.ACCOUNT, '1 = 1');
    if (count > 0) {
      return;
    }
    const cashPreset: AccountPreset = ACCOUNT_PRESETS[0];
    const sql: string = 'INSERT INTO ll_account ' +
      '(ledger_id, name, type, icon, color, initial_balance, credit_limit, is_archived, sort_order, created_at, updated_at) ' +
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
    await store.executeSql(sql, [
      SeedDataManager.DEFAULT_LEDGER_ID,
      cashPreset.name,
      AccountType.CASH,
      cashPreset.icon,
      cashPreset.color,
      0,
      0,
      0,
      0,
      now,
      now
    ]);
  }

  /** 按类型批量插入预置分类 */
  private static async insertPresets(store: relationalStore.RdbStore, ledgerId: number,
    presets: CategoryPreset[], categoryType: number, now: number): Promise<void> {
    const sql: string = 'INSERT INTO ll_category ' +
      '(ledger_id, name, type, parent_id, icon, color, sort_order, is_system, is_hidden, use_count, created_at, updated_at) ' +
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
    for (let i = 0; i < presets.length; i++) {
      const preset: CategoryPreset = presets[i];
      await store.executeSql(sql, [
        ledgerId,
        preset.name,
        categoryType,
        0,
        preset.icon,
        preset.color,
        preset.sortOrder,
        1,
        0,
        0,
        now,
        now
      ]);
    }
  }

  /** 条件计数 */
  private static async countRows(store: relationalStore.RdbStore, table: string, where: string): Promise<number> {
    const resultSet: relationalStore.ResultSet =
      await store.querySql('SELECT COUNT(*) AS cnt FROM ' + table + ' WHERE ' + where);
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
}
