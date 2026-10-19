/**
 * 模块职责：流水领域服务（架构 T03）。
 * - 记账 / 编辑 / 删除 / 转账（双流水同一事务）/ 检索 / 最近流水
 * - 转账三条铁律：① 两条 type=2 ② related_tx_id 互指 ③ 删除时事务内双删
 * - 统计口径：所有收支聚合排除 type=2（WHERE type IN (0,1)）
 * - **所有写操作末尾必须 DataBus.bump()**（跨页面刷新唯一机制）
 * - 只允许 throw 业务异常，禁止在 Service 内弹 Toast（架构 9.5）
 */
import { relationalStore } from '@kit.ArkData';
import { DatabaseManager } from './DatabaseManager';
import { DataBus } from './DataBus';
import { Tables } from './SchemaConstants';
import { Transaction } from '../model/Transaction';
import { TxFilter } from '../model/TxFilter';
import { AppConstants, CategoryType, TxType } from '../constants/AppConstants';
import { CategoryService } from './CategoryService';
import { SettingsService } from './SettingsService';
import { DateUtil } from '../utils/DateUtil';
import { LogUtil } from '../utils/LogUtil';
import { ErrorMessages } from '../constants/ErrorMessages';

export class TransactionService {
  private static readonly TAG: string = 'TransactionService';

  /** 记一笔（支出/收入）。事务内：insert + 分类使用频次 +1；事务外：记默认账户/分类 + bump */
  public static async add(tx: Transaction): Promise<number> {
    TransactionService.validateCommon(tx);
    if (tx.type === TxType.TRANSFER) {
      throw new Error(ErrorMessages.TX_USE_ADD_TRANSFER);
    }
    if (tx.accountId <= 0) {
      throw new Error(ErrorMessages.TX_ACCOUNT_REQUIRED);
    }
    if (tx.categoryId <= 0) {
      throw new Error(ErrorMessages.TX_CATEGORY_REQUIRED);
    }
    const ledgerId: number = SettingsService.getCurrentLedgerId();
    const now: number = DateUtil.now();
    tx.createdAt = now;
    tx.updatedAt = now;
    tx.ledgerId = ledgerId;
    tx.relatedTxId = 0;
    tx.toAccountId = 0;

    const db: DatabaseManager = DatabaseManager.getInstance();
    const rowId: number = await db.runInTransaction<number>(async (store: relationalStore.RdbStore) => {
      await TransactionService.requireAccountInLedger(store, tx.accountId, ledgerId);
      await TransactionService.requireCategoryInLedger(store, tx.categoryId, ledgerId, tx.type);
      const rowId: number = await store.insert(Tables.TRANSACTION, tx.toValuesBucket());
      await CategoryService.increaseUseCount(store, tx.categoryId);
      return rowId;
    });
    // 默认值记忆（F-1.1：默认上次使用的账户与分类）
    SettingsService.setLastAccountId(tx.accountId);
    SettingsService.setLastCategoryId(tx.categoryId);
    DataBus.bump();
    LogUtil.d(TransactionService.TAG, 'tx added, id=' + rowId.toString());
    return rowId;
  }

  /** 公共字段校验，确保 Service 被其他入口直接调用时也不会写入脏数据。 */
  private static validateCommon(tx: Transaction): void {
    if (tx.type !== TxType.EXPENSE && tx.type !== TxType.INCOME && tx.type !== TxType.TRANSFER) {
      throw new Error(ErrorMessages.TX_INVALID_TYPE);
    }
    if (!Number.isSafeInteger(tx.amount) || tx.amount <= 0 || tx.amount > AppConstants.MAX_MONEY_FEN) {
      throw new Error(ErrorMessages.TX_AMOUNT_INVALID);
    }
    if (!Number.isSafeInteger(tx.txDate) || tx.txDate <= 0 || DateUtil.isFuture(tx.txDate)) {
      throw new Error(ErrorMessages.TX_DATE_INVALID);
    }
    if (tx.note.length > AppConstants.MAX_NOTE_LENGTH) {
      throw new Error(ErrorMessages.TX_NOTE_TOO_LONG);
    }
  }

