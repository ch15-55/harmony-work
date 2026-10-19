/**
 * 模块职责：账户领域服务（架构 T03）。
 * - CRUD / 归档 / 删除拦截（有流水禁止删除，提示先归档，架构 R11）
 * - 余额**实时计算不冗余存储**（架构 4.7）：4 子查询一次取齐
 * - 总资产 / 总负债 / 净资产（首页资产卡）
 */
import { relationalStore } from '@kit.ArkData';
import { DatabaseManager } from './DatabaseManager';
import { DataBus } from './DataBus';
import { Tables } from './SchemaConstants';
import { Account } from '../model/Account';
import { AccountBalance, NetAssetSummary } from '../model/StatsModels';
import { AccountType, AppConstants, TxType } from '../constants/AppConstants';
import { SettingsService } from './SettingsService';
import { DateUtil } from '../utils/DateUtil';
import { LogUtil } from '../utils/LogUtil';
import { ErrorMessages } from '../constants/ErrorMessages';

export class AccountService {
  private static readonly TAG: string = 'AccountService';

  /** 全部账户（默认只取未归档，按 sort_order 升序），走 idx_account_ledger */
  public static async listAll(includeArchived: boolean = false): Promise<Account[]> {
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(Tables.ACCOUNT);
    predicates.equalTo('ledger_id', SettingsService.getCurrentLedgerId());
    if (!includeArchived) {
      predicates.equalTo('is_archived', 0);
    }
    predicates.orderByAsc('sort_order');
    predicates.orderByAsc('id');
    const resultSet: relationalStore.ResultSet = await store.query(predicates);
    const list: Account[] = [];
    try {
      while (resultSet.goToNextRow()) {
        list.push(Account.fromRow(resultSet));
      }
    } finally {
      resultSet.close();
    }
    return list;
  }

  /** 按 id 查单条；不存在返回 null */
  public static async getById(id: number): Promise<Account | null> {
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    const resultSet: relationalStore.ResultSet =
      await store.querySql('SELECT * FROM ' + Tables.ACCOUNT + ' WHERE id = ? AND ledger_id = ?',
        [id, SettingsService.getCurrentLedgerId()]);
    let account: Account | null = null;
    try {
      if (resultSet.goToFirstRow()) {
        account = Account.fromRow(resultSet);
      }
    } finally {
      resultSet.close();
    }
    return account;
  }

  /** 新增账户（期初余额任意，信用卡可为负额度另行录入 creditLimit） */
  public static async add(account: Account): Promise<number> {
    if (account.name.trim().length === 0) {
      throw new Error(ErrorMessages.ACCOUNT_NAME_EMPTY);
    }
    AccountService.validateMoneyFields(account);
    const now: number = DateUtil.now();
    account.ledgerId = SettingsService.getCurrentLedgerId();
    account.createdAt = now;
    account.updatedAt = now;
    const db: DatabaseManager = DatabaseManager.getInstance();
    const rowId: number = await db.runInTransaction<number>(async (store: relationalStore.RdbStore): Promise<number> => {
      return await store.insert(Tables.ACCOUNT, account.toValuesBucket());
    });
    DataBus.bump();
    return rowId;
  }

  /** 编辑账户（名称/类型/图标/颜色/期初/额度/排序） */
  public static async update(account: Account): Promise<void> {
    if (account.id <= 0) {
      throw new Error(ErrorMessages.ACCOUNT_NOT_FOUND);
    }
    if (account.name.trim().length === 0) {
      throw new Error(ErrorMessages.ACCOUNT_NAME_EMPTY);
    }
    AccountService.validateMoneyFields(account);
    const ledgerId: number = SettingsService.getCurrentLedgerId();
    account.ledgerId = ledgerId;
    account.updatedAt = DateUtil.now();
    const db: DatabaseManager = DatabaseManager.getInstance();
    await db.runInTransaction<void>(async (store: relationalStore.RdbStore): Promise<void> => {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(Tables.ACCOUNT);
      predicates.equalTo('id', account.id);
      predicates.equalTo('ledger_id', ledgerId);
      const changed: number = await store.update(account.toValuesBucket(), predicates);
      if (changed <= 0) {
        throw new Error(ErrorMessages.ACCOUNT_NOT_FOUND);
      }
    });
    DataBus.bump();
  }

