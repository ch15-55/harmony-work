/**
 * 模块职责：本地备份与恢复服务（架构 T03 / 1.1 R5~R7 / 1.2 备份 JSON 结构）。
 * - buildBackupJson：全量读 6 张业务表 → meta + data → 明文 JSON（UTF-8，原样序列化，
 *   金额恒整数分、时间 UTC 毫秒，不引入任何换算，架构 6 铁律 6）
 * - exportViaPicker：沙箱临时文件 → DocumentViewPicker.save(['.json']) → 拷贝 → 清理，
 *   复用 ExportOutcome 三态（saved/cancelled/failed + failurePoint）
 * - restoreFromJson：readTextFromUri → validateBackupJson（沙箱内校验，不碰库）
 *   → runInTransaction 内清 6 表 → 显式主键按序插入（ledger→account→category→
 *   budget→budget_item→transaction）→ 重置当前账本指针（备份 is_default 账本）
 *   → 清空 last_account_id / last_category_id（架构 R7）→ DataBus.bump()
 * - 校验项（架构 1.2）：JSON 可解析且含 meta/data；data 恰含 6 表键且均为数组；
 *   schema_version ≤ 1；row_counts 逐表核对；逐行必填字段存在且类型合法
 * - 只允许 throw 业务异常，禁止在 Service 内弹 Toast（架构 9.5）
 */
import { picker } from '@kit.CoreFileKit';
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { bundleManager } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { DatabaseManager } from './DatabaseManager';
import { Tables, BUSINESS_TABLES, CURRENT_SCHEMA_VERSION } from './SchemaConstants';
import { SettingsService } from './SettingsService';
import { DataBus } from './DataBus';
import { AppConstants } from '../constants/AppConstants';
import { ErrorMessages } from '../constants/ErrorMessages';
import { ExportOutcome, ExportStatus } from './ExportService';
import { FileUtil } from '../utils/FileUtil';
import { LogUtil } from '../utils/LogUtil';
import { DateUtil } from '../utils/DateUtil';

/** 备份文件 meta 段（架构 1.2；row_counts 键为表名） */
interface BackupMetaJson {
  app: string;
  app_version: string;
  schema_version: number;
  exported_at: number;
  row_counts: Record<string, number>;
  rows_total: number;
}

/** 备份文件 data 段：6 张表的行数组（行为列名 → 值键值对，原样序列化） */
interface BackupDataJson {
  'll_ledger': Record<string, Object>[];
  'll_account': Record<string, Object>[];
  'll_category': Record<string, Object>[];
  'll_budget': Record<string, Object>[];
  'll_budget_item': Record<string, Object>[];
  'll_transaction': Record<string, Object>[];
}

/** 备份文件顶层结构 */
interface BackupFileJson {
  meta: BackupMetaJson;
  data: BackupDataJson;
}

/** 备份与恢复的表清单及列序（恢复插入顺序 = 架构 1.2：ledger → … → transaction） */
const BACKUP_TABLES: string[] = [
  Tables.LEDGER,
  Tables.ACCOUNT,
  Tables.CATEGORY,
  Tables.BUDGET,
  Tables.BUDGET_ITEM,
  Tables.TRANSACTION
];

/** 逐表列定义（'列名:t' 表示 TEXT，其余按 INTEGER 读） */
const TABLE_COLUMNS: Map<string, string[]> = new Map([
  [Tables.LEDGER, ['id:n', 'name:t', 'icon:t', 'color:t', 'currency:t', 'is_default:n',
    'sort_order:n', 'created_at:n', 'updated_at:n']],
  [Tables.ACCOUNT, ['id:n', 'ledger_id:n', 'name:t', 'type:n', 'icon:t', 'color:t',
    'initial_balance:n', 'credit_limit:n', 'is_archived:n', 'sort_order:n',
    'created_at:n', 'updated_at:n']],
  [Tables.CATEGORY, ['id:n', 'ledger_id:n', 'name:t', 'type:n', 'parent_id:n', 'icon:t',
    'color:t', 'sort_order:n', 'is_system:n', 'is_hidden:n', 'use_count:n',
    'created_at:n', 'updated_at:n']],
  [Tables.BUDGET, ['id:n', 'ledger_id:n', 'month:t', 'total_amount:n', 'carry_over:n',
    'created_at:n', 'updated_at:n']],
  [Tables.BUDGET_ITEM, ['id:n', 'budget_id:n', 'category_id:n', 'amount:n']],
  [Tables.TRANSACTION, ['id:n', 'ledger_id:n', 'type:n', 'amount:n', 'account_id:n',
    'to_account_id:n', 'category_id:n', 'related_tx_id:n', 'note:t', 'image_paths:t',
    'tx_date:n', 'created_at:n', 'updated_at:n']]
]);