  /**
   * 转账：双流水同一事务（架构 6.3 ③）。
   * 生成 A（account_id=转出, to_account_id=转入）与 B（互反）两条 type=2 流水，
   * related_tx_id 互指；任一步异常 rollBack，两条都不落库。
   */
  public static async addTransfer(fromAccountId: number, toAccountId: number,
    amount: number, note: string, txDate: number): Promise<number[]> {
    if (fromAccountId <= 0 || toAccountId <= 0) {
      throw new Error(ErrorMessages.TX_TRANSFER_ACCOUNTS_REQUIRED);
    }
    if (fromAccountId === toAccountId) {
      throw new Error(ErrorMessages.TX_TRANSFER_SAME_ACCOUNT);
    }
    if (!Number.isSafeInteger(amount) || amount <= 0 || amount > AppConstants.MAX_MONEY_FEN) {
      throw new Error(ErrorMessages.TX_AMOUNT_INVALID);
    }
    if (!Number.isSafeInteger(txDate) || txDate <= 0 || DateUtil.isFuture(txDate)) {
      throw new Error(ErrorMessages.TX_DATE_INVALID);
    }
    if (note.length > AppConstants.MAX_NOTE_LENGTH) {
      throw new Error(ErrorMessages.TX_NOTE_TOO_LONG);
    }
    const db: DatabaseManager = DatabaseManager.getInstance();
    const now: number = DateUtil.now();
    const ledgerId: number = SettingsService.getCurrentLedgerId();
    const ids: number[] = await db.runInTransaction<number[]>(async (store: relationalStore.RdbStore) => {
      await TransactionService.requireAccountInLedger(store, fromAccountId, ledgerId);
      await TransactionService.requireAccountInLedger(store, toAccountId, ledgerId);
      // 流水 A：转出方视角
      const txA: Transaction = new Transaction();
      txA.type = TxType.TRANSFER;
      txA.amount = amount;
      txA.accountId = fromAccountId;
      txA.toAccountId = toAccountId;
      txA.categoryId = 0;
      txA.relatedTxId = 0;
      txA.note = note;
      txA.txDate = txDate;
      txA.createdAt = now;
      txA.updatedAt = now;
      txA.ledgerId = ledgerId;
      const idA: number = await store.insert(Tables.TRANSACTION, txA.toValuesBucket());

      // 流水 B：转入方视角，related_tx_id 指向 A
      const txB: Transaction = new Transaction();
      txB.type = TxType.TRANSFER;
      txB.amount = amount;
      txB.accountId = toAccountId;
      txB.toAccountId = fromAccountId;
      txB.categoryId = 0;
      txB.relatedTxId = idA;
      txB.note = note;
      txB.txDate = txDate;
      txB.createdAt = now;
      txB.updatedAt = now;
      txB.ledgerId = ledgerId;
      const idB: number = await store.insert(Tables.TRANSACTION, txB.toValuesBucket());

      // 回填 A 的配对指针，完成互指
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(Tables.TRANSACTION);
      predicates.equalTo('id', idA);
      const patch: relationalStore.ValuesBucket = {
        'related_tx_id': idB,
        'updated_at': now
      };
      await store.update(patch, predicates);
      return [idA, idB];
    });
    DataBus.bump();
    LogUtil.d(TransactionService.TAG, 'transfer added: ' + ids[0].toString() + ' <-> ' + ids[1].toString());
    return ids;
  }

