/**
 * 模块职责：流水详情页（架构 T05 填充业务 UI，F-5.6 / F-5.7）。
 * - 全字段展示：类型 / 金额 / 分类 / 账户（转账为「A → B」）/ 日期时间 / 备注 / 记录时间
 * - 编辑：非转账跳记账页 edit 模式；转账按 Service 约定不支持单条编辑，Toast 提示
 * - 删除：ConfirmDialog 二次确认，转账文案额外提示「将同时删除对应的另一条转账记录」
 * - 三态齐全：LoadingState / ErrorState / 流水已被删除时的空态
 * - 刷新：@StorageLink(dataVersion) @Watch + onPageShow（编辑返回后重新取数）
 */
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { palette } from '../constants/ThemeConstants';
import { AppStorageKeys, TxType } from '../constants/AppConstants';
import { RouteConstants } from '../constants/RouteConstants';
import { ErrorMessages } from '../constants/ErrorMessages';
import { RecordsViewModel } from '../viewmodel/RecordsViewModel';
import { TxDisplayItem } from '../model/StatsModels';
import { NavTitleBar } from '../components/common/NavTitleBar';
import { EmptyState } from '../components/common/EmptyState';
import { ErrorState } from '../components/common/ErrorState';
import { LoadingState } from '../components/common/LoadingState';
import { ConfirmDialog } from '../components/common/ConfirmDialog';
import { MoneyUtil } from '../utils/MoneyUtil';
import { DateUtil } from '../utils/DateUtil';
import { LogUtil } from '../utils/LogUtil';
import { ToastUtil } from '../utils/ToastUtil';
import { RecordEditParams } from './RecordEditPage';

/** 流水详情页路由参数 */
export interface TxDetailParams {
  txId: number;
}

@Entry
@Component
export struct TransactionDetailPage {
  /** 页面转场：二级页统一右侧滑入（v1.2 美化） */
  pageTransition() {
    PageTransitionEnter({ type: RouteType.Push, duration: 300, curve: Curve.EaseOut })
      .slide(SlideEffect.Right)
    PageTransitionExit({ type: RouteType.Pop, duration: 280, curve: Curve.EaseIn })
      .slide(SlideEffect.Right)
  }

  private static readonly TAG: string = 'TransactionDetailPage';
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  @StorageLink(AppStorageKeys.DATA_VERSION) @Watch('onDataVersionChanged') dataVersion: number = 0;
  /** 展示条目（含分类名/账户名） */
  @State private item: TxDisplayItem = new TxDisplayItem();
  @State private loading: boolean = true;
  @State private loadFailed: boolean = false;
  /** 流水不存在（已被其他入口删除） */
  @State private missing: boolean = false;
  private txId: number = 0;
  private firstShowConsumed: boolean = false;
  /** 删除中防重复 */
  private deleting: boolean = false;

