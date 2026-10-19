/**
 * 模块职责：账本实体（架构 4.3 / 4.2 ll_ledger）。
 * 纯数据类：列 ↔ 字段转换只发生在本文件的 fromRow / toValuesBucket 中（架构 9.1）。
 * v1.0 仅 id=1「个人账本」，UI 不开放切换（架构 D5）。
 */
import { relationalStore } from '@kit.ArkData';

export class Ledger {
  public id: number = 0;
  public name: string = '';
  public icon: string = 'book';
  public color: string = '#5B67F5';
  public currency: string = 'CNY';
  public isDefault: boolean = false;
  public sortOrder: number = 0;
  public createdAt: number = 0;
  public updatedAt: number = 0;

  /** ResultSet 当前行 → 实体。调用方负责遍历游标并在结束后 close()。 */
  public static fromRow(row: relationalStore.ResultSet): Ledger {
    const entity: Ledger = new Ledger();
    entity.id = row.getLong(row.getColumnIndex('id'));
    entity.name = row.getString(row.getColumnIndex('name'));
    entity.icon = row.getString(row.getColumnIndex('icon'));
    entity.color = row.getString(row.getColumnIndex('color'));
    entity.currency = row.getString(row.getColumnIndex('currency'));
    entity.isDefault = row.getLong(row.getColumnIndex('is_default')) === 1;
    entity.sortOrder = row.getLong(row.getColumnIndex('sort_order'));
    entity.createdAt = row.getLong(row.getColumnIndex('created_at'));
    entity.updatedAt = row.getLong(row.getColumnIndex('updated_at'));
    return entity;
  }

  /** 实体 → 插入/更新用值桶（不含 id，插入时自增） */
  public toValuesBucket(): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      'name': this.name,
      'icon': this.icon,
      'color': this.color,
      'currency': this.currency,
      'is_default': this.isDefault ? 1 : 0,
      'sort_order': this.sortOrder,
      'created_at': this.createdAt,
      'updated_at': this.updatedAt
    };
    return bucket;
  }
}
