/**
 * 模块职责：记账页（架构 T05 / PRD 5.3 P2）。
 * 全屏拉起：支出/收入/转账切换 + 分类宫格 + 账户选择 + 日期 + 备注 + 自绘计算器键盘。
 * 支持 mode=add / mode=edit（路由参数 RecordEditParams）。
 * 键盘契约：onExprChange 回传完整表达式；onConfirm(fen) 触发保存。
 */
import { router } from '@kit.ArkUI';
import { palette } from '../constants/ThemeConstants';
import { AppStorageKeys, AppConstants, TxType } from '../constants/AppConstants';
import { RouteConstants } from '../constants/RouteConstants';
import { RecordEditViewModel, RecordEditData } from '../viewmodel/RecordEditViewModel';
import { Category } from '../model/Category';
import { LogUtil } from '../utils/LogUtil';
import { DateUtil } from '../utils/DateUtil';
import { TypeSwitchTabs } from '../components/record/TypeSwitchTabs';
import { CategoryGrid } from '../components/record/CategoryGrid';
import { AccountSelector, AccountOption } from '../components/record/AccountSelector';
import { DateSelector } from '../components/record/DateSelector';
import { NoteInput } from '../components/record/NoteInput';
import { AmountKeyboard } from '../components/record/AmountKeyboard';
import { LoadingState } from '../components/common/LoadingState';
import { ErrorState } from '../components/common/ErrorState';
import { NavTitleBar } from '../components/common/NavTitleBar';
import { ToastUtil } from '../utils/ToastUtil';

/** 路由参数（由 pages/Index.ets / RecordsPage / StatisticsPage 透传） */
export interface RecordEditParams {
  mode: string;
  txId?: number;
  categoryId?: number;
  monthKey?: string;
}

@Entry
@Component
struct RecordEditPage {
  /** 页面转场：底部滑入，模态编辑感（v1.2 美化） */
  pageTransition() {
    PageTransitionEnter({ type: RouteType.Push, duration: 320, curve: Curve.EaseOut })
      .slide(SlideEffect.Bottom)
    PageTransitionExit({ type: RouteType.Pop, duration: 280, curve: Curve.EaseIn })
      .slide(SlideEffect.Bottom)
  }

  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 状态栏/导航条高度（px，WindowUtil 冷启动写入），沉浸式避让 */
  @StorageLink(AppStorageKeys.STATUS_BAR_HEIGHT_PX) statusBarHeightPx: number = 0;
  @StorageLink(AppStorageKeys.NAV_INDICATOR_HEIGHT_PX) navIndicatorHeightPx: number = 0;

