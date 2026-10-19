/**
 * 模块职责：账户类型预置（架构 4.6 账户类型 6 类，F-2.1）。
 * 由 AccountEditPage（T05）提供新建账户时的默认色与默认图标，
 * 以及 AccountService 展示账户列表时补充缺省视觉。
 * 本文件只允许数据，禁止任何逻辑。
 */

/** 账户类型预置条目结构 */
export interface AccountPreset {
  /** 对应 ll_account.type（AccountType 枚举值） */
  type: number;
  /** 类型默认名 */
  name: string;
  /** 类型默认色 */
  color: string;
  /** 图标标识 */
  icon: string;
}

/** 账户类型 6 类预置 */
export const ACCOUNT_PRESETS: AccountPreset[] = [
  { type: 0, name: '现金', color: '#12B76A', icon: 'ic_acc_cash' },
  { type: 1, name: '借记卡', color: '#5B67F5', icon: 'ic_acc_debit' },
  { type: 2, name: '信用卡', color: '#F5544B', icon: 'ic_acc_credit' },
  { type: 3, name: '支付宝', color: '#1677FF', icon: 'ic_acc_alipay' },
  { type: 4, name: '微信', color: '#07C160', icon: 'ic_acc_wechat' },
  { type: 5, name: '其他', color: '#8A8F9E', icon: 'ic_acc_other' }
];

/** 新建账户的默认期初余额（分）：恒为 0，避免误带入余额 */
export const DEFAULT_INITIAL_BALANCE_FEN: number = 0;