  /** 普通流水删除确认 */
  private deleteDialog: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({
      title: $r('app.string.list_delete_confirm_title'),
      message: $r('app.string.list_delete_confirm_message'),
      confirmText: $r('app.string.common_delete'),
      danger: true,
      onConfirmed: (): void => {
        this.confirmDelete();
      }
    }),
    autoCancel: true,
    customStyle: false
  });

  /** 转账流水删除确认（提示同时删除配对流水） */
  private deleteTransferDialog: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({
      title: $r('app.string.list_delete_confirm_title'),
      message: $r('app.string.list_delete_transfer_tip'),
      confirmText: $r('app.string.common_delete'),
      danger: true,
      onConfirmed: (): void => {
        this.confirmDelete();
      }
    }),
    autoCancel: true,
    customStyle: false
  });

  aboutToAppear(): void {
    const params: Object | undefined = router.getParams();
    if (params !== undefined && params !== null) {
      const typed: TxDetailParams = params as TxDetailParams;
      this.txId = typed.txId;
    }
    this.loadData();
  }

  onPageShow(): void {
    if (!this.firstShowConsumed) {
      this.firstShowConsumed = true;
      return;
    }
    this.loadData();
  }

  private onDataVersionChanged(propName: string): void {
    this.loadData();
  }

  /** 资源 → 纯文本 */
  private resText(res: Resource): string {
    const context: common.Context = getContext(this) as common.Context;
    return context.resourceManager.getStringSync(res);
  }

  /** 载入单条流水并关联名称 */
  private async loadData(): Promise<void> {
    if (this.txId <= 0) {
      this.loading = false;
      this.missing = true;
      return;
    }
    this.loading = true;
    this.loadFailed = false;
    try {
      const detail: TxDisplayItem | null = await RecordsViewModel.loadDetail(this.txId);
      if (detail === null) {
        this.missing = true;
      } else {
        this.item = detail;
        this.missing = false;
      }
      this.loadFailed = false;
    } catch (e) {
      LogUtil.e(TransactionDetailPage.TAG, 'loadData failed');
      this.loadFailed = true;
    }
    this.loading = false;
  }

  /** 类型文案 */
  private typeText(): Resource {
    if (this.item.tx.type === TxType.INCOME) {
      return $r('app.string.record_type_income');
    }
    if (this.item.tx.type === TxType.TRANSFER) {
      return $r('app.string.record_type_transfer');
    }
    return $r('app.string.record_type_expense');
  }

  /** 金额文案：收入带 +，支出带 -，转账不带方向号 */
  private amountText(): string {
    if (this.item.tx.type === TxType.INCOME) {
      return '+' + MoneyUtil.display(this.item.tx.amount);
    }
    if (this.item.tx.type === TxType.TRANSFER) {
      return MoneyUtil.display(this.item.tx.amount);
    }
    return '-' + MoneyUtil.display(this.item.tx.amount);
  }

  /** 金额颜色 */
  private amountColor(): string {
    if (this.item.tx.type === TxType.INCOME) {
      return palette(this.isDark).income;
    }
    if (this.item.tx.type === TxType.TRANSFER) {
      return palette(this.isDark).transfer;
    }
    return palette(this.isDark).expense;
  }

  /** 备注（空值占位「—」） */
  private noteText(): string {
    if (this.item.tx.note.length === 0) {
      return this.resText($r('app.string.common_none_value'));
    }
    return this.item.tx.note;
  }

  /** 分类名（缺分类兜底占位） */
  private categoryText(): string {
    if (this.item.categoryName.length === 0) {
      return this.resText($r('app.string.common_none_value'));
    }
    return this.item.categoryName;
  }

  /** 账户名（转账为「A → B」，由 TxDisplayMapper 拼装） */
  private accountText(): string {
    if (this.item.accountName.length === 0) {
      return this.resText($r('app.string.common_none_value'));
    }
    return this.item.accountName;
  }

  /** 编辑（转账不支持单条编辑） */
  private editTx(): void {
    if (this.item.tx.type === TxType.TRANSFER) {
      ToastUtil.show(ErrorMessages.TX_TRANSFER_EDIT_BLOCKED);
      return;
    }
    const params: RecordEditParams = { mode: 'edit', txId: this.item.tx.id };
    router.pushUrl({ url: RouteConstants.RECORD_EDIT, params: params })
      .catch((e: Object) => {
        LogUtil.e(TransactionDetailPage.TAG, 'pushUrl RECORD_EDIT failed');
      });
  }

  /** 删除：二次确认 */
  private askDelete(): void {
    if (this.item.tx.type === TxType.TRANSFER) {
      this.deleteTransferDialog.open();
      return;
    }
    this.deleteDialog.open();
  }

  /** 确认删除后返回上一页（Service 内含转账双删事务 + bump） */
  private async confirmDelete(): Promise<void> {
    if (this.deleting || this.item.tx.id <= 0) {
      return;
    }
    this.deleting = true;
    try {
      await RecordsViewModel.deleteTx(this.item.tx.id);
      ToastUtil.showRes($r('app.string.toast_delete_success'));
      this.deleting = false;
      router.back();
    } catch (e) {
      LogUtil.e(TransactionDetailPage.TAG, 'deleteTx failed');
      ToastUtil.showRes($r('app.string.toast_delete_failed'));
      this.deleting = false;
    }
  }

  /** 字段行 */
  @Builder
  private detailRow(label: Resource, value: string, showDivider: boolean) {
    Column() {
      Row({ space: 12 }) {
        Text(label)
          .fontSize($r('app.float.font_body'))
          .fontColor(palette(this.isDark).textSecondary)
        Text(value)
          .fontSize($r('app.float.font_body'))
          .fontColor(palette(this.isDark).textPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.End)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Center)

      if (showDivider) {
        Divider()
          .color(palette(this.isDark).divider)
          .strokeWidth(1)
      }
    }
    .width('100%')
  }

  /** 正文 */
  @Builder
  private contentArea() {
    Scroll() {
      Column({ space: 12 }) {
        // 金额头卡
        Column({ space: 6 }) {
          Text(this.typeText())
            .fontSize($r('app.float.font_aux'))
            .fontColor(palette(this.isDark).textSecondary)
          Text(this.amountText())
            .fontSize($r('app.float.font_amount_large'))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.amountColor())
            .fontFeature('"tnum" on')
            .maxLines(1)
        }
        .width('100%')
        .padding($r('app.float.card_padding'))
        .borderRadius($r('app.float.radius_card'))
        .backgroundColor(palette(this.isDark).bgCard)

        // 字段卡
        Column() {
          if (this.item.tx.type === TxType.TRANSFER) {
            this.detailRow($r('app.string.detail_transfer_path_label'), this.accountText(), true)
          } else {
            this.detailRow($r('app.string.detail_category_label'), this.categoryText(), true)
            this.detailRow($r('app.string.detail_account_label'), this.accountText(), true)
          }
          this.detailRow($r('app.string.detail_date_label'),
            DateUtil.formatDate(this.item.tx.txDate) + ' ' +
            DateUtil.weekdayLabel(this.item.tx.txDate), true)
          // 只记录日期时 tx_date 为当日 0 点，不展示无意义的 00:00；记录时间另列展示
          if (!DateUtil.isDateOnly(this.item.tx.txDate)) {
            this.detailRow($r('app.string.detail_time_label'),
              DateUtil.formatTime(this.item.tx.txDate), true)
          }
          this.detailRow($r('app.string.detail_note_label'), this.noteText(), true)
          this.detailRow($r('app.string.detail_created_label'),
            DateUtil.formatDateTime(this.item.tx.createdAt), false)
        }
        .width('100%')
        .padding({
          left: $r('app.float.card_padding'),
          right: $r('app.float.card_padding')
        })
        .borderRadius($r('app.float.radius_card'))
        .backgroundColor(palette(this.isDark).bgCard)

        // 操作区
        Row({ space: 12 }) {
          Text($r('app.string.common_edit'))
            .fontSize($r('app.float.font_body'))
            .fontColor(palette(this.isDark).primary)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 12, bottom: 12 })
            .borderRadius($r('app.float.radius_button'))
            .border({ width: 1, color: palette(this.isDark).primary })
            .onClick(() => {
              this.editTx();
            })

          Text($r('app.string.common_delete'))
            .fontSize($r('app.float.font_body'))
            .fontColor('#FFFFFF')
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 12, bottom: 12 })
            .borderRadius($r('app.float.radius_button'))
            .backgroundColor(palette(this.isDark).danger)
            .onClick(() => {
              this.askDelete();
            })
        }
        .width('100%')
        .padding({ top: 8 })
      }
      .width('100%')
      .padding({ bottom: 24 })
    }
    .layoutWeight(1)
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .padding({ left: $r('app.float.page_padding'), right: $r('app.float.page_padding') })
  }

  build() {
    Column() {
      NavTitleBar({
        title: $r('app.string.page_tx_detail_title'),
        showBack: true,
        onBack: (): void => {
          router.back();
        }
      })

      if (this.loading) {
        // 骨架屏外层承载页面内边距（自定义组件不直接加 padding）
        Column() {
          LoadingState({ rows: 5, rowHeight: 56 })
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: $r('app.float.page_padding'), right: $r('app.float.page_padding') })
      } else if (this.loadFailed) {
        ErrorState({
          title: $r('app.string.common_error_title'),
          message: $r('app.string.common_error_desc'),
          onRetry: (): void => {
            this.loadData();
          }
        })
          .layoutWeight(1)
      } else if (this.missing) {
        EmptyState({
          title: $r('app.string.detail_missing'),
          iconKey: 'ic_common_none',
          buttonText: this.resText($r('app.string.common_back')),
          onButton: (): void => {
            router.back();
          }
        })
          .layoutWeight(1)
      } else {
        this.contentArea()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).bgPage)
  }
}