export class BackupService {
  private static readonly TAG: string = 'BackupService';
  private static readonly BACKUP_SUFFIX: string = '.json';
  /** 导入文件只含结构化账本数据，限制大小以避免恶意或误选文件耗尽内存。 */
  private static readonly MAX_BACKUP_BYTES: number = 20 * 1024 * 1024;

  /**
   * 构建备份 JSON 字符串（全量 6 表；meta 含版本/时间/行数统计，架构 1.2）。
   */
  public static async buildBackupJson(): Promise<string> {
    const backup: BackupFileJson = await BackupService.buildBackupData();
    return JSON.stringify(backup);
  }

  /**
   * 备份导出链路：JSON → 沙箱临时文件（failed/'temp_file'）
   *   → picker.save(['.json'])（空数组=cancelled；异常=failed/'picker'）
   *   → 拷贝（failed/'copy'）→ 清理 → saved（count = rows_total）。
   * 与 CSV 导出共用三态语义（架构 4.2 时序）。
   */
  public static async exportViaPicker(context: common.UIAbilityContext): Promise<ExportOutcome> {
    LogUtil.timeStart(BackupService.TAG + '/exportViaPicker');
    const json: string = await BackupService.buildBackupJson();
    const outcome: ExportOutcome = new ExportOutcome();

    // 文件名：轻账本_备份_yyyyMMdd_HHmmss.json（架构 R5）
    const now: number = DateUtil.now();
    const stamp: string = DateUtil.formatDate(now).split('-').join('') + '_' +
      DateUtil.formatTime(now).split(':').join('');
    const fileName: string = AppConstants.BACKUP_FILE_PREFIX + stamp + BackupService.BACKUP_SUFFIX;

    const sandboxFile: string = FileUtil.sandboxPath(context, 'backup', fileName);
    const encoder: util.TextEncoder = new util.TextEncoder();
    const bytes: Uint8Array = encoder.encodeInto(json);
    try {
      FileUtil.writeBytes(context, sandboxFile, bytes);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      LogUtil.e(BackupService.TAG, 'backup failed at temp_file: ' + err.message);
      outcome.status = ExportStatus.FAILED;
      outcome.failurePoint = 'temp_file';
      return outcome;
    }

    try {
      const pickerInstance: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const saveOptions: picker.DocumentSaveOptions = {
        newFileNames: [fileName],
        fileSuffixChoices: [BackupService.BACKUP_SUFFIX]
      };
      const uris: Array<string> = await pickerInstance.save(saveOptions);
      if (uris.length === 0) {
        // 用户取消：显式 cancelled，静默无 Toast（架构 R8 同款语义）
        LogUtil.d(BackupService.TAG, 'backup cancelled by user');
        outcome.status = ExportStatus.CANCELLED;
        return outcome;
      }
      try {
        FileUtil.copyToUri(context, sandboxFile, uris[0]);
      } catch (e) {
        const err: BusinessError = e as BusinessError;
        LogUtil.e(BackupService.TAG, 'backup failed at copy: ' + err.message);
        outcome.status = ExportStatus.FAILED;
        outcome.failurePoint = 'copy';
        outcome.detail = (err.code !== undefined && err.code !== null ? String(err.code) : '?') + ': ' + err.message;
        return outcome;
      }
      const total: number = BackupService.countRowsTotal(json);
      outcome.status = ExportStatus.SAVED;
      outcome.uri = uris[0];
      outcome.count = total;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      LogUtil.e(BackupService.TAG, 'backup failed at picker: ' + err.message);
      outcome.status = ExportStatus.FAILED;
      outcome.failurePoint = 'picker';
      return outcome;
    } finally {
      FileUtil.deleteFile(sandboxFile);
      LogUtil.timeEnd(BackupService.TAG + '/exportViaPicker');
    }
    return outcome;
  }