  @State private data: RecordEditData | null = null;
  @State private loading: boolean = true;
  @State private errorMsg: string = '';
  /** 键盘清空令牌：保存/重置后 +1 触发键盘清空 */
  @State private resetToken: number = 0;
  /** 当前编辑态 id（>0 为编辑） */
  @State private editId: number = 0;
  /**
   * 保存中标志（防重入）。
   * 保存有两个入口：标题「保存」与键盘「完成」，await 期间两者仍可再次点击，
   * 无守卫会并发两次 TransactionService.add → 同一笔记两遍。
   */
  @State private saving: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as RecordEditParams | undefined;
    const mode: string = params && params.mode ? params.mode : 'add';
    this.editId = (params && params.txId && params.txId > 0) ? params.txId : 0;
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      this.data = await RecordEditViewModel.load(this.editId, TxType.EXPENSE);
    } catch (e) {
      this.errorMsg = (e instanceof Error) ? e.message : getContext(this).resourceManager.getStringSync($r('app.string.common_error_title'));
      this.data = null;
    } finally {
      this.loading = false;
    }
  }

  /** 触发 @State 重新渲染（@State 仅观察引用变化） */
  private commit(): void {
    if (this.data !== null) {
      this.data = this.data.clone();
    }
  }

  private onExprChange(expr: string): void {
    if (this.data === null) {
      return;
    }
    this.data.expression = expr;
    // 键盘按展示币种输入，入库前换算回基础货币（¥ 分）；
    // 编辑态未改动金额时沿用库中原始值，规避汇率往返漂移
    this.data.amountFen = RecordEditViewModel.resolveAmountFen(this.data, expr);
    this.commit();
  }

  private onConfirm(fen: number): void {
    if (this.data === null) {
      return;
    }
    // 与 onExprChange 同一口径：编辑态未改动金额时保持原始基础货币分
    this.data.amountFen = RecordEditViewModel.resolveAmountFen(this.data, this.data.expression);
    this.commit();
    this.doSave();
  }

  private async onTypeChange(txType: number): Promise<void> {
    if (this.data === null) {
      return;
    }
    await RecordEditViewModel.switchType(this.data, txType);
    this.commit();
  }

  private onSelectCategory(categoryId: number): void {
    if (this.data === null) {
      return;
    }
    this.data.selectedCategoryId = categoryId;
    this.commit();
  }

  private onSelectFrom(accountId: number): void {
    if (this.data === null) {
      return;
    }
    this.data.selectedAccountId = accountId;
    this.commit();
  }

  private onSelectTo(accountId: number): void {
    if (this.data === null) {
      return;
    }
    this.data.toAccountId = accountId;
    this.commit();
  }

  private onDateChange(ts: number): void {
    if (this.data === null) {
      return;
    }
    this.data.txDate = ts;
    this.commit();
  }

  private onNoteChange(note: string): void {
    if (this.data === null) {
      return;
    }
    this.data.note = note;
    this.commit();
  }

  private accent(): string {
    if (this.data === null) {
      return palette(this.isDark).primary;
    }
    if (this.data.type === TxType.EXPENSE) {
      return palette(this.isDark).expense;
    }
    if (this.data.type === TxType.INCOME) {
      return palette(this.isDark).income;
    }
    return palette(this.isDark).transfer;
  }

  /** 组装账户选择器入参 */
  private accountOptions(): AccountOption[] {
    const opts: AccountOption[] = [];
    if (this.data !== null) {
      for (let i = 0; i < this.data.accounts.length; i++) {
        const a = this.data.accounts[i];
        const o = new AccountOption();
        o.id = a.id;
        o.name = a.name;
        o.icon = a.icon;
        o.color = a.color;
        const bal = this.data.balances.get(a.id);
        o.balance = bal ? bal.balance : 0;
        opts.push(o);
      }
    }
    return opts;
  }

  private async doSave(): Promise<void> {
    // 防重入：标题「保存」与键盘「完成」两个入口共用同一把锁
    if (this.saving || this.data === null) {
      return;
    }
    this.saving = true;
    try {
      await this.doSaveInner();
    } finally {
      this.saving = false;
    }
  }

  private async doSaveInner(): Promise<void> {
    if (this.data === null) {
      return;
    }
    const result = await RecordEditViewModel.save(this.data);
    if (!result.ok) {
      if (result.message !== undefined && result.message.length > 0) {
        ToastUtil.show(result.message);
      } else {
        ToastUtil.showRes($r('app.string.toast_save_failed'));
      }
      return;
    }
    const isTransfer: boolean = this.data.type === TxType.TRANSFER;
    if (this.editId > 0) {
      // 编辑模式：保存成功后返回来源页（Service 内已 bump，首页/明细/统计自动刷新）
      ToastUtil.showRes(isTransfer ? $r('app.string.record_save_transfer') : $r('app.string.record_saved'));
      router.back();
      return;
    }
    ToastUtil.showRes(isTransfer ? $r('app.string.record_save_transfer') : $r('app.string.record_saved'));
    // 再记一笔：重置为同类型空白表单
    this.resetToken += 1;
    await this.resetForAnother();
  }

  private async resetForAnother(): Promise<void> {
    const keepType: number = this.data !== null ? this.data.type : TxType.EXPENSE;
    try {
      this.data = await RecordEditViewModel.load(0, keepType);
    } catch (e) {
      this.errorMsg = (e instanceof Error) ? e.message : getContext(this).resourceManager.getStringSync($r('app.string.common_error_title'));
      this.data = null;
    }
  }

  private onClose(): void {
    router.back();
  }

  build() {
    Column() {
      // 顶部：关闭 / 标题 / 保存（padding-top 含状态栏避让）
      Row() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(20)
          .fontColor([palette(this.isDark).textPrimary])
          .padding({ left: 4, right: 12 })
          .onClick(() => { this.onClose(); })
        Text(this.editId > 0 ? $r('app.string.record_edit_title') : $r('app.string.page_record_edit_title'))
          .fontSize($r('app.float.font_title'))
          .fontWeight(FontWeight.Medium)
          .fontColor(palette(this.isDark).textPrimary)
          .layoutWeight(1)
        Text($r('app.string.common_save'))
          .fontSize($r('app.float.font_body'))
          .fontColor(this.saving ? palette(this.isDark).textTertiary : palette(this.isDark).primary)
          .onClick(() => { this.doSave(); })
          .enabled(!this.saving)
      }
      .width('100%')
      .padding({
        top: 12 + px2vp(this.statusBarHeightPx),
        bottom: 8,
        left: 12,
        right: 16
      })

      if (this.loading) {
        LoadingState({ rows: 5 })
      } else if (this.errorMsg.length > 0) {
        ErrorState({ onRetry: (): void => { this.load(); } })
      } else if (this.data !== null) {
        this.editor()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).bgPage)
  }

  /**
   * 编辑区（无参 Builder：直接绑定 this.data）。
   * ⚠️ ArkUI 铁律：@Builder 按值传参不随状态刷新，必须引用 this.* 保持响应式。
   */
  @Builder
  private editor() {
    Column() {
      // 支出/收入/转账 切换（编辑模式隐藏转账：Service 层禁止改转账，避免填完保存必报错）
      TypeSwitchTabs({
        selected: this.data!.type,
        showTransfer: this.editId <= 0,
        onTypeChange: (txType: number): void => { this.onTypeChange(txType); }
      })
        .margin({ top: 4, bottom: 8 })

      // 金额大字
      Text(this.data!.currency + (this.data!.expression.length > 0 ? this.data!.expression : '0'))
        .fontSize($r('app.float.font_display'))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.accent())
        .fontFeature('"tnum" on')
        .alignSelf(ItemAlign.End)
        .margin({ right: 4, top: 4, bottom: 8 })

      Scroll() {
        Column({ space: 12 }) {
          // 转账态：隐藏分类，显示从账户/到账户
          if (this.data!.type === TxType.TRANSFER) {
            AccountSelector({
              options: this.accountOptions(),
              selectedId: this.data!.selectedAccountId,
              labelRes: $r('app.string.record_from_account'),
              onSelected: (id: number): void => { this.onSelectFrom(id); }
            })
            AccountSelector({
              options: this.accountOptions(),
              selectedId: this.data!.toAccountId,
              labelRes: $r('app.string.record_to_account'),
              onSelected: (id: number): void => { this.onSelectTo(id); }
            })
          } else {
            CategoryGrid({
              categories: this.data!.categories,
              selectedId: this.data!.selectedCategoryId,
              onSelect: (id: number): void => { this.onSelectCategory(id); },
              onMore: (): void => {
                router.pushUrl({ url: RouteConstants.CATEGORY_MANAGE })
                  .catch((e: Object) => {
                    LogUtil.e('RecordEditPage', 'pushUrl CATEGORY_MANAGE failed');
                  });
              }
            })
            AccountSelector({
              options: this.accountOptions(),
              selectedId: this.data!.selectedAccountId,
              labelRes: $r('app.string.record_account_label'),
              onSelected: (id: number): void => { this.onSelectFrom(id); }
            })
          }

          DateSelector({
            txDate: this.data!.txDate,
            allowFuture: false,
            onDateChange: (ts: number): void => { this.onDateChange(ts); }
          })

          NoteInput({
            note: this.data!.note,
            onNoteChange: (note: string): void => { this.onNoteChange(note); }
          })
        }
        .padding({ left: 4, right: 4, top: 4, bottom: 8 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // 自绘计算器键盘（padding-bottom 避让手势条）
      AmountKeyboard({
        accentColor: this.accent(),
        resetToken: this.resetToken,
        initialExpr: this.data!.expression,
        onExprChange: (expr: string): void => { this.onExprChange(expr); },
        onConfirm: (fen: number): void => { this.onConfirm(fen); }
      })
        .padding({
          left: 8,
          right: 8,
          bottom: 8 + px2vp(this.navIndicatorHeightPx)
        })
    }
    .width('100%')
    .layoutWeight(1)
  }
}
