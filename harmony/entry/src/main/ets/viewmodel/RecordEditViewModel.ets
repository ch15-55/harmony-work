/**
 * 模块职责：记账页 ViewModel（架构 T03 / 6.2 时序 ②）。
 * - load：分类宫格（按类型）+ 账户列表 + 上次账户/分类 + 默认今天
 * - validate：金额（分）> 0、账户已选、转账双方不同且非空
 * - save：add / addTransfer / update 三分支；成功后由 Service 内部 bump
 * 页面持 @State 接收本类返回的数据包；本类不持有 UI 状态。
 */
import { Account } from '../model/Account';
import { AccountBalance } from '../model/StatsModels';
import { Category } from '../model/Category';
import { Transaction } from '../model/Transaction';
import { AppConstants, CategoryType, Result, TxType } from '../constants/AppConstants';
import { ErrorMessages } from '../constants/ErrorMessages';
import { CategoryService } from '../service/CategoryService';
import { AccountService } from '../service/AccountService';
import { TransactionService } from '../service/TransactionService';
import { SettingsService } from '../service/SettingsService';
import { ExpressionEvaluator } from '../utils/ExpressionEvaluator';
import { MoneyUtil } from '../utils/MoneyUtil';
import { DateUtil } from '../utils/DateUtil';

/** 记账页加载与编辑数据包 */
export class RecordEditData {
  public txId: number = 0;
  /** 当前类型（TxType） */
  public type: number = TxType.EXPENSE;
  /** 当前类型下的可见分类 */
  public categories: Category[] = [];
  public selectedCategoryId: number = 0;
  public accounts: Account[] = [];
  /** 支出/收入记账账户；转账时为「从账户」 */
  public selectedAccountId: number = 0;
  /** 转账「到账户」 */
  public toAccountId: number = 0;
  /** 业务发生时间（默认今天） */
  public txDate: number = 0;
  /** 键盘表达式（原始串，页面实时展示） */
  public expression: string = '';
  /** 表达式求值结果（分；0 表示未完成输入） */
  public amountFen: number = 0;
  /**
   * 编辑态：库中原始基础货币分（新增模式为 0）。
   * 非 ¥ 币种时 displayFen → baseFen 往返不守恒（例：rate=6.5，100分→15分→98分），
   * 仅凭换算回写会让「打开编辑页再保存」静默改金额，故保留原始值用于比对。
   */
  public editBaseFen: number = 0;
  /** 编辑态：由原始金额回填的展示币表达式（用于判断用户是否真的改过金额） */
  public baseExpr: string = '';
  public note: string = '';
  public currency: string = AppConstants.DEFAULT_CURRENCY;
  /** 账户实时余额映射（账户选择器展示余额用，避免页面直接触达 Service） */
  public balances: Map<number, AccountBalance> = new Map();

  /** 克隆自身（浅拷贝引用字段），用于触发 @State 引用变化重渲染 */
  public clone(): RecordEditData {
    const copy: RecordEditData = new RecordEditData();
    copy.txId = this.txId;
    copy.type = this.type;
    copy.categories = this.categories;
    copy.selectedCategoryId = this.selectedCategoryId;
    copy.accounts = this.accounts;
    copy.selectedAccountId = this.selectedAccountId;
    copy.toAccountId = this.toAccountId;
    copy.txDate = this.txDate;
    copy.expression = this.expression;
    copy.amountFen = this.amountFen;
    copy.editBaseFen = this.editBaseFen;
    copy.baseExpr = this.baseExpr;
    copy.note = this.note;
    copy.currency = this.currency;
    copy.balances = this.balances;
    return copy;
  }
}

export class RecordEditViewModel {

  /** 加载：新增模式载入分类/账户/默认值；编辑模式载入既有流水 */
  public static async load(txId: number, initialType: number): Promise<RecordEditData> {
    const data: RecordEditData = new RecordEditData();
    data.txDate = DateUtil.startOfDay(DateUtil.now());
    data.type = initialType;
    data.currency = SettingsService.getCurrency();
    if (txId > 0) {
      await RecordEditViewModel.loadForEdit(data, txId);
    } else {
      // 默认上次使用的账户与分类（F-1.1）
      data.selectedAccountId = SettingsService.getLastAccountId();
      data.selectedCategoryId = SettingsService.getLastCategoryId();
    }
    // 编辑流水会覆写 type；在字段回填后统一加载一次，避免重复查询分类、账户及余额。
    await RecordEditViewModel.loadLists(data);
    if (txId <= 0) {
      RecordEditViewModel.normalizeSelection(data);
    }
    return data;
  }

