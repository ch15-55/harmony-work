/**
 * 模块职责：流水展示 DTO 映射器（架构 T03/T04 桥接件）。
 * 把 Transaction（只含 categoryId/accountId）批量关联为 TxDisplayItem
 * （分类名/图标/色 + 账户名），供首页「最近记录」与明细页列表消费。
 *
 * 设计要点：
 * - 只发 2 次查询（分类名映射 + 账户列表），与流水条数无关，避免 N+1；
 * - 分类缺失（用户删除后遗留流水）兜底「其他」样式，不抛异常；
 * - 转账条目 accountName 组合为「A → B」，categorName 置空。
 */
import { Transaction } from '../model/Transaction';
import { TxDisplayItem } from '../model/StatsModels';
import { TxType } from '../constants/AppConstants';
import { CategoryService } from '../service/CategoryService';
import { AccountService } from '../service/AccountService';
import { Category } from '../model/Category';
import { Account } from '../model/Account';

export class TxDisplayMapper {

  /** 批量关联（顺序与输入保持一致） */
  public static async resolve(items: Transaction[]): Promise<TxDisplayItem[]> {
    const result: TxDisplayItem[] = [];
    if (items.length === 0) {
      return result;
    }
    // 两次全量加载：预置+自定义分类/账户总量在百级，内存映射换取零 N+1
    const categoryMap: Map<number, Category> = await CategoryService.loadNameMap();
    const accounts: Account[] = await AccountService.listAll(true);
    const accountMap: Map<number, Account> = new Map<number, Account>();
    for (let i = 0; i < accounts.length; i++) {
      accountMap.set(accounts[i].id, accounts[i]);
    }

    for (let i = 0; i < items.length; i++) {
      result.push(TxDisplayMapper.mapOne(items[i], categoryMap, accountMap));
    }
    return result;
  }

  /** 单条映射（纯函数，便于单测） */
  private static mapOne(tx: Transaction,
    categoryMap: Map<number, Category>, accountMap: Map<number, Account>): TxDisplayItem {
    const item: TxDisplayItem = new TxDisplayItem();
    item.tx = tx;

    if (tx.type === TxType.TRANSFER) {
      // 转账：无分类语义，账户名组合「A → B」
      const fromAcc: Account | undefined = accountMap.get(tx.accountId);
      const toAcc: Account | undefined = accountMap.get(tx.toAccountId);
      const fromName: string = fromAcc === undefined ? '' : fromAcc.name;
      const toName: string = toAcc === undefined ? '' : toAcc.name;
      item.accountName = fromName + ' → ' + toName;
      return item;
    }

    const category: Category | undefined = categoryMap.get(tx.categoryId);
    if (category !== undefined) {
      item.categoryName = category.name;
      item.categoryIcon = category.icon;
      item.categoryColor = category.color;
    }
    const account: Account | undefined = accountMap.get(tx.accountId);
    if (account !== undefined) {
      item.accountName = account.name;
    }
    return item;
  }
}
