/**
 * 模块职责：分类领域服务（架构 T03）。
 * - 按类型查询（过滤 is_hidden）/ 新增 / 编辑 / 隐藏
 * - increaseUseCount 接收事务内 store，供 TransactionService 同事务调用
 * - 内置分类（is_system=1）不可删除，只能隐藏（CategoryManagePage v1.0 范围）
 */
import { relationalStore } from '@kit.ArkData';
import { DatabaseManager } from './DatabaseManager';
import { DataBus } from './DataBus';
import { Tables } from './SchemaConstants';
import { Category } from '../model/Category';
import { CategoryType } from '../constants/AppConstants';
import { SettingsService } from './SettingsService';
import { DateUtil } from '../utils/DateUtil';
import { ErrorMessages } from '../constants/ErrorMessages';

export class CategoryService {

  /** 按类型查询（默认过滤隐藏分类，记账页分类宫格用） */
  public static async listByType(type: number, includeHidden: boolean = false): Promise<Category[]> {
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(Tables.CATEGORY);
    predicates.equalTo('ledger_id', SettingsService.getCurrentLedgerId());
    predicates.equalTo('type', type);
    if (!includeHidden) {
      predicates.equalTo('is_hidden', 0);
    }
    predicates.orderByAsc('sort_order');
    predicates.orderByAsc('id');
    const resultSet: relationalStore.ResultSet = await store.query(predicates);
    const list: Category[] = [];
    try {
      while (resultSet.goToNextRow()) {
        list.push(Category.fromRow(resultSet));
      }
    } finally {
      resultSet.close();
    }
    return list;
  }

  /** 按 id 查单条；不存在返回 null */
  public static async getById(id: number): Promise<Category | null> {
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    const resultSet: relationalStore.ResultSet =
      await store.querySql('SELECT * FROM ' + Tables.CATEGORY + ' WHERE id = ? AND ledger_id = ?',
        [id, SettingsService.getCurrentLedgerId()]);
    let category: Category | null = null;
    try {
      if (resultSet.goToFirstRow()) {
        category = Category.fromRow(resultSet);
      }
    } finally {
      resultSet.close();
    }
    return category;
  }

  /** 新增自定义分类（v1.1 开放 UI；服务能力先就绪） */
  public static async add(category: Category): Promise<number> {
    if (category.name.trim().length === 0) {
      throw new Error(ErrorMessages.CATEGORY_NAME_EMPTY);
    }
    const now: number = DateUtil.now();
    category.ledgerId = SettingsService.getCurrentLedgerId();
    category.createdAt = now;
    category.updatedAt = now;
    category.isSystem = false;
    const db: DatabaseManager = DatabaseManager.getInstance();
    const rowId: number = await db.runInTransaction<number>(async (store: relationalStore.RdbStore): Promise<number> => {
      return await store.insert(Tables.CATEGORY, category.toValuesBucket());
    });
    DataBus.bump();
    return rowId;
  }

  /** 编辑分类（名称/图标/颜色/排序） */
  public static async update(category: Category): Promise<void> {
    if (category.id <= 0) {
      throw new Error(ErrorMessages.CATEGORY_NOT_FOUND);
    }
    if (category.name.trim().length === 0) {
      throw new Error(ErrorMessages.CATEGORY_NAME_EMPTY);
    }
    const ledgerId: number = SettingsService.getCurrentLedgerId();
    category.ledgerId = ledgerId;
    category.updatedAt = DateUtil.now();
    const db: DatabaseManager = DatabaseManager.getInstance();
    await db.runInTransaction<void>(async (store: relationalStore.RdbStore): Promise<void> => {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(Tables.CATEGORY);
      predicates.equalTo('id', category.id);
      predicates.equalTo('ledger_id', ledgerId);
      const changed: number = await store.update(category.toValuesBucket(), predicates);
      if (changed <= 0) {
        throw new Error(ErrorMessages.CATEGORY_NOT_FOUND);
      }
    });
    DataBus.bump();
  }

  /** 隐藏 / 显示分类（内置分类可隐藏不可删除） */
  public static async hide(id: number, hidden: boolean): Promise<void> {
    const ledgerId: number = SettingsService.getCurrentLedgerId();
    const db: DatabaseManager = DatabaseManager.getInstance();
    await db.runInTransaction<void>(async (store: relationalStore.RdbStore): Promise<void> => {
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(Tables.CATEGORY);
      predicates.equalTo('id', id);
      predicates.equalTo('ledger_id', ledgerId);
      const patch: relationalStore.ValuesBucket = {
        'is_hidden': hidden ? 1 : 0,
        'updated_at': DateUtil.now()
      };
      const changed: number = await store.update(patch, predicates);
      if (changed <= 0) {
        throw new Error(ErrorMessages.CATEGORY_NOT_FOUND);
      }
    });
    DataBus.bump();
  }

  /**
   * 使用频次 +1（常用置顶依据，v1.2 启用）。
   * ⚠️ 接收调用方事务内的 store：与流水 insert 同事务，保证原子性。
   */
  public static async increaseUseCount(store: relationalStore.RdbStore, categoryId: number): Promise<void> {
    if (categoryId <= 0) {
      return;
    }
    await store.executeSql(
      'UPDATE ' + Tables.CATEGORY + ' SET use_count = use_count + 1 WHERE id = ? AND ledger_id = ?',
      [categoryId, SettingsService.getCurrentLedgerId()]);
  }

  /**
   * 使用频次 -1（编辑流水换走原分类时回退，防止 use_count 虚高）。
   * ⚠️ 与 increaseUseCount 同约定：接收调用方事务内的 store；不会减成负数。
   */
  public static async decreaseUseCount(store: relationalStore.RdbStore, categoryId: number): Promise<void> {
    if (categoryId <= 0) {
      return;
    }
    await store.executeSql(
      'UPDATE ' + Tables.CATEGORY + ' SET use_count = use_count - 1 WHERE id = ? AND ledger_id = ? AND use_count > 0',
      [categoryId, SettingsService.getCurrentLedgerId()]);
  }

  /** 全部分类数量（我的页汇总展示） */
  public static async countAll(): Promise<number> {
    const store: relationalStore.RdbStore = DatabaseManager.getInstance().getStore();
    const resultSet: relationalStore.ResultSet = await store.querySql(
      'SELECT COUNT(*) AS cnt FROM ' + Tables.CATEGORY +
      ' WHERE ledger_id = ? AND is_hidden = 0', [SettingsService.getCurrentLedgerId()]);
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

  /** 分类名 → id 映射（导出 CSV 与搜索场景使用） */
  public static async loadNameMap(): Promise<Map<number, Category>> {
    const list: Category[] = await CategoryService.listByType(CategoryType.EXPENSE, true);
    const incomeList: Category[] = await CategoryService.listByType(CategoryType.INCOME, true);
    const map: Map<number, Category> = new Map();
    for (let i = 0; i < list.length; i++) {
      map.set(list[i].id, list[i]);
    }
    for (let i = 0; i < incomeList.length; i++) {
      map.set(incomeList[i].id, incomeList[i]);
    }
    return map;
  }
}
