/**
 * 模块职责：RDB 单例（架构 5.1 / T02）。
 * - init(context)：建库 → 读 schema_version → freshInstall / upgrade / 降级保护
 * - runInTransaction<T>：begin/commit/rollBack 包装；异步 SQL 必须 await 完成后
 *   再 commit（官方明确警告，否则操作丢失）
 * - clearAllData()：DELETE 业务表（不 DROP，保留 schema）+ 重跑 seed（架构 4.5 规则 5）
 * - 全应用唯一的 relationalStore 使用入口，pages/components 禁止 import 本模块
 */
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  BUSINESS_TABLES,
  CREATE_META_TABLE,
  CURRENT_SCHEMA_VERSION
} from './SchemaConstants';
import { AppConstants } from '../constants/AppConstants';
import { ErrorMessages } from '../constants/ErrorMessages';
import { MigrationManager } from './MigrationManager';
import { SeedDataManager } from './SeedDataManager';
import { LogUtil } from '../utils/LogUtil';
import { ToastUtil } from '../utils/ToastUtil';

export class DatabaseManager {
  private static readonly TAG: string = 'DatabaseManager';
  private static instance: DatabaseManager | null = null;
  private static initPromise: Promise<void> | null = null;

  private store: relationalStore.RdbStore | null = null;
  /** 降级保护：高版本数据库打开低版本 App 时只读，禁止写库（架构 4.5） */
  private readOnlyMode: boolean = false;
  /**
   * RdbStore 的事务不能交叉执行。页面虽有各自的防重入状态，但不同页面或异步回调
   * 仍可能同时发起写入；用尾 Promise 将事务串行化，避免 begin/commit 互相覆盖。
   */
  private transactionTail: Promise<void> = Promise.resolve();

  private constructor() {
  }

  /** 单例入口 */
  public static getInstance(): DatabaseManager {
    if (DatabaseManager.instance === null) {
      DatabaseManager.instance = new DatabaseManager();
    }
    return DatabaseManager.instance;
  }

  /**
   * 初始化（幂等，并发安全：多次调用共享同一个 Promise）。
   * 在隐私同意之后调用（架构 6.1 时序），Failure 时抛出业务异常。
   */
  public init(context: common.Context): Promise<void> {
    if (DatabaseManager.initPromise !== null) {
      return DatabaseManager.initPromise;
    }
    DatabaseManager.initPromise = this.doInit(context);
    return DatabaseManager.initPromise;
  }

  /** 内部初始化流程 */
  private async doInit(context: common.Context): Promise<void> {
    if (this.store !== null) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: AppConstants.DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    try {
      const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);
      this.store = store;
      // meta 表必须最先存在，否则无法读取 schema 版本
      await store.executeSql(CREATE_META_TABLE);
      const current: number = await MigrationManager.readVersion(store);
      LogUtil.i(DatabaseManager.TAG, 'schema_version=' + current.toString());

      if (current > CURRENT_SCHEMA_VERSION) {
        // 降级保护：只读模式，禁止写库，提示用户备份后重装
        this.readOnlyMode = true;
        LogUtil.w(DatabaseManager.TAG, 'db version newer than app, enter read-only mode');
        ToastUtil.showLong('当前数据库版本高于应用版本，数据将以只读方式打开');
        return;
      }
      if (current === 0) {
        await MigrationManager.freshInstall(store);
        return;
      }
      if (current < CURRENT_SCHEMA_VERSION) {
        await MigrationManager.upgrade(store, current);
      }
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      LogUtil.e(DatabaseManager.TAG, 'init failed: ' + err.message);
      this.store = null;
      DatabaseManager.initPromise = null;
      throw new Error(ErrorMessages.DB_INIT_FAILED + err.message);
    }
  }

  /** 获取 RdbStore；未初始化时抛业务异常（调用方为 service 层，异常会被 ViewModel 捕获） */
  public getStore(): relationalStore.RdbStore {
    if (this.store === null) {
      throw new Error(ErrorMessages.DB_NOT_INITIALIZED);
    }
    return this.store;
  }

  /** 是否处于只读降级模式 */
  public isReadOnly(): boolean {
    return this.readOnlyMode;
  }

  /** 是否已就绪 */
  public isReady(): boolean {
    return this.store !== null;
  }

  /**
   * 事务包装：begin → await fn → commit；异常 rollBack 后 rethrow（架构 T02 约束 1）。
   * 用法示例（T03）：
   *   await db.runInTransaction(async (store) => { await store.insert(...); return id; });
   */
  public async runInTransaction<T>(fn: (store: relationalStore.RdbStore) => Promise<T>): Promise<T> {
    const store: relationalStore.RdbStore = this.getStore();
    if (this.readOnlyMode) {
      throw new Error(ErrorMessages.DB_READ_ONLY);
    }
    let release: () => void = (): void => {};
    const previous: Promise<void> = this.transactionTail;
    this.transactionTail = new Promise<void>((resolve: () => void): void => {
      release = resolve;
    });
    await previous;
    try {
      store.beginTransaction();
      const result: T = await fn(store);
      await store.commit();
      return result;
    } catch (e) {
      try {
        store.rollBack();
      } catch (rollBackError) {
        LogUtil.e(DatabaseManager.TAG, 'rollBack failed');
      }
      const rollbackErr: BusinessError = e as BusinessError;
      throw new Error(rollbackErr.message);
    } finally {
      release();
    }
  }

  /**
   * 清空全部业务数据（我的 → 清空数据）。
   * 只 DELETE 不 DROP：保留表结构与索引，schema_version 不变，随后重跑 seed
   * （预置分类/账本/现金账户恢复，架构 4.5 规则 5）。
   */
  public async clearAllData(): Promise<void> {
    try {
      await this.runInTransaction<void>(async (store: relationalStore.RdbStore): Promise<void> => {
        for (let i = 0; i < BUSINESS_TABLES.length; i++) {
          await store.executeSql('DELETE FROM ' + BUSINESS_TABLES[i]);
        }
        await SeedDataManager.seed(store);
      });
      LogUtil.i(DatabaseManager.TAG, 'all data cleared and reseeded');
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      LogUtil.e(DatabaseManager.TAG, 'clearAllData failed: ' + err.message);
      throw new Error(ErrorMessages.DB_CLEAR_FAILED + err.message);
    }
  }

  /** 关闭数据库（EntryAbility.onDestroy 调用；当前版本无显式 close API，置空即可） */
  public close(): void {
    this.store = null;
    DatabaseManager.initPromise = null;
  }
}
