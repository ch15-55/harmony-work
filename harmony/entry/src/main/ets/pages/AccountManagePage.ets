/**
 * 模块职责：账户管理页（架构 T05 / PRD F-2.1）。
 * - 列出未归档账户 + 实时余额（AccountService.getAllBalances）
 * - 点击进入编辑；右上「新增」进入新增
 * - 三态齐全：LoadingState / ErrorState / EmptyState
 * - 刷新：onPageShow 重读（编辑/归档/删除后回来同步）
 */
import { router } from '@kit.ArkUI';
import { palette } from '../constants/ThemeConstants';
import { AppStorageKeys, AccountType, TxType } from '../constants/AppConstants';
import { RouteConstants } from '../constants/RouteConstants';
import { AccountService } from '../service/AccountService';
import { Account } from '../model/Account';
import { AccountBalance } from '../model/StatsModels';
import { NavTitleBar } from '../components/common/NavTitleBar';
import { LoadingState } from '../components/common/LoadingState';
import { ErrorState } from '../components/common/ErrorState';
import { EmptyState } from '../components/common/EmptyState';
import { AmountText } from '../components/common/AmountText';
import { LogUtil } from '../utils/LogUtil';
import { AccountEditParams } from './AccountEditPage';

@Entry
@Component
struct AccountManagePage {
  /** 页面转场：二级页统一右侧滑入（v1.2 美化） */
  pageTransition() {
    PageTransitionEnter({ type: RouteType.Push, duration: 300, curve: Curve.EaseOut })
      .slide(SlideEffect.Right)
    PageTransitionExit({ type: RouteType.Pop, duration: 280, curve: Curve.EaseIn })
      .slide(SlideEffect.Right)
  }

  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  @StorageLink(AppStorageKeys.DATA_VERSION) @Watch('onDataChanged') dataVersion: number = 0;
  @State private accounts: Account[] = [];
  @State private balances: Map<number, AccountBalance> = new Map();
  @State private loading: boolean = true;
  @State private loadFailed: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  onPageShow(): void {
    this.load();
  }

  onDataChanged(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.loadFailed = false;
    try {
      this.accounts = await AccountService.listAll(false);
      this.balances = await AccountService.getAllBalances();
      this.loadFailed = false;
    } catch (e) {
      LogUtil.e('AccountManagePage', 'load failed');
      this.loadFailed = true;
    }
    this.loading = false;
  }

  private goAdd(): void {
    const params: AccountEditParams = { mode: 'add' };
    router.pushUrl({ url: RouteConstants.ACCOUNT_EDIT, params: params })
      .catch((e: Object) => {
        LogUtil.e('AccountManagePage', 'pushUrl ACCOUNT_EDIT failed');
      });
  }

  private goEdit(id: number): void {
    const params: AccountEditParams = { mode: 'edit', accountId: id };
    router.pushUrl({ url: RouteConstants.ACCOUNT_EDIT, params: params })
      .catch((e: Object) => {
        LogUtil.e('AccountManagePage', 'pushUrl ACCOUNT_EDIT failed');
      });
  }

  private typeRes(type: number): Resource {
    if (type === AccountType.DEBIT) {
      return $r('app.string.account_type_debit');
    }
    if (type === AccountType.CREDIT) {
      return $r('app.string.account_type_credit');
    }
    if (type === AccountType.ALIPAY) {
      return $r('app.string.account_type_alipay');
    }
    if (type === AccountType.WECHAT) {
      return $r('app.string.account_type_wechat');
    }
    if (type === AccountType.OTHER) {
      return $r('app.string.account_type_other');
    }
    return $r('app.string.account_type_cash');
  }

  build() {
    Column() {
      NavTitleBar({
        title: $r('app.string.page_account_manage_title'),
        showBack: true,
        actionText: $r('app.string.account_add'),
        onBack: (): void => { router.back(); },
        onAction: (): void => { this.goAdd(); }
      })

      if (this.loading) {
        LoadingState({ rows: 4 })
      } else if (this.loadFailed) {
        ErrorState({ onRetry: (): void => { this.load(); } })
      } else if (this.accounts.length === 0) {
        EmptyState({ title: $r('app.string.list_empty_month') })
      } else {
        this.list()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).bgPage)
  }

  @Builder
  private list() {
    List({ space: 0 }) {
      ForEach(this.accounts, (account: Account) => {
        ListItem() {
          this.accountRow(account)
        }
        .onClick(() => {
          this.goEdit(account.id);
        })
      }, (account: Account) => 'acc_' + account.id.toString() + '_' +
        account.updatedAt.toString())
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .padding({ left: 16, right: 16, top: 8 })
  }

  @Builder
  private accountRow(account: Account) {
    Row({ space: 12 }) {
      // 分类色点（简洁化，无图标字形）
      Circle()
        .width(12)
        .height(12)
        .fill(account.color)

      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text(account.name)
            .fontSize($r('app.float.font_body'))
            .fontColor(palette(this.isDark).textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (account.isArchived) {
            Text($r('app.string.account_archived_tag'))
              .fontSize($r('app.float.font_aux'))
              .fontColor(palette(this.isDark).textTertiary)
          }
        }
        .width('100%')
        Text(this.typeRes(account.type))
          .fontSize($r('app.float.font_aux'))
          .fontColor(palette(this.isDark).textTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 余额：正绿负红（AmountText 自动配色）
      AmountText({
        amountFen: this.balances.get(account.id)?.balance ?? 0,
        txType: (this.balances.get(account.id)?.balance ?? 0) < 0 ? TxType.EXPENSE : TxType.INCOME,
        autoColor: true
      })
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
    .borderRadius($r('app.float.radius_card'))
  }
}