  /** 服务层兜底，账户初始余额与额度必须是可安全累计的整数分。 */
  private static validateMoneyFields(account: Account): void {
    if (!Number.isSafeInteger(account.initialBalance) ||
      Math.abs(account.initialBalance) > AppConstants.MAX_MONEY_FEN ||
      !Number.isSafeInteger(account.creditLimit) ||
      Math.abs(account.creditLimit) > AppConstants.MAX_MONEY_FEN) {
      throw new Error(ErrorMessages.AMOUNT_INVALID);
    }
  }

  /** 归档 / 取消归档（保留历史，不计入总资产） */
  public static async archive(id: number, archived: boolean): Promise<void> {
    const ledgerId: number = SettingsService.getCurrentLedgerId();
    const db: DatabaseManager = DatabaseManager.getInstance();
    await db.runInTransaction<void>(async (store: relationalStore.RdbStore): Promise<void> => {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(Tables.ACCOUNT);
      predicates.equalTo('id', id);
      predicates.equalTo('ledger_id', ledgerId);
      const patch: relationalStore.ValuesBucket = {
        'is_archived': archived ? 1 : 0,
        'updated_at': DateUtil.now()
      };
      const changed: number = await store.update(patch, predicates);
      if (changed <= 0) {
        throw new Error(ErrorMessages.ACCOUNT_NOT_FOUND);
      }
    });
    DataBus.bump();
  }

