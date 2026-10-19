/**
 * 模块职责：账户实体（架构 4.3 / 4.2 ll_account）。
 * 注意：余额不冗余存储，由 AccountService 用 4 子查询实时计算（架构 4.7）。
 */
import { relationalStore } from '@kit.ArkData';
import { AccountType } from '../constants/AppConstants';

export class Account {
  public id: number = 0;
  public ledgerId: number = 1;
  public name: string = '';
  public type: number = AccountType.CASH;
  public icon: string = 'wallet';
  public color: string = '#5B67F5';
  /** 期初余额（分），可为负 */
  public initialBalance: number = 0;
  /** 信用额度（分），仅信用卡用，v1.0 预留 */
  public creditLimit: number = 0;
  /** 1=已归档，不计入总资产 */
  public isArchived: boolean = false;
  public sortOrder: number = 0;
  public createdAt: number = 0;
  public updatedAt: number = 0;

  public static fromRow(row: relationalStore.ResultSet): Account {
    const entity: Account = new Account();
    entity.id = row.getLong(row.getColumnIndex('id'));
    entity.ledgerId = row.getLong(row.getColumnIndex('ledger_id'));
    entity.name = row.getString(row.getColumnIndex('name'));
    entity.type = row.getLong(row.getColumnIndex('type'));
    entity.icon = row.getString(row.getColumnIndex('icon'));
    entity.color = row.getString(row.getColumnIndex('color'));
    entity.initialBalance = row.getLong(row.getColumnIndex('initial_balance'));
    entity.creditLimit = row.getLong(row.getColumnIndex('credit_limit'));
    entity.isArchived = row.getLong(row.getColumnIndex('is_archived')) === 1;
    entity.sortOrder = row.getLong(row.getColumnIndex('sort_order'));
    entity.createdAt = row.getLong(row.getColumnIndex('created_at'));
    entity.updatedAt = row.getLong(row.getColumnIndex('updated_at'));
    return entity;
  }

  public toValuesBucket(): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      'ledger_id': this.ledgerId,
      'name': this.name,
      'type': this.type,
      'icon': this.icon,
      'color': this.color,
      'initial_balance': this.initialBalance,
      'credit_limit': this.creditLimit,
      'is_archived': this.isArchived ? 1 : 0,
      'sort_order': this.sortOrder,
      'created_at': this.createdAt,
      'updated_at': this.updatedAt
    };
    return bucket;
  }

  /** 是否信用卡（首页可用额度展示预留） */
  public isCredit(): boolean {
    return this.type === AccountType.CREDIT;
  }
}