  /**
   * 拉起系统文件选择器（免权限）挑选备份文件（架构 4.3 时序：选择 → 二次确认 → 恢复）。
   * 返回所选文件 URI；用户取消返回空串。
   */
  public static async pickBackupFile(context: common.UIAbilityContext): Promise<string> {
    try {
      const pickerInstance: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      // 单选默认：本 SDK 的 DocumentSelectOptions 无 maxFileNumber 字段，走无参重载
      const uris: Array<string> = await pickerInstance.select();
      if (uris.length === 0) {
        return '';
      }
      return uris[0];
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      LogUtil.e(BackupService.TAG, 'pickBackupFile failed: ' + err.message);
      return '';
    }
  }

  /**
   * 从 Picker 授权 URI 读取备份文件并校验、整库恢复（架构 4.3 时序）。
   * 校验失败不触碰数据库；恢复成功返回总行数。
   * @param uri DocumentViewPicker.select 返回的文件 URI
   */
  public static async restoreFromJson(uri: string): Promise<number> {
    const text: string = FileUtil.readTextFromUri(uri, BackupService.MAX_BACKUP_BYTES);
    if (text.length === 0) {
      throw new Error(ErrorMessages.BACKUP_INVALID);
    }
    const backup: BackupFileJson = await BackupService.validateBackupJson(text);
    const defaultLedgerId: number = BackupService.resolveDefaultLedgerId(backup.data);
    const rowsTotal: number = backup.meta.rows_total;

    const db: DatabaseManager = DatabaseManager.getInstance();
    await db.runInTransaction<void>(async (store: relationalStore.RdbStore) => {
      // 1. 清空 6 张业务表（BUSINESS_TABLES 序：先子后父，无外键约束仅为可读性）
      for (let i = 0; i < BUSINESS_TABLES.length; i++) {
        await store.executeSql('DELETE FROM ' + BUSINESS_TABLES[i]);
      }
      // 2. 显式主键按依赖顺序插入，保证跨表引用（account_id/category_id 等）不错位
      for (let i = 0; i < BACKUP_TABLES.length; i++) {
        const table: string = BACKUP_TABLES[i];
        const rows: Record<string, Object>[] = BackupService.rowsOf(backup.data, table);
        const columns: string[] = TABLE_COLUMNS.get(table) as string[];
        for (let j = 0; j < rows.length; j++) {
          const bucket: relationalStore.ValuesBucket =
            BackupService.rowToBucket(rows[j], columns);
          await store.insert(table, bucket);
        }
      }
    });
    // 仅在 RDB 事务提交成功后写偏好，避免提交失败时留下指向不存在账本的指针。
    SettingsService.setCurrentLedgerId(defaultLedgerId);
    SettingsService.setLastAccountId(0);
    SettingsService.setLastCategoryId(0);
    DataBus.bump();
    LogUtil.i(BackupService.TAG, 'restore done, rowsTotal=' + rowsTotal.toString());
    return rowsTotal;
  }

  /**
   * 只读预检：读取并执行完整结构校验，但绝不获取数据库、删除或写入任何数据。
   * 用于用户确认覆盖前明确发现损坏/不兼容备份。
   */
  public static async validateBackupUri(uri: string): Promise<number> {
    const text: string = FileUtil.readTextFromUri(uri, BackupService.MAX_BACKUP_BYTES);
    if (text.length === 0) {
      throw new Error(ErrorMessages.BACKUP_INVALID);
    }
    const backup: BackupFileJson = await BackupService.validateBackupJson(text);
    return backup.meta.rows_total;
  }