  /** 切换支出/收入类型：重载分类列表并纠正默认选中 */
  public static async switchType(data: RecordEditData, type: number): Promise<void> {
    data.type = type;
    // 收支切换只影响分类；账户与余额在本页停留期间没有发生写入。
    await RecordEditViewModel.loadCategories(data);
    RecordEditViewModel.normalizeSelection(data);
  }

  /** 分类/账户列表装载 */
  private static async loadLists(data: RecordEditData): Promise<void> {
    await RecordEditViewModel.loadCategories(data);
    data.accounts = await AccountService.listAll(false);
    // 账户余额一次性取全量映射（账户数量在十级），账户选择器直接消费
    data.balances = await AccountService.getAllBalances();
  }

  /** 仅按当前收支类型加载可选分类。 */
  private static async loadCategories(data: RecordEditData): Promise<void> {
    const categoryType: number = data.type === TxType.INCOME ?
      CategoryType.INCOME : CategoryType.EXPENSE;
    data.categories = await CategoryService.listByType(categoryType, false);
  }

  /** 纠正选中项：上次选择已失效时回落到首项 */
  private static normalizeSelection(data: RecordEditData): void {
    let found: boolean = false;
    for (let i = 0; i < data.categories.length; i++) {
      if (data.categories[i].id === data.selectedCategoryId) {
        found = true;
        break;
      }
    }
    if (!found && data.categories.length > 0) {
      data.selectedCategoryId = data.categories[0].id;
    } else if (!found) {
      data.selectedCategoryId = 0;
    }
    let accountFound: boolean = false;
    for (let i = 0; i < data.accounts.length; i++) {
      if (data.accounts[i].id === data.selectedAccountId) {
        accountFound = true;
        break;
      }
    }
    if (!accountFound && data.accounts.length > 0) {
      data.selectedAccountId = data.accounts[0].id;
    } else if (!accountFound) {
      data.selectedAccountId = 0;
    }
  }

  /** 编辑模式：载入既有流水（转账不允许单条编辑，Service 层会拦截） */
  private static async loadForEdit(data: RecordEditData, txId: number): Promise<void> {
    const tx: Transaction | null = await TransactionService.getById(txId);
    if (tx === null) {
      throw new Error(ErrorMessages.TX_NOT_FOUND_OR_DELETED);
    }
    // 路由参数可能被外部入口直接构造，不能只依赖列表和详情页隐藏编辑按钮。
    if (tx.isTransfer()) {
      throw new Error(ErrorMessages.TX_TRANSFER_EDIT_BLOCKED);
    }
    data.txId = tx.id;
    data.type = tx.type;
    data.txDate = tx.txDate;
    data.note = tx.note;
    data.selectedAccountId = tx.accountId;
    data.toAccountId = tx.toAccountId;
    data.selectedCategoryId = tx.categoryId;
    data.amountFen = tx.amount;
    // 编辑态表达式显示展示币种金额（库中基础货币换算回输入币），保存时再换回
    data.expression = MoneyUtil.fenToYuan(MoneyUtil.baseFenToDisplayFen(tx.amount)).toString();
    // 记录回填基准：表达式未变时直接沿用库中原始金额，规避汇率往返舍入漂移
    data.baseExpr = data.expression;
    data.editBaseFen = tx.amount;
  }

  /**
   * 由键盘表达式解析入库金额（基础货币分）。
   * 编辑态且表达式与回填值完全一致时，直接返回库中原始金额：
   * 非整数汇率下 baseFen → displayFen → baseFen 不守恒，
   * 盲目换算会让「打开编辑页、什么都没改、点保存」把金额改掉。
   */
  public static resolveAmountFen(data: RecordEditData, expr: string): number {
    if (data.editBaseFen > 0 && expr.length > 0 && expr === data.baseExpr) {
      return data.editBaseFen;
    }
    return MoneyUtil.displayFenToBaseFen(
      MoneyUtil.yuanToFen(ExpressionEvaluator.evaluate(expr)));
  }

