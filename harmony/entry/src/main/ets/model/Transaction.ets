/**
 * 模块职责：流水实体（架构 4.3 / 4.2 ll_transaction，核心表）。
 * 铁律：
 * - amount 恒为正整数分，方向由 type 决定
 * - tx_date 为业务发生时间的 UTC 毫秒戳
 * - 转账为同表两条互指流水：type=2、related_tx_id 互相指向对方（架构 6.3），
 *   不建独立转账表
 * - image_paths 列存 JSON 字符串数组，与 imagePaths 字段在本文件内互转
 */
import { relationalStore } from '@kit.ArkData';
import { TxType } from '../constants/AppConstants';

export class Transaction {
  public id: number = 0;
  public ledgerId: number = 1;
  public type: number = TxType.EXPENSE;
  /** 正整数，单位分 */
  public amount: number = 0;
  /** 支出/收入为记账账户；转账时为「转出账户」 */
  public accountId: number = 0;
  /** 转账时为「转入账户」；非转账为 0 */
  public toAccountId: number = 0;
  /** 转账为 0 */
  public categoryId: number = 0;
  /** 配对流水 id；非转账为 0 */
  public relatedTxId: number = 0;
  public note: string = '';
  /** 沙箱图片路径数组（v1.1 启用，v1.0 恒为空数组） */
  public imagePaths: string[] = [];
  /** 业务发生时间，UTC 毫秒 */
  public txDate: number = 0;
  public createdAt: number = 0;
  public updatedAt: number = 0;

  public static fromRow(row: relationalStore.ResultSet): Transaction {
    const entity: Transaction = new Transaction();
    entity.id = row.getLong(row.getColumnIndex('id'));
    entity.ledgerId = row.getLong(row.getColumnIndex('ledger_id'));
    entity.type = row.getLong(row.getColumnIndex('type'));
    entity.amount = row.getLong(row.getColumnIndex('amount'));
    entity.accountId = row.getLong(row.getColumnIndex('account_id'));
    entity.toAccountId = row.getLong(row.getColumnIndex('to_account_id'));
    entity.categoryId = row.getLong(row.getColumnIndex('category_id'));
    entity.relatedTxId = row.getLong(row.getColumnIndex('related_tx_id'));
    entity.note = row.getString(row.getColumnIndex('note'));
    entity.imagePaths = Transaction.jsonToPaths(row.getString(row.getColumnIndex('image_paths')));
    entity.txDate = row.getLong(row.getColumnIndex('tx_date'));
    entity.createdAt = row.getLong(row.getColumnIndex('created_at'));
    entity.updatedAt = row.getLong(row.getColumnIndex('updated_at'));
    return entity;
  }

  public toValuesBucket(): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      'ledger_id': this.ledgerId,
      'type': this.type,
      'amount': this.amount,
      'account_id': this.accountId,
      'to_account_id': this.toAccountId,
      'category_id': this.categoryId,
      'related_tx_id': this.relatedTxId,
      'note': this.note,
      'image_paths': Transaction.pathsToJson(this.imagePaths),
      'tx_date': this.txDate,
      'created_at': this.createdAt,
      'updated_at': this.updatedAt
    };
    return bucket;
  }

  /** 是否转账流水 */
  public isTransfer(): boolean {
    return this.type === TxType.TRANSFER;
  }

  /** image_paths 列（JSON 串）→ 数组；空串或解析失败返回空数组 */
  public static jsonToPaths(json: string): string[] {
    if (json === null || json === undefined || json.length === 0) {
      return [];
    }
    try {
      const parsed: object = JSON.parse(json) as object;
      const list: string[] = [];
      const arr: Array<string> = parsed as Array<string>;
      if (arr === null || arr === undefined) {
        return [];
      }
      for (let i = 0; i < arr.length; i++) {
        list.push(arr[i]);
      }
      return list;
    } catch (e) {
      // 脏数据兜底：不中断列表加载
      return [];
    }
  }

  /** 数组 → image_paths 列（JSON 串）；空数组存空串，节省存储 */
  public static pathsToJson(paths: string[]): string {
    if (paths === null || paths === undefined || paths.length === 0) {
      return '';
    }
    return JSON.stringify(paths);
  }
}