  /** 编辑流水（转账不允许单条编辑，须删后重记，保证配对一致性） */
  public static async update(tx: Transaction): Promise<void> {
    if (tx.id <= 0) {
      throw new Error(ErrorMessages.TX_NOT_FOUND);
    }
    if (tx.isTransfer()) {
      throw new Error(ErrorMessages.TX_TRANSFER_EDIT_BLOCKED);
    }
    TransactionService.validateCommon(tx);
    if (tx.accountId <= 0) {
      throw new Error(ErrorMessages.TX_ACCOUNT_REQUIRED);
    }
    if (tx.categoryId <= 0) {
      throw new Error(ErrorMessages.TX_CATEGORY_REQUIRED);
    }
    tx.updatedAt = DateUtil.now();
    const db: DatabaseManager = DatabaseManager.getInstance();
    const ledgerId: number = SettingsService.getCurrentLedgerId();
    await db.runInTransaction<void>(async (store: relationalStore.RdbStore) => {
      // 先取旧记录：仅当分类发生变化时才回退旧分类计数、累加新分类计数。
      // 无条件 +1 会让「反复编辑同一笔」「换分类」把 use_count 慢慢撑爆，常用置顶失真。
      const old: Transaction | null = await TransactionService.getByIdIn(store, tx.id, ledgerId);
      if (old === null) {
        throw new Error(ErrorMessages.TX_NOT_FOUND);
      }
      // 必须以数据库中的原记录为准。仅检查调用方传入的 type，会允许转账被伪装成收支，
      // 从而留下未同步修改的配对流水。
      if (old.isTransfer()) {
        throw new Error(ErrorMessages.TX_TRANSFER_EDIT_BLOCKED);
      }
      const oldCategoryId: number = old.categoryId;
      // 不允许调用方借由构造 Transaction 改写账本归属、创建时间或转账关联字段。
      tx.ledgerId = old.ledgerId;
      tx.createdAt = old.createdAt;
      tx.relatedTxId = 0;
      tx.toAccountId = 0;
      await TransactionService.requireAccountInLedger(store, tx.accountId, ledgerId);
      await TransactionService.requireCategoryInLedger(store, tx.categoryId, ledgerId, tx.type);
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(Tables.TRANSACTION);
      predicates.equalTo('id', tx.id);
      predicates.equalTo('ledger_id', old.ledgerId);
      await store.update(tx.toValuesBucket(), predicates);
      if (oldCategoryId > 0 && oldCategoryId !== tx.categoryId) {
        await CategoryService.decreaseUseCount(store, oldCategoryId);
      }
      if (tx.categoryId > 0 && tx.categoryId !== oldCategoryId) {
        await CategoryService.increaseUseCount(store, tx.categoryId);
      }
    });
    DataBus.bump();
  }

  /**
   * 删除流水。若为转账：事务内查出配对 id，两条一起删（架构 6.3 删除侧）。
   * 删除图片凭证文件同步清理（v1.1 ImageService.deleteByTx）。
   */
  public static async delete(id: number): Promise<void> {
    const db: DatabaseManager = DatabaseManager.getInstance();
    const ledgerId: number = SettingsService.getCurrentLedgerId();
    await db.runInTransaction<void>(async (store: relationalStore.RdbStore) => {
      const self: Transaction | null = await TransactionService.getByIdIn(store, id, ledgerId);
      if (self === null) {
        return;
      }
      if (self.isTransfer() && self.relatedTxId > 0) {
        const pair: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(Tables.TRANSACTION);
        pair.equalTo('id', self.relatedTxId);
        pair.equalTo('ledger_id', self.ledgerId);
        await store.delete(pair);
      }
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(Tables.TRANSACTION);
      predicates.equalTo('id', id);
      predicates.equalTo('ledger_id', self.ledgerId);
      await store.delete(predicates);
    });
    DataBus.bump();
  }

  /** 按 id 查当前账本内单条；不存在或属于其他账本均返回 null */
  public static async getById(id: number): Promise<Transaction | null> {
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    return await TransactionService.getByIdIn(store, id, SettingsService.getCurrentLedgerId());
  }

  private static async getByIdIn(store: relationalStore.RdbStore, id: number,
    ledgerId: number): Promise<Transaction | null> {
    const resultSet: relationalStore.ResultSet =
      await store.querySql('SELECT * FROM ' + Tables.TRANSACTION + ' WHERE id = ? AND ledger_id = ?',
        [id, ledgerId]);
    let tx: Transaction | null = null;
    try {
      if (resultSet.goToFirstRow()) {
        tx = Transaction.fromRow(resultSet);
      }
    } finally {
      resultSet.close();
    }
    return tx;
  }

