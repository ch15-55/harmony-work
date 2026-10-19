/**
 * 模块职责：全部页面路由路径常量（架构 9.4）。
 * 铁律：页面内禁止硬编码路由字符串；本文件与
 * entry/src/main/resources/base/profile/main_pages.json 必须严格同步，
 * 漏登一个条目即运行时「页面不存在」。
 */
export class RouteConstants {
  /** 首次启动隐私弹窗页（独立路由，视觉伪装弹窗） */
  static readonly PRIVACY: string = 'pages/PrivacyPage';
  /** Tabs 主容器 */
  static readonly INDEX: string = 'pages/Index';

  /** Tab 内页（v1.0 由 Index 以组件形式内嵌，同时登记在 main_pages.json 以便深链兜底） */
  static readonly HOME: string = 'pages/HomePage';
  static readonly RECORDS: string = 'pages/RecordsPage';
  static readonly PLACEHOLDER: string = 'pages/PlaceholderPage';
  static readonly STATISTICS: string = 'pages/StatisticsPage';
  static readonly MINE: string = 'pages/MinePage';

  /** 记账 / 编辑（全屏拉起） */
  static readonly RECORD_EDIT: string = 'pages/RecordEditPage';
  /** 流水详情 */
  static readonly TX_DETAIL: string = 'pages/TransactionDetailPage';
  /** 环形图下钻：某分类流水列表 */
  static readonly CATEGORY_TX_LIST: string = 'pages/CategoryTxListPage';

  /** 账本管理 / 账户管理 / 编辑 */
  static readonly LEDGER_MANAGE: string = 'pages/LedgerManagePage';
  static readonly ACCOUNT_MANAGE: string = 'pages/AccountManagePage';
  static readonly ACCOUNT_EDIT: string = 'pages/AccountEditPage';
  /** 分类管理 */
  static readonly CATEGORY_MANAGE: string = 'pages/CategoryManagePage';
  /** 预算设置 */
  static readonly BUDGET_SETTING: string = 'pages/BudgetSettingPage';
  /** 导出数据 */
  static readonly EXPORT: string = 'pages/ExportPage';
  /** 备份与恢复（v1.1 F-10.5/F-10.6） */
  static readonly BACKUP: string = 'pages/BackupPage';
  /** 仅技术运行信息的本地诊断导出 */
  static readonly DIAGNOSTICS: string = 'pages/DiagnosticsPage';
  /** 主题与货币 */
  static readonly THEME_SETTING: string = 'pages/ThemeSettingPage';
  /** 应用锁设置 / PIN 校验 */
  static readonly APPLOCK_SETTING: string = 'pages/AppLockSettingPage';
  static readonly PIN_VERIFY: string = 'pages/PinVerifyPage';
  /** 关于类 */
  static readonly ABOUT: string = 'pages/AboutPage';
  static readonly PRIVACY_POLICY: string = 'pages/PrivacyPolicyPage';
  static readonly USER_AGREEMENT: string = 'pages/UserAgreementPage';
}
