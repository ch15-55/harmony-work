/**
 * 模块职责：分类实体（架构 4.3 / 4.2 ll_category）。
 * parentId 恒为 0（二级分类 v1.1 启用，表结构已预留）。
 */
import { relationalStore } from '@kit.ArkData';
import { CategoryType } from '../constants/AppConstants';

export class Category {
  public id: number = 0;
  public ledgerId: number = 1;
  public name: string = '';
  public type: number = CategoryType.EXPENSE;
  /** 0=一级；v1.0 恒为 0 */
  public parentId: number = 0;
  public icon: string = 'more';
  public color: string = '#F5544B';
  public sortOrder: number = 0;
  /** 1=内置预置（不可删除，但可隐藏） */
  public isSystem: boolean = false;
  public isHidden: boolean = false;
  /** 使用频次，用于常用置顶（v1.2） */
  public useCount: number = 0;
  public createdAt: number = 0;
  public updatedAt: number = 0;

  public static fromRow(row: relationalStore.ResultSet): Category {
    const entity: Category = new Category();
    entity.id = row.getLong(row.getColumnIndex('id'));
    entity.ledgerId = row.getLong(row.getColumnIndex('ledger_id'));
    entity.name = row.getString(row.getColumnIndex('name'));
    entity.type = row.getLong(row.getColumnIndex('type'));
    entity.parentId = row.getLong(row.getColumnIndex('parent_id'));
    entity.icon = row.getString(row.getColumnIndex('icon'));
    entity.color = row.getString(row.getColumnIndex('color'));
    entity.sortOrder = row.getLong(row.getColumnIndex('sort_order'));
    entity.isSystem = row.getLong(row.getColumnIndex('is_system')) === 1;
    entity.isHidden = row.getLong(row.getColumnIndex('is_hidden')) === 1;
    entity.useCount = row.getLong(row.getColumnIndex('use_count'));
    entity.createdAt = row.getLong(row.getColumnIndex('created_at'));
    entity.updatedAt = row.getLong(row.getColumnIndex('updated_at'));
    return entity;
  }

  public toValuesBucket(): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      'ledger_id': this.ledgerId,
      'name': this.name,
      'type': this.type,
      'parent_id': this.parentId,
      'icon': this.icon,
      'color': this.color,
      'sort_order': this.sortOrder,
      'is_system': this.isSystem ? 1 : 0,
      'is_hidden': this.isHidden ? 1 : 0,
      'use_count': this.useCount,
      'created_at': this.createdAt,
      'updated_at': this.updatedAt
    };
    return bucket;
  }
}