  /** 确认账户属于当前账本；所有写入都在同一事务内调用，避免跨账本引用。 */
  private static async requireAccountInLedger(store: relationalStore.RdbStore, accountId: number,
    ledgerId: number): Promise<void> {
    const resultSet: relationalStore.ResultSet = await store.querySql(
      'SELECT COUNT(*) AS cnt FROM ' + Tables.ACCOUNT + ' WHERE id = ? AND ledger_id = ?',
      [accountId, ledgerId]);
    try {
      if (!resultSet.goToFirstRow() || resultSet.getLong(resultSet.getColumnIndex('cnt')) <= 0) {
        throw new Error(ErrorMessages.TX_ACCOUNT_REQUIRED);
      }
    } finally {
      resultSet.close();
    }
  }

  /** 确认分类属于当前账本且与收支类型一致。 */
  private static async requireCategoryInLedger(store: relationalStore.RdbStore, categoryId: number,
    ledgerId: number, txType: number): Promise<void> {
    const categoryType: number = txType === TxType.INCOME ? CategoryType.INCOME : CategoryType.EXPENSE;
    const resultSet: relationalStore.ResultSet = await store.querySql(
      'SELECT COUNT(*) AS cnt FROM ' + Tables.CATEGORY + ' WHERE id = ? AND ledger_id = ? AND type = ?',
      [categoryId, ledgerId, categoryType]);
    try {
      if (!resultSet.goToFirstRow() || resultSet.getLong(resultSet.getColumnIndex('cnt')) <= 0) {
        throw new Error(ErrorMessages.TX_CATEGORY_REQUIRED);
      }
    } finally {
      resultSet.close();
    }
  }

  /** 按月查询（左闭右开月区间，txDate 倒序），走 idx_tx_ledger_date */
  public static async listByMonth(monthKey: string): Promise<Transaction[]> {
    const start: number = DateUtil.monthKeyToStart(monthKey);
    const end: number = DateUtil.endOfMonth(start);
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    const sql: string = 'SELECT * FROM ' + Tables.TRANSACTION +
      ' WHERE ledger_id = ? AND tx_date >= ? AND tx_date < ? ORDER BY tx_date DESC';
    const resultSet: relationalStore.ResultSet = await store.querySql(sql,
      [SettingsService.getCurrentLedgerId(), start, end]);
    return TransactionService.readAll(resultSet);
  }

  /** 多维筛选（F-5.4）：在月区间基础上叠加 keyword/类型/分类/账户/金额条件 */
  public static async listByFilter(monthKey: string, filter: TxFilter): Promise<Transaction[]> {
    const start: number = DateUtil.monthKeyToStart(monthKey);
    const end: number = DateUtil.endOfMonth(start);
    const whereParts: string[] = ['ledger_id = ?', 'tx_date >= ?', 'tx_date < ?'];
    const args: Array<string | number> = [SettingsService.getCurrentLedgerId(), start, end];

    if (filter.keyword.length > 0) {
      // 关键词命中备注 / 分类名 / 账户名（架构 4.7 关键词搜索 SQL）
      const like: string = '%' + filter.keyword + '%';
      whereParts.push('(note LIKE ? OR category_id IN (SELECT id FROM ' + Tables.CATEGORY +
        ' WHERE name LIKE ?) OR account_id IN (SELECT id FROM ' + Tables.ACCOUNT + ' WHERE name LIKE ?))');
      args.push(like, like, like);
    }
    if (filter.types.length > 0) {
      whereParts.push('type IN (' + TransactionService.placeholders(filter.types.length) + ')');
      for (let i = 0; i < filter.types.length; i++) {
        args.push(filter.types[i]);
      }
    }
    if (filter.categoryIds.length > 0) {
      whereParts.push('category_id IN (' + TransactionService.placeholders(filter.categoryIds.length) + ')');
      for (let i = 0; i < filter.categoryIds.length; i++) {
        args.push(filter.categoryIds[i]);
      }
    }
    if (filter.accountIds.length > 0) {
      whereParts.push('(account_id IN (' + TransactionService.placeholders(filter.accountIds.length) + ')' +
        ' OR to_account_id IN (' + TransactionService.placeholders(filter.accountIds.length) + '))');
      for (let i = 0; i < filter.accountIds.length; i++) {
        args.push(filter.accountIds[i]);
      }
      for (let i = 0; i < filter.accountIds.length; i++) {
        args.push(filter.accountIds[i]);
      }
    }
    if (filter.minAmount > 0) {
      whereParts.push('amount >= ?');
      args.push(filter.minAmount);
    }
    if (filter.maxAmount > 0) {
      whereParts.push('amount <= ?');
      args.push(filter.maxAmount);
    }

    const sql: string = 'SELECT * FROM ' + Tables.TRANSACTION + ' WHERE ' +
      whereParts.join(' AND ') + ' ORDER BY tx_date DESC';
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    const resultSet: relationalStore.ResultSet = await store.querySql(sql, args);
    return TransactionService.readAll(resultSet);
  }