  /**
   * 备份文件校验（架构 1.2 五项）：任一不通过即拒绝，不进入覆盖流程。
   * 通过则返回解析后的结构化备份（供恢复流程复用，避免二次解析）。
   */
  public static async validateBackupJson(json: string): Promise<BackupFileJson> {
    if (json.length === 0) {
      throw new Error(ErrorMessages.BACKUP_INVALID);
    }
    let backup: BackupFileJson;
    try {
      backup = JSON.parse(json) as BackupFileJson;
    } catch (e) {
      throw new Error(ErrorMessages.BACKUP_INVALID);
    }
    if (backup === null || backup === undefined ||
      backup.meta === null || backup.meta === undefined ||
      backup.data === null || backup.data === undefined) {
      throw new Error(ErrorMessages.BACKUP_INVALID);
    }
    if (backup.meta.app !== AppConstants.BACKUP_APP_NAME ||
      !BackupService.isNonNegativeInteger(backup.meta.exported_at) || backup.meta.exported_at <= 0 ||
      !BackupService.isNonNegativeInteger(backup.meta.rows_total)) {
      throw new Error(ErrorMessages.BACKUP_INVALID);
    }
    // ③ schema 版本（架构 R9：≤ CURRENT_SCHEMA_VERSION 才可恢复；缺失视为损坏）
    if (!BackupService.isNonNegativeInteger(backup.meta.schema_version) ||
      backup.meta.schema_version < 1 || backup.meta.schema_version > CURRENT_SCHEMA_VERSION) {
      throw new Error(ErrorMessages.BACKUP_VERSION_INCOMPATIBLE);
    }
    BackupService.validateTableKeys(backup.data);
    BackupService.validateCountKeys(backup.meta.row_counts);
    // ② 恰好含 6 个表键且均为数组 + ④ row_counts 逐表核对
    let total: number = 0;
    for (let i = 0; i < BACKUP_TABLES.length; i++) {
      const table: string = BACKUP_TABLES[i];
      const rows: Record<string, Object>[] = BackupService.rowsOf(backup.data, table);
      const expected: number = BackupService.expectedCount(backup.meta, table);
      if (rows.length !== expected) {
        throw new Error(ErrorMessages.BACKUP_INVALID);
      }
      total += rows.length;
    }
    if (total !== backup.meta.rows_total) {
      throw new Error(ErrorMessages.BACKUP_INVALID);
    }
    // ⑤ 逐行必填字段存在且类型合法
    for (let i = 0; i < BACKUP_TABLES.length; i++) {
      const table: string = BACKUP_TABLES[i];
      const rows: Record<string, Object>[] = BackupService.rowsOf(backup.data, table);
      for (let j = 0; j < rows.length; j++) {
        BackupService.validateRow(table, rows[j]);
      }
    }
    BackupService.validateRelations(backup.data);
    return backup;
  }

  // ---------- 内部实现 ----------

  /** 全量读取 6 表并组装备份结构 */
  private static async buildBackupData(): Promise<BackupFileJson> {
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    const versionName: string = BackupService.appVersion();
    const counts: Record<string, number> = {};
    const data: BackupDataJson = {
      'll_ledger': [],
      'll_account': [],
      'll_category': [],
      'll_budget': [],
      'll_budget_item': [],
      'll_transaction': []
    };
    let total: number = 0;
    for (let i = 0; i < BACKUP_TABLES.length; i++) {
      const table: string = BACKUP_TABLES[i];
      const rows: Record<string, Object>[] =
        await BackupService.readAllRows(store, table, TABLE_COLUMNS.get(table) as string[]);
      counts[table] = rows.length;
      total += rows.length;
      BackupService.assignRows(data, table, rows);
    }
    const meta: BackupMetaJson = {
      app: AppConstants.BACKUP_APP_NAME,
      app_version: versionName,
      schema_version: CURRENT_SCHEMA_VERSION,
      exported_at: DateUtil.now(),
      row_counts: counts,
      rows_total: total
    };
    const backup: BackupFileJson = { meta: meta, data: data };
    return backup;
  }

