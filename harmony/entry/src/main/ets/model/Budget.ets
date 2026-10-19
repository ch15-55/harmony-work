/**
 * 模块职责：预算实体（架构 4.3 / 4.2 ll_budget）。
 * (ledger_id, month) 唯一索引支撑 UPSERT 语义。
 * 分类预算项（ll_budget_item）v1.0 建表预留，v1.1 启用 UI。
 */
import { relationalStore } from '@kit.ArkData';

export class Budget {
  public id: number = 0;
  public ledgerId: number = 1;
  /** 'yyyy-MM' */
  public month: string = '';
  /** 月度总预算（分） */
  public totalAmount: number = 0;
  /** 结转开关，v1.0 预留 */
  public carryOver: number = 0;
  public createdAt: number = 0;
  public updatedAt: number = 0;

  public static fromRow(row: relationalStore.ResultSet): Budget {
    const entity: Budget = new Budget();
    entity.id = row.getLong(row.getColumnIndex('id'));
    entity.ledgerId = row.getLong(row.getColumnIndex('ledger_id'));
    entity.month = row.getString(row.getColumnIndex('month'));
    entity.totalAmount = row.getLong(row.getColumnIndex('total_amount'));
    entity.carryOver = row.getLong(row.getColumnIndex('carry_over'));
    entity.createdAt = row.getLong(row.getColumnIndex('created_at'));
    entity.updatedAt = row.getLong(row.getColumnIndex('updated_at'));
    return entity;
  }

  public toValuesBucket(): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      'ledger_id': this.ledgerId,
      'month': this.month,
      'total_amount': this.totalAmount,
      'carry_over': this.carryOver,
      'created_at': this.createdAt,
      'updated_at': this.updatedAt
    };
    return bucket;
  }
}

/** 分类预算项实体（v1.0 建表预留，v1.1 启用） */
export class BudgetItem {
  public id: number = 0;
  public budgetId: number = 0;
  public categoryId: number = 0;
  public amount: number = 0;

  public static fromRow(row: relationalStore.ResultSet): BudgetItem {
    const entity: BudgetItem = new BudgetItem();
    entity.id = row.getLong(row.getColumnIndex('id'));
    entity.budgetId = row.getLong(row.getColumnIndex('budget_id'));
    entity.categoryId = row.getLong(row.getColumnIndex('category_id'));
    entity.amount = row.getLong(row.getColumnIndex('amount'));
    return entity;
  }

  public toValuesBucket(): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      'budget_id': this.budgetId,
      'category_id': this.categoryId,
      'amount': this.amount
    };
    return bucket;
  }
}