  /** 关键词搜索（跨全部月份） */
  public static async search(keyword: string): Promise<Transaction[]> {
    // 搜索不限月份：命中备注 / 分类名 / 账户名，按时间倒序取最近 500 条
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    const like: string = '%' + keyword + '%';
    const sql: string = 'SELECT * FROM ' + Tables.TRANSACTION +
      ' WHERE ledger_id = ? AND (note LIKE ? OR category_id IN (SELECT id FROM ' + Tables.CATEGORY +
      ' WHERE name LIKE ?) OR account_id IN (SELECT id FROM ' + Tables.ACCOUNT + ' WHERE name LIKE ?))' +
      ' ORDER BY tx_date DESC LIMIT 500';
    const resultSet: relationalStore.ResultSet = await store.querySql(sql,
      [SettingsService.getCurrentLedgerId(), like, like, like]);
    return TransactionService.readAll(resultSet);
  }

  /** 最近 n 条（首页最近流水，按 txDate 倒序） */
  public static async getRecent(n: number): Promise<Transaction[]> {
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    const sql: string = 'SELECT * FROM ' + Tables.TRANSACTION +
      ' WHERE ledger_id = ? ORDER BY tx_date DESC LIMIT ?';
    const resultSet: relationalStore.ResultSet = await store.querySql(sql,
      [SettingsService.getCurrentLedgerId(), n]);
    return TransactionService.readAll(resultSet);
  }

  /** 有流水的月份键列表（导出页月份选择，倒序，最多 24 个月） */
  public static async listMonthsWithData(): Promise<string[]> {
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    // 单列扫描 + 内存按月去重，规避 strftime 兼容问题（架构 6.4 同款取舍）
    const sql: string = 'SELECT tx_date FROM ' + Tables.TRANSACTION +
      ' WHERE ledger_id = ? ORDER BY tx_date DESC';
    const resultSet: relationalStore.ResultSet = await store.querySql(sql, [SettingsService.getCurrentLedgerId()]);
    const months: string[] = [];
    try {
      while (resultSet.goToNextRow()) {
        const key: string = DateUtil.monthKey(resultSet.getLong(resultSet.getColumnIndex('tx_date')));
        if (months.indexOf(key) < 0) {
          months.push(key);
          if (months.length >= 24) {
            break;
          }
        }
      }
    } finally {
      resultSet.close();
    }
    return months;
  }

  /** 读出整个游标（统一 close） */
  private static readAll(resultSet: relationalStore.ResultSet): Transaction[] {
    const list: Transaction[] = [];
    try {
      while (resultSet.goToNextRow()) {
        list.push(Transaction.fromRow(resultSet));
      }
    } finally {
      resultSet.close();
    }
    return list;
  }

  /** 生成 n 个 SQL 占位符 */
  private static placeholders(n: number): string {
    if (n <= 0) {
      return '';
    }
    const parts: string[] = [];
    for (let i = 0; i < n; i++) {
      parts.push('?');
    }
    return parts.join(',');
  }
}
