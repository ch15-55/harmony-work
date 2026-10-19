/**
 * 模块职责：DB 版本迁移框架（架构 4.5 / T02）。
 *
 * 为什么版本存 ll_meta 而不用 PRAGMA user_version：
 * PRAGMA 语句经 relationalStore 的返回值解析不稳定，且无法承载迁移日志；
 * 自建 meta 表可同时存 schema_version 与 last_migrate_at，可读可测。
 *
 * 迁移执行规则（必须遵守）：
 * 1. 逐级升级：按 from===当前版本 定位步骤，禁止跨级跳步；
 * 2. 每级一个事务：sql[] + migrate() + 更新版本号同事务，任一异常 rollBack 后向上抛；
 * 3. 只增不改：新增字段一律 ALTER TABLE ADD COLUMN ... NOT NULL DEFAULT <默认值>；
 *    禁止 DROP COLUMN、禁改字段类型；
 * 4. 预置数据不重复插入（SeedDataManager 幂等）；
 * 5. 清库保留 schema：clearAllData 只 DELETE 业务表，版本号不变并重跑 seed。
 */
import { relationalStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  CREATE_INDEXES,
  CREATE_META_TABLE,
  CREATE_TABLES,
  CURRENT_SCHEMA_VERSION,
  META_KEY_LAST_MIGRATE_AT,
  META_KEY_SCHEMA_VERSION
} from './SchemaConstants';
import { SeedDataManager } from './SeedDataManager';
import { LogUtil } from '../utils/LogUtil';

/** 单级迁移步骤（v1.0 数组为空，框架完整可用） */
export class MigrationStep {
  /** 起始版本 */
  public from: number = 0;
  /** 目标版本 */
  public to: number = 0;
  /** 本级执行的 DDL/DML 语句，按序执行 */
  public sql: string[] = [];
  /** 语句无法表达的数据整形逻辑（可选） */
  public migrate?: (store: relationalStore.RdbStore) => Promise<void>;
}

export class MigrationManager {
  private static readonly TAG: string = 'MigrationManager';

  /**
   * 逐级迁移脚本数组。
   * v1.1 示例（届时追加，勿修改历史条目）：
   *   const step = new MigrationStep();
   *   step.from = 1; step.to = 2;
   *   step.sql = ['ALTER TABLE ll_transaction ADD COLUMN tag TEXT NOT NULL DEFAULT ""'];
   *   MIGRATIONS.push(step);
   */
  public static readonly MIGRATIONS: MigrationStep[] = [];

  /**
   * 首次安装：建 meta 表 → 建全部业务表 → 建全部索引 → 预置数据 → 写版本号。
   * 全程单事务；失败 rollBack 后向上抛，由 DatabaseManager 转成用户可读提示。
   */
  public static async freshInstall(store: relationalStore.RdbStore): Promise<void> {
    store.beginTransaction();
    try {
      await store.executeSql(CREATE_META_TABLE);
      for (let i = 0; i < CREATE_TABLES.length; i++) {
        await store.executeSql(CREATE_TABLES[i]);
      }
      for (let i = 0; i < CREATE_INDEXES.length; i++) {
        await store.executeSql(CREATE_INDEXES[i]);
      }
      // 预置数据与建表同事务：保证「建表成功即有预置数据」的原子性
      await SeedDataManager.seed(store);
      await MigrationManager.writeVersion(store, CURRENT_SCHEMA_VERSION);
      store.commit();
      LogUtil.i(MigrationManager.TAG, 'fresh install done, schema_version=' + CURRENT_SCHEMA_VERSION.toString());
    } catch (e) {
      store.rollBack();
      const err: BusinessError = e as BusinessError;
      LogUtil.e(MigrationManager.TAG, 'freshInstall failed: ' + err.message);
      throw new Error(err.message);
    }
  }

  /**
   * 从 fromVersion 逐级升级到 CURRENT_SCHEMA_VERSION。
   * 每级独立事务：DDL + 数据整形 + 版本号更新同事务。
   */
  public static async upgrade(store: relationalStore.RdbStore, fromVersion: number): Promise<void> {
    let current: number = fromVersion;
    while (current < CURRENT_SCHEMA_VERSION) {
      const step: MigrationStep | undefined = MigrationManager.findStep(current);
      if (step === undefined) {
        const msg: string = '缺少 schema v' + current.toString() + ' 的迁移步骤';
        LogUtil.e(MigrationManager.TAG, msg);
        throw new Error(msg);
      }
      await MigrationManager.runStep(store, step);
      current = step.to;
    }
    LogUtil.i(MigrationManager.TAG, 'upgraded to schema_version=' + CURRENT_SCHEMA_VERSION.toString());
  }

  /** 执行单级迁移（独立事务） */
  private static async runStep(store: relationalStore.RdbStore, step: MigrationStep): Promise<void> {
    store.beginTransaction();
    try {
      for (let i = 0; i < step.sql.length; i++) {
        await store.executeSql(step.sql[i]);
      }
      if (step.migrate !== undefined) {
        await step.migrate(store);
      }
      await MigrationManager.writeVersion(store, step.to);
      store.commit();
      LogUtil.i(MigrationManager.TAG, 'migrated v' + step.from.toString() + ' -> v' + step.to.toString());
    } catch (e) {
      store.rollBack();
      const err: BusinessError = e as BusinessError;
      LogUtil.e(MigrationManager.TAG, 'migration failed: ' + err.message);
      throw new Error(err.message);
    }
  }

  /** 定位某起点的迁移步骤 */
  private static findStep(fromVersion: number): MigrationStep | undefined {
    for (let i = 0; i < MigrationManager.MIGRATIONS.length; i++) {
      if (MigrationManager.MIGRATIONS[i].from === fromVersion) {
        return MigrationManager.MIGRATIONS[i];
      }
    }
    return undefined;
  }

  /** 写版本号与迁移时间（须在事务内调用） */
  private static async writeVersion(store: relationalStore.RdbStore, version: number): Promise<void> {
    const now: number = Date.now();
    const upsert: string = 'INSERT OR REPLACE INTO ll_meta (key, value) VALUES (?, ?)';
    await store.executeSql(upsert, [META_KEY_SCHEMA_VERSION, version.toString()]);
    await store.executeSql(upsert, [META_KEY_LAST_MIGRATE_AT, now.toString()]);
  }

  /** 读版本号（DatabaseManager.init 使用；meta 表由调用方保证已存在） */
  public static async readVersion(store: relationalStore.RdbStore): Promise<number> {
    const resultSet: relationalStore.ResultSet =
      await store.querySql('SELECT value FROM ll_meta WHERE key = ?', [META_KEY_SCHEMA_VERSION]);
    let version: number = 0;
    try {
      if (resultSet.goToFirstRow()) {
        const columnIndex: number = resultSet.getColumnIndex('value');
        version = parseInt(resultSet.getString(columnIndex), 10);
        if (Number.isNaN(version)) {
          version = 0;
        }
      }
    } finally {
      // ResultSet 用完必须 close（架构 T02 关键实现约束 2）
      resultSet.close();
    }
    return version;
  }
}