  /** 读取整表为「列名 → 值」行数组（数值列 getLong，文本列 getString，原样序列化） */
  private static async readAllRows(store: relationalStore.RdbStore, table: string,
    columns: string[]): Promise<Record<string, Object>[]> {
    const resultSet: relationalStore.ResultSet =
      await store.querySql('SELECT * FROM ' + table);
    const rows: Record<string, Object>[] = [];
    try {
      while (resultSet.goToNextRow()) {
        const row: Record<string, Object> = {};
        for (let i = 0; i < columns.length; i++) {
          const spec: string = columns[i];
          const sep: number = spec.lastIndexOf(':');
          const colName: string = spec.substring(0, sep);
          const isText: boolean = spec.substring(sep + 1) === 't';
          if (isText) {
            row[colName] = resultSet.getString(resultSet.getColumnIndex(colName));
          } else {
            row[colName] = resultSet.getLong(resultSet.getColumnIndex(colName));
          }
        }
        rows.push(row);
      }
    } finally {
      resultSet.close();
    }
    return rows;
  }

  /** 行 → 插入值桶（含显式主键 id；类型兜底：文本缺省 ''、数值缺省 0） */
  private static rowToBucket(row: Record<string, Object>,
    columns: string[]): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {};
    for (let i = 0; i < columns.length; i++) {
      const spec: string = columns[i];
      const sep: number = spec.lastIndexOf(':');
      const colName: string = spec.substring(0, sep);
      const isText: boolean = spec.substring(sep + 1) === 't';
      const value: Object | undefined = row[colName];
      if (isText) {
        bucket[colName] = (typeof value === 'string') ? (value as string) : '';
      } else {
        bucket[colName] = (typeof value === 'number') ? (value as number) : 0;
      }
    }
    return bucket;
  }

  /** 取指定表的行数组；键缺失或非数组即校验失败（结构不符） */
  private static rowsOf(data: BackupDataJson, table: string): Record<string, Object>[] {
    let rows: Record<string, Object>[] = [];
    if (table === Tables.LEDGER) {
      rows = data.ll_ledger;
    } else if (table === Tables.ACCOUNT) {
      rows = data.ll_account;
    } else if (table === Tables.CATEGORY) {
      rows = data.ll_category;
    } else if (table === Tables.BUDGET) {
      rows = data.ll_budget;
    } else if (table === Tables.BUDGET_ITEM) {
      rows = data.ll_budget_item;
    } else if (table === Tables.TRANSACTION) {
      rows = data.ll_transaction;
    }
    if (rows === null || rows === undefined || !Array.isArray(rows)) {
      throw new Error(ErrorMessages.BACKUP_INVALID);
    }
    return rows;
  }

  /** meta.row_counts 中该表的期望行数（缺失即校验失败） */
  private static expectedCount(meta: BackupMetaJson, table: string): number {
    const counts: Record<string, number> = meta.row_counts;
    if (counts === null || counts === undefined) {
      throw new Error(ErrorMessages.BACKUP_INVALID);
    }
    const value: number | undefined = counts[table];
    if (value === undefined || !BackupService.isNonNegativeInteger(value)) {
      throw new Error(ErrorMessages.BACKUP_INVALID);
    }
    return value;
  }

  /** 将行数组写入 data 的对应表键 */
  private static assignRows(data: BackupDataJson, table: string,
    rows: Record<string, Object>[]): void {
    if (table === Tables.LEDGER) {
      data.ll_ledger = rows;
    } else if (table === Tables.ACCOUNT) {
      data.ll_account = rows;
    } else if (table === Tables.CATEGORY) {
      data.ll_category = rows;
    } else if (table === Tables.BUDGET) {
      data.ll_budget = rows;
    } else if (table === Tables.BUDGET_ITEM) {
      data.ll_budget_item = rows;
    } else if (table === Tables.TRANSACTION) {
      data.ll_transaction = rows;
    }
  }

  /** data 只能含当前版本定义的六张表，防止未知字段被静默忽略后产生误导性恢复。 */
  private static validateTableKeys(data: BackupDataJson): void {
    const keys: string[] = Object.keys(data);
    if (keys.length !== BACKUP_TABLES.length) {
      throw new Error(ErrorMessages.BACKUP_INVALID);
    }
    for (let i = 0; i < keys.length; i++) {
      if (BACKUP_TABLES.indexOf(keys[i]) < 0) {
        throw new Error(ErrorMessages.BACKUP_INVALID);
      }
    }
  }

  /** row_counts 与 data 一样必须严格对应六张业务表，额外或缺失键均拒绝。 */
  private static validateCountKeys(counts: Record<string, number>): void {
    if (counts === null || counts === undefined) {
      throw new Error(ErrorMessages.BACKUP_INVALID);
    }
    const keys: string[] = Object.keys(counts);
    if (keys.length !== BACKUP_TABLES.length) {
      throw new Error(ErrorMessages.BACKUP_INVALID);
    }
    for (let i = 0; i < keys.length; i++) {
      if (BACKUP_TABLES.indexOf(keys[i]) < 0) {
        throw new Error(ErrorMessages.BACKUP_INVALID);
      }
    }
  }

  /** 逐行字段校验：列必须齐全，数值必须是安全整数，文本必须是字符串。 */
  private static validateRow(table: string, row: Record<string, Object>): void {
    const columns: string[] = TABLE_COLUMNS.get(table) as string[];
    for (let i = 0; i < columns.length; i++) {
      const spec: string = columns[i];
      const sep: number = spec.lastIndexOf(':');
      const key: string = spec.substring(0, sep);
      const value: Object | undefined = row[key];
      if (spec.substring(sep + 1) === 't') {
        if (typeof value !== 'string') {
          throw new Error(ErrorMessages.BACKUP_INVALID);
        }
      } else if (typeof value !== 'number' || !BackupService.isAllowedInteger(table, key, value as number)) {
        throw new Error(ErrorMessages.BACKUP_INVALID);
      }
    }
    if (BackupService.num(row, 'id') <= 0) {
      throw new Error(ErrorMessages.BACKUP_INVALID);
    }
    if ((table === Tables.LEDGER || table === Tables.ACCOUNT || table === Tables.CATEGORY) &&
      BackupService.str(row, 'name').trim().length === 0) {
      throw new Error(ErrorMessages.BACKUP_INVALID);
    }
  }

  /** 期初余额允许为负，其余当前 schema 数值列均为非负整数。 */
  private static isAllowedInteger(table: string, key: string, value: number): boolean {
    if (!Number.isSafeInteger(value)) {
      return false;
    }
    return (table === Tables.ACCOUNT && key === 'initial_balance') || value >= 0;
  }

  /** 校验主外键与转账配对，防止结构正确但引用已断裂的备份覆盖现有数据。 */
  private static validateRelations(data: BackupDataJson): void {
    const ledgerIds: Set<number> = new Set<number>();
    const accountLedgerIds: Map<number, number> = new Map<number, number>();
    const categoryLedgerIds: Map<number, number> = new Map<number, number>();
    const categoryTypes: Map<number, number> = new Map<number, number>();
    const budgetLedgerIds: Map<number, number> = new Map<number, number>();
    const budgetItemIds: Set<number> = new Set<number>();
    const transactions: Map<number, Record<string, Object>> = new Map<number, Record<string, Object>>();

    const ledgers: Record<string, Object>[] = BackupService.rowsOf(data, Tables.LEDGER);
    for (let i = 0; i < ledgers.length; i++) {
      const id: number = BackupService.num(ledgers[i], 'id');
      if (ledgerIds.has(id)) {
        throw new Error(ErrorMessages.BACKUP_INVALID);
      }
      ledgerIds.add(id);
    }
    if (ledgerIds.size === 0) {
      throw new Error(ErrorMessages.BACKUP_INVALID);
    }

    const accounts: Record<string, Object>[] = BackupService.rowsOf(data, Tables.ACCOUNT);
    for (let i = 0; i < accounts.length; i++) {
      const id: number = BackupService.num(accounts[i], 'id');
      const ledgerId: number = BackupService.num(accounts[i], 'ledger_id');
      if (accountLedgerIds.has(id) || !ledgerIds.has(ledgerId)) {
        throw new Error(ErrorMessages.BACKUP_INVALID);
      }
      accountLedgerIds.set(id, ledgerId);
    }

    const categories: Record<string, Object>[] = BackupService.rowsOf(data, Tables.CATEGORY);
    for (let i = 0; i < categories.length; i++) {
      const id: number = BackupService.num(categories[i], 'id');
      const ledgerId: number = BackupService.num(categories[i], 'ledger_id');
      if (categoryLedgerIds.has(id) || !ledgerIds.has(ledgerId)) {
        throw new Error(ErrorMessages.BACKUP_INVALID);
      }
      categoryLedgerIds.set(id, ledgerId);
      categoryTypes.set(id, BackupService.num(categories[i], 'type'));
    }

    const budgets: Record<string, Object>[] = BackupService.rowsOf(data, Tables.BUDGET);
    for (let i = 0; i < budgets.length; i++) {
      const id: number = BackupService.num(budgets[i], 'id');
      const ledgerId: number = BackupService.num(budgets[i], 'ledger_id');
      if (budgetLedgerIds.has(id) || !ledgerIds.has(ledgerId)) {
        throw new Error(ErrorMessages.BACKUP_INVALID);
      }
      budgetLedgerIds.set(id, ledgerId);
    }

    const budgetItems: Record<string, Object>[] = BackupService.rowsOf(data, Tables.BUDGET_ITEM);
    for (let i = 0; i < budgetItems.length; i++) {
      const id: number = BackupService.num(budgetItems[i], 'id');
      const budgetLedgerId: number = budgetLedgerIds.get(BackupService.num(budgetItems[i], 'budget_id')) ?? 0;
      const categoryLedgerId: number = categoryLedgerIds.get(BackupService.num(budgetItems[i], 'category_id')) ?? 0;
      if (budgetItemIds.has(id) || budgetLedgerId === 0 || budgetLedgerId !== categoryLedgerId) {
        throw new Error(ErrorMessages.BACKUP_INVALID);
      }
      budgetItemIds.add(id);
    }

    const txRows: Record<string, Object>[] = BackupService.rowsOf(data, Tables.TRANSACTION);
    for (let i = 0; i < txRows.length; i++) {
      const tx: Record<string, Object> = txRows[i];
      const id: number = BackupService.num(tx, 'id');
      const ledgerId: number = BackupService.num(tx, 'ledger_id');
      const accountLedgerId: number = accountLedgerIds.get(BackupService.num(tx, 'account_id')) ?? 0;
      const categoryId: number = BackupService.num(tx, 'category_id');
      const toAccountId: number = BackupService.num(tx, 'to_account_id');
      const categoryLedgerId: number = categoryId > 0 ? (categoryLedgerIds.get(categoryId) ?? 0) : ledgerId;
      const toAccountLedgerId: number = toAccountId > 0 ? (accountLedgerIds.get(toAccountId) ?? 0) : ledgerId;
      const type: number = BackupService.num(tx, 'type');
      const expectedCategoryType: number = type === 1 ? 1 : 0;
      if (transactions.has(id) || !ledgerIds.has(ledgerId) || accountLedgerId !== ledgerId ||
        categoryLedgerId !== ledgerId || toAccountLedgerId !== ledgerId ||
        (categoryId > 0 && categoryTypes.get(categoryId) !== expectedCategoryType)) {
        throw new Error(ErrorMessages.BACKUP_INVALID);
      }
      transactions.set(id, tx);
    }

    for (const tx of transactions.values()) {
      const type: number = BackupService.num(tx, 'type');
      const relatedId: number = BackupService.num(tx, 'related_tx_id');
      const toAccountId: number = BackupService.num(tx, 'to_account_id');
      const categoryId: number = BackupService.num(tx, 'category_id');
      const accountId: number = BackupService.num(tx, 'account_id');
      const amount: number = BackupService.num(tx, 'amount');
      if (type < 0 || type > 2 || !Number.isSafeInteger(amount) || amount <= 0 ||
        amount > AppConstants.MAX_MONEY_FEN ||
        BackupService.num(tx, 'tx_date') <= 0 ||
        BackupService.str(tx, 'note').length > AppConstants.MAX_NOTE_LENGTH) {
        throw new Error(ErrorMessages.BACKUP_INVALID);
      }
      if (type === 2) {
        const pair: Record<string, Object> | undefined = transactions.get(relatedId);
        if (relatedId <= 0 || toAccountId <= 0 || categoryId !== 0 || accountId === toAccountId || pair === undefined ||
          BackupService.num(pair, 'type') !== 2 || BackupService.num(pair, 'related_tx_id') !== BackupService.num(tx, 'id') ||
          BackupService.num(pair, 'ledger_id') !== BackupService.num(tx, 'ledger_id') ||
          BackupService.num(pair, 'amount') !== BackupService.num(tx, 'amount') ||
          BackupService.num(pair, 'account_id') !== toAccountId ||
          BackupService.num(pair, 'to_account_id') !== BackupService.num(tx, 'account_id')) {
          throw new Error(ErrorMessages.BACKUP_INVALID);
        }
      } else if (categoryId <= 0 || relatedId !== 0 || toAccountId !== 0) {
        throw new Error(ErrorMessages.BACKUP_INVALID);
      }
    }
  }

  private static isNonNegativeInteger(value: number): boolean {
    return Number.isSafeInteger(value) && value >= 0;
  }

  /** 备份中 is_default=1 的账本 id；无 is_default 行时回退首个账本；再回退默认账本 */
  private static resolveDefaultLedgerId(data: BackupDataJson): number {
    const ledgers: Record<string, Object>[] = BackupService.rowsOf(data, Tables.LEDGER);
    let firstId: number = 0;
    for (let i = 0; i < ledgers.length; i++) {
      const row: Record<string, Object> = ledgers[i];
      const id: number = BackupService.num(row, 'id');
      if (firstId === 0 && id > 0) {
        firstId = id;
      }
      if (BackupService.num(row, 'is_default') === 1 && id > 0) {
        return id;
      }
    }
    if (firstId > 0) {
      return firstId;
    }
    return AppConstants.DEFAULT_LEDGER_ID;
  }

  /** 从备份 JSON 取 rows_total（exportViaPicker 用；解析失败按 0 处理，不影响保存） */
  private static countRowsTotal(json: string): number {
    try {
      const backup: BackupFileJson = JSON.parse(json) as BackupFileJson;
      if (backup !== null && backup !== undefined && backup.meta !== null &&
        backup.meta !== undefined) {
        return backup.meta.rows_total;
      }
    } catch (e) {
      LogUtil.w(BackupService.TAG, 'countRowsTotal parse failed');
    }
    return 0;
  }

  /** 应用版本号（meta.app_version；读取失败回退空串） */
  private static appVersion(): string {
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionName;
    } catch (e) {
      LogUtil.w(BackupService.TAG, 'appVersion read failed');
      return '';
    }
  }

  /** 行字段数值读取（非法/缺失回退 0） */
  private static num(row: Record<string, Object>, key: string): number {
    const value: Object | undefined = row[key];
    return (typeof value === 'number') ? (value as number) : 0;
  }

  /** 行字段文本读取（非法/缺失回退 ''） */
  private static str(row: Record<string, Object>, key: string): string {
    const value: Object | undefined = row[key];
    return (typeof value === 'string') ? (value as string) : '';
  }
}