  /** 键盘输入：追加 token 并重算金额（展示币换算为基础货币分） */
  public static appendExpression(data: RecordEditData, token: string): void {
    data.expression = ExpressionEvaluator.appendToken(data.expression, token);
    data.amountFen = MoneyUtil.displayFenToBaseFen(
      MoneyUtil.yuanToFen(ExpressionEvaluator.evaluate(data.expression)));
  }

  /** 退格 */
  public static backspaceExpression(data: RecordEditData): void {
    data.expression = ExpressionEvaluator.backspace(data.expression);
    data.amountFen = MoneyUtil.displayFenToBaseFen(
      MoneyUtil.yuanToFen(ExpressionEvaluator.evaluate(data.expression)));
  }

  /** 清空表达式 */
  public static clearExpression(data: RecordEditData): void {
    data.expression = '';
    data.amountFen = 0;
  }

  /**
   * 保存前校验；通过返回空串，否则返回可直接 Toast 的提示文案。
   * 金额校验用 MoneyUtil.isRecordableAmount（正整数分，单一判定点）。
   */
  public static validate(data: RecordEditData): string {
    if (data.accounts.length === 0) {
      return ErrorMessages.TX_NO_ACCOUNT;
    }
    if (!MoneyUtil.isRecordableAmount(data.amountFen)) {
      return ErrorMessages.TX_AMOUNT_INVALID;
    }
    if (data.type === TxType.TRANSFER) {
      if (data.selectedAccountId <= 0 || data.toAccountId <= 0) {
        return ErrorMessages.TX_TRANSFER_ACCOUNTS_REQUIRED;
      }
      if (data.selectedAccountId === data.toAccountId) {
        return ErrorMessages.TX_TRANSFER_SAME_ACCOUNT;
      }
      return '';
    }
    if (data.selectedAccountId <= 0) {
      return ErrorMessages.TX_ACCOUNT_REQUIRED;
    }
    if (data.selectedCategoryId <= 0) {
      return ErrorMessages.TX_CATEGORY_REQUIRED;
    }
    return '';
  }

  /** 保存：add / addTransfer / update 三分支（架构 6.2 ⑥校验通过侧） */
  public static async save(data: RecordEditData): Promise<Result<number[]>> {
    const invalidReason: string = RecordEditViewModel.validate(data);
    if (invalidReason.length > 0) {
      const failed: Result<number[]> = { ok: false, message: invalidReason };
      return failed;
    }
    if (DateUtil.isFuture(data.txDate)) {
      // 记账不可选未来（F-1.10）；时钟被人为回调时兜底拦一道
      const futureBlocked: Result<number[]> = { ok: false, message: ErrorMessages.TX_FUTURE_DATE };
      return futureBlocked;
    }
    try {
      if (data.txId > 0) {
        const tx: Transaction | null = await TransactionService.getById(data.txId);
        if (tx === null) {
          const missing: Result<number[]> = { ok: false, message: ErrorMessages.TX_NOT_FOUND_OR_DELETED };
          return missing;
        }
        tx.type = data.type;
        tx.amount = data.amountFen;
        tx.accountId = data.selectedAccountId;
        tx.categoryId = data.type === TxType.TRANSFER ? 0 : data.selectedCategoryId;
        tx.note = data.note;
        tx.txDate = data.txDate;
        await TransactionService.update(tx);
        const updated: Result<number[]> = { ok: true, data: [data.txId] };
        return updated;
      }
      if (data.type === TxType.TRANSFER) {
        const ids: number[] = await TransactionService.addTransfer(
          data.selectedAccountId, data.toAccountId, data.amountFen, data.note, data.txDate);
        const okTransfer: Result<number[]> = { ok: true, data: ids };
        return okTransfer;
      }
      const txNew: Transaction = new Transaction();
      txNew.type = data.type;
      txNew.amount = data.amountFen;
      txNew.accountId = data.selectedAccountId;
      txNew.categoryId = data.selectedCategoryId;
      txNew.note = data.note;
      txNew.txDate = data.txDate;
      const rowId: number = await TransactionService.add(txNew);
      const okAdd: Result<number[]> = { ok: true, data: [rowId] };
      return okAdd;
    } catch (e) {
      // 业务异常（Service 层 throw）→ 统一结果对象，页面据此 Toast
      const message: string = e instanceof Error ? e.message : ErrorMessages.SAVE_FAILED;
      const errorResult: Result<number[]> = { ok: false, message: message };
      return errorResult;
    }
  }
}
