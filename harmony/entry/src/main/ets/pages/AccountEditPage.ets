/**
 * 模块职责：账户新增 / 编辑页（架构 T05 / PRD F-2.1 / F-2.2）。
 * - 名称 / 类型（6 类账户）/ 期初余额录入
 * - 编辑态支持归档开关与删除（有流水禁止删除，提示先归档，架构 R11）
 * - 金额仅经 MoneyUtil（÷100 铁律）
 * - 三态：LoadingState / ErrorState
 */
import { router, promptAction } from '@kit.ArkUI';
import { palette } from '../constants/ThemeConstants';
import { AppStorageKeys, AccountType, AppConstants } from '../constants/AppConstants';
import { ErrorMessages } from '../constants/ErrorMessages';
import { RouteConstants } from '../constants/RouteConstants';
import { AccountService } from '../service/AccountService';
import { Account } from '../model/Account';
import { MoneyUtil } from '../utils/MoneyUtil';
import { NavTitleBar } from '../components/common/NavTitleBar';
import { SettingItem } from '../components/common/SettingItem';
import { LoadingState } from '../components/common/LoadingState';
import { ErrorState } from '../components/common/ErrorState';
import { ConfirmDialog } from '../components/common/ConfirmDialog';
import { ToastUtil } from '../utils/ToastUtil';
import { LogUtil } from '../utils/LogUtil';

/** 路由参数（AccountManagePage 透传） */
export interface AccountEditParams {
  mode: string;
  accountId?: number;
}

@Entry
@Component
struct AccountEditPage {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  @State private loading: boolean = true;
  @State private loadFailed: boolean = false;
  /** 编辑态基准（保留 icon/color/sortOrder 等不被编辑字段） */
  private base: Account = new Account();
  @State private editId: number = 0;
  @State private name: string = '';
  @State private type: number = AccountType.CASH;
  @State private initialYuan: string = '';
  @State private isArchived: boolean = false;
  /** 编辑页回填的展示金额；未改金额时保留原始基础货币分，避免汇率往返取整漂移。 */
  private initialYuanAtLoad: string = '';