  /** 是否已有流水引用该账户（删除拦截依据） */
  public static async hasTransactions(id: number): Promise<boolean> {
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    const resultSet: relationalStore.ResultSet = await store.querySql(
      'SELECT COUNT(*) AS cnt FROM ' + Tables.TRANSACTION +
      ' WHERE account_id = ? OR to_account_id = ?', [id, id]);
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

  /**
   * 删除账户：有流水时抛业务异常（UI 提示先归档），无流水才允许删除。
   */
  public static async delete(id: number): Promise<void> {
    const ledgerId: number = SettingsService.getCurrentLedgerId();
    const db: DatabaseManager = DatabaseManager.getInstance();
    await db.runInTransaction<void>(async (store: relationalStore.RdbStore): Promise<void> => {
      const account: Account | null = await AccountService.getById(id);
      if (account === null) {
        throw new Error(ErrorMessages.ACCOUNT_NOT_FOUND);
      }
      if (await AccountService.hasTransactionsIn(store, id)) {
        throw new Error(ErrorMessages.ACCOUNT_HAS_TX);
      }
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(Tables.ACCOUNT);
      predicates.equalTo('id', id);
      predicates.equalTo('ledger_id', ledgerId);
      await store.delete(predicates);
    });
    DataBus.bump();
    LogUtil.d(AccountService.TAG, 'account deleted, id=' + id.toString());
  }

  /**
   * 单账户实时余额（架构 4.7 的 4 子查询）。
   * balance = initialBalance + income - expense + transferIn - transferOut
   */
  public static async getBalance(accountId: number): Promise<AccountBalance> {
    const account: Account | null = await AccountService.getById(accountId);
    const result: AccountBalance = new AccountBalance();
    result.accountId = accountId;
    if (account !== null) {
      result.initialBalance = account.initialBalance;
    }
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    const sql: string = 'SELECT' +
      ' (SELECT COALESCE(SUM(amount),0) FROM ' + Tables.TRANSACTION + ' WHERE account_id = ? AND type = ?) AS income,' +
      ' (SELECT COALESCE(SUM(amount),0) FROM ' + Tables.TRANSACTION + ' WHERE account_id = ? AND type = ?) AS expense,' +
      ' (SELECT COALESCE(SUM(amount),0) FROM ' + Tables.TRANSACTION + ' WHERE type = ? AND to_account_id = ?) AS transfer_in,' +
      ' (SELECT COALESCE(SUM(amount),0) FROM ' + Tables.TRANSACTION + ' WHERE type = ? AND account_id = ?) AS transfer_out';
    const resultSet: relationalStore.ResultSet = await store.querySql(sql, [
      accountId, TxType.INCOME,
      accountId, TxType.EXPENSE,
      TxType.TRANSFER, accountId,
      TxType.TRANSFER, accountId
    ]);
    try {
      if (resultSet.goToFirstRow()) {
        result.income = resultSet.getLong(resultSet.getColumnIndex('income'));
        result.expense = resultSet.getLong(resultSet.getColumnIndex('expense'));
        result.transferIn = resultSet.getLong(resultSet.getColumnIndex('transfer_in'));
        result.transferOut = resultSet.getLong(resultSet.getColumnIndex('transfer_out'));
      }
    } finally {
      resultSet.close();
    }
    return result;
  }

  /**
   * 全部未归档账户的余额（架构 4.7 实时计算）。
   * 性能：两条 GROUP BY 聚合替代旧版「逐户 4 子查询」的 N+1（账户数无关，恒定 2 条 SQL）。
   * 口径不变：balance = initialBalance + income - expense + transferIn - transferOut。
   */
  public static async getAllBalances(): Promise<Map<number, AccountBalance>> {
    const accounts: Account[] = await AccountService.listAll(false);
    const map: Map<number, AccountBalance> = new Map();
    for (let i = 0; i < accounts.length; i++) {
      const b: AccountBalance = new AccountBalance();
      b.accountId = accounts[i].id;
      b.initialBalance = accounts[i].initialBalance;
      map.set(b.accountId, b);
    }
    if (map.size === 0) {
      return map;
    }
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    // 聚合一：收入/支出/转出按 account_id 分组（转账行 account_id = 转出方）
    const rs1: relationalStore.ResultSet = await store.querySql(
      'SELECT account_id AS aid, ' +
      'COALESCE(SUM(CASE WHEN type = ? THEN amount ELSE 0 END), 0) AS income, ' +
      'COALESCE(SUM(CASE WHEN type = ? THEN amount ELSE 0 END), 0) AS expense, ' +
      'COALESCE(SUM(CASE WHEN type = ? THEN amount ELSE 0 END), 0) AS tout ' +
      'FROM ' + Tables.TRANSACTION + ' GROUP BY account_id',
      [TxType.INCOME, TxType.EXPENSE, TxType.TRANSFER]);
    try {
      while (rs1.goToNextRow()) {
        const id: number = rs1.getLong(rs1.getColumnIndex('aid'));
        const b: AccountBalance | undefined = map.get(id);
        if (b !== undefined) {
          b.income = rs1.getLong(rs1.getColumnIndex('income'));
          b.expense = rs1.getLong(rs1.getColumnIndex('expense'));
          b.transferOut = rs1.getLong(rs1.getColumnIndex('tout'));
        }
      }
    } finally {
      rs1.close();
    }
    // 聚合二：转入按 to_account_id 分组
    const rs2: relationalStore.ResultSet = await store.querySql(
      'SELECT to_account_id AS tid, COALESCE(SUM(amount), 0) AS tin FROM ' + Tables.TRANSACTION +
      ' WHERE type = ? GROUP BY to_account_id', [TxType.TRANSFER]);
    try {
      while (rs2.goToNextRow()) {
        const id: number = rs2.getLong(rs2.getColumnIndex('tid'));
        const b: AccountBalance | undefined = map.get(id);
        if (b !== undefined) {
          b.transferIn = rs2.getLong(rs2.getColumnIndex('tin'));
        }
      }
    } finally {
      rs2.close();
    }
    return map;
  }

  /**
   * 资产总览（架构 4.7，口径与 StatsModels.NetAssetSummary 注释一致）：
   * 总资产 = Σ 未归档账户 balance 中 ≥ 0 部分（信用卡欠款不计入资产，避免重复扣减）
   * 总负债 = Σ 信用卡账户 balance < 0 的绝对值
   * 净资产 = 总资产 - 总负债
   * ⚠️ 若把负余额也算进总资产，再减一次总负债会把欠款扣两遍（净资产少报）。
   * 性能：复用 getAllBalances 的聚合结果，不再逐户重查。
   */
  public static async getNetAsset(): Promise<NetAssetSummary> {
    const accounts: Account[] = await AccountService.listAll(false);
    const balances: Map<number, AccountBalance> = await AccountService.getAllBalances();
    const summary: NetAssetSummary = new NetAssetSummary();
    for (let i = 0; i < accounts.length; i++) {
      const balance: AccountBalance | undefined = balances.get(accounts[i].id);
      if (balance === undefined) {
        continue;
      }
      if (balance.balance >= 0) {
        summary.totalAsset += balance.balance;
      }
      if (accounts[i].type === AccountType.CREDIT && balance.balance < 0) {
        summary.totalDebt += -balance.balance;
      }
    }
    summary.netAsset = summary.totalAsset - summary.totalDebt;
    return summary;
  }

  private static async hasTransactionsIn(store: relationalStore.RdbStore, id: number): Promise<boolean> {
    const resultSet: relationalStore.ResultSet = await store.querySql(
      'SELECT COUNT(*) AS cnt FROM ' + Tables.TRANSACTION +
      ' WHERE account_id = ? OR to_account_id = ?', [id, id]);
    try {
      return resultSet.goToFirstRow() && resultSet.getLong(resultSet.getColumnIndex('cnt')) > 0;
    } finally {
      resultSet.close();
    }
  }
}