  private deleteDialog: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({
      title: $r('app.string.common_delete'),
      message: $r('app.string.account_delete_confirm'),
      danger: true,
      onConfirmed: (): void => {
        this.confirmDelete();
      }
    }),
    autoCancel: true
  });

  aboutToAppear(): void {
    const params = router.getParams() as AccountEditParams | undefined;
    const mode: string = params && params.mode ? params.mode : 'add';
    const id: number = params && params.accountId && params.accountId > 0 ? params.accountId : 0;
    this.editId = id;
    this.load(id);
  }

  private async load(id: number): Promise<void> {
    this.loading = true;
    this.loadFailed = false;
    try {
      if (id > 0) {
        const acc: Account | null = await AccountService.getById(id);
        if (acc !== null) {
          this.base = acc;
          this.name = acc.name;
          this.type = acc.type;
          this.initialYuan = acc.initialBalance !== 0
            ? MoneyUtil.fenToYuan(MoneyUtil.baseFenToDisplayFen(acc.initialBalance)).toString() : '';
          this.initialYuanAtLoad = this.initialYuan;
          this.isArchived = acc.isArchived;
        }
      }
      this.loadFailed = false;
    } catch (e) {
      LogUtil.e('AccountEditPage', 'load failed');
      this.loadFailed = true;
    }
    this.loading = false;
  }

  private async onSave(): Promise<void> {
    if (this.name.trim().length === 0) {
      ToastUtil.show(ErrorMessages.ACCOUNT_NAME_EMPTY);
      return;
    }
    const displayFen: number | null = this.initialYuan.trim().length === 0 ? 0 :
      MoneyUtil.parseStrictInput(this.initialYuan);
    if (displayFen === null) {
      ToastUtil.show(ErrorMessages.AMOUNT_INVALID);
      return;
    }
    // 外币展示分值无法与基础货币分值严格互逆。编辑态未改输入时必须沿用原值。
    const fen: number = this.editId > 0 && this.initialYuan === this.initialYuanAtLoad
      ? this.base.initialBalance
      : MoneyUtil.displayFenToBaseFen(displayFen);
    if (!Number.isSafeInteger(fen) || Math.abs(fen) > AppConstants.MAX_MONEY_FEN) {
      ToastUtil.show(ErrorMessages.AMOUNT_INVALID);
      return;
    }
    try {
      if (this.editId > 0) {
        this.base.name = this.name;
        this.base.type = this.type;
        this.base.initialBalance = fen;
        await AccountService.update(this.base);
      } else {
        const acc: Account = new Account();
        acc.name = this.name;
        acc.type = this.type;
        acc.initialBalance = fen;
        acc.icon = 'wallet';
        acc.color = '#5B67F5';
        await AccountService.add(acc);
      }
      ToastUtil.showRes($r('app.string.account_save_success'));
      router.back();
    } catch (e) {
      ToastUtil.show(ErrorMessages.SAVE_FAILED);
    }
  }

  private async onToggleArchive(archived: boolean): Promise<void> {
    if (this.editId <= 0) {
      return;
    }
    try {
      await AccountService.archive(this.editId, archived);
      this.isArchived = archived;
    } catch (e) {
      ToastUtil.show(ErrorMessages.SAVE_FAILED);
    }
  }

  private async confirmDelete(): Promise<void> {
    if (this.editId <= 0) {
      return;
    }
    try {
      await AccountService.delete(this.editId);
      ToastUtil.showRes($r('app.string.toast_delete_success'));
      router.back();
    } catch (e) {
      const err: Error = e as Error;
      // 有流水时 Service 抛业务异常，提示先归档
      ToastUtil.show(err.message.length > 0 ? err.message : ErrorMessages.ACCOUNT_HAS_TX);
    }
  }

  build() {
    Column() {
      // 统一导航栏：内部按 WindowUtil 写入的状态栏高度避让，不再自建顶部行
      NavTitleBar({
        title: this.editId > 0 ? $r('app.string.page_account_edit_title') : $r('app.string.account_add'),
        showBack: true,
        actionText: $r('app.string.common_save'),
        onBack: (): void => {
          router.back();
        },
        onAction: (): void => {
          this.onSave();
        }
      })

      if (this.loading) {
        LoadingState({ rows: 4 })
      } else if (this.loadFailed) {
        ErrorState({ onRetry: (): void => { this.load(this.editId); } })
      } else {
        this.editor()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).bgPage)
  }

  @Builder
  private editor() {
    Scroll() {
      Column({ space: 12 }) {
        // 名称
        Column({ space: 6 }) {
          Text($r('app.string.account_name_label'))
            .fontSize($r('app.float.font_aux'))
            .fontColor(palette(this.isDark).textSecondary)
            .width('100%')
          TextInput({ text: this.name, placeholder: $r('app.string.account_name_hint') })
            .fontSize($r('app.float.font_body'))
            .backgroundColor(palette(this.isDark).bgCard)
            .borderRadius($r('app.float.radius_button'))
            .onChange((value: string): void => {
              this.name = value;
            })
        }
        .width('100%')
        .padding($r('app.float.card_padding'))
        .backgroundColor(palette(this.isDark).bgCard)
        .borderRadius($r('app.float.radius_card'))

        // 类型
        Column({ space: 8 }) {
          Text($r('app.string.account_type_label'))
            .fontSize($r('app.float.font_aux'))
            .fontColor(palette(this.isDark).textSecondary)
            .width('100%')
          this.typeChips()
        }
        .width('100%')
        .padding($r('app.float.card_padding'))
        .backgroundColor(palette(this.isDark).bgCard)
        .borderRadius($r('app.float.radius_card'))

        // 期初余额
        Column({ space: 6 }) {
          Text($r('app.string.account_initial_label'))
            .fontSize($r('app.float.font_aux'))
            .fontColor(palette(this.isDark).textSecondary)
            .width('100%')
          TextInput({ text: this.initialYuan, placeholder: '0.00' })
            .type(InputType.Number)
            .fontSize($r('app.float.font_body'))
            .backgroundColor(palette(this.isDark).bgCard)
            .borderRadius($r('app.float.radius_button'))
            .onChange((value: string): void => {
              this.initialYuan = value;
            })
        }
        .width('100%')
        .padding($r('app.float.card_padding'))
        .backgroundColor(palette(this.isDark).bgCard)
        .borderRadius($r('app.float.radius_card'))

        // 编辑态：归档 + 删除
        if (this.editId > 0) {
          Column() {
            SettingItem({
              iconKey: 'ic_common_wallet',
              title: $r('app.string.account_archive'),
              showToggle: true,
              toggleOn: this.isArchived,
              showDivider: true,
              onToggleChange: (on: boolean): void => {
                this.onToggleArchive(on);
              }
            })
            SettingItem({
              iconKey: 'ic_common_none',
              title: $r('app.string.common_delete'),
              danger: true,
              showDivider: false,
              onItemClick: (): void => {
                this.deleteDialog.open();
              }
            })
          }
          .width('100%')
          .borderRadius($r('app.float.radius_card'))
          .backgroundColor(palette(this.isDark).bgCard)
          .clip(true)
        }

        Blank().height(16)
      }
      .width('100%')
      .padding({ top: 8, bottom: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .padding({ left: 16, right: 16 })
  }

  /** 账户类型六选一 */
  @Builder
  private typeChips() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      this.chip($r('app.string.account_type_cash'), AccountType.CASH)
      this.chip($r('app.string.account_type_debit'), AccountType.DEBIT)
      this.chip($r('app.string.account_type_credit'), AccountType.CREDIT)
      this.chip($r('app.string.account_type_alipay'), AccountType.ALIPAY)
      this.chip($r('app.string.account_type_wechat'), AccountType.WECHAT)
      this.chip($r('app.string.account_type_other'), AccountType.OTHER)
    }
    .width('100%')
  }

  @Builder
  private chip(label: Resource, value: number) {
    Text(label)
      .fontSize($r('app.float.font_body'))
      .fontColor(this.type === value ? '#FFFFFF' : palette(this.isDark).textPrimary)
      .textAlign(TextAlign.Center)
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .margin({ right: 8, bottom: 8 })
      .borderRadius($r('app.float.radius_button'))
      .backgroundColor(this.type === value ? palette(this.isDark).primary : palette(this.isDark).bgElevated)
      .onClick((): void => {
        this.type = value;
      })
  }
}
