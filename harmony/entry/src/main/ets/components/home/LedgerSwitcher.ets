/**
 * 模块职责：账本切换入口（架构 T04 home/LedgerSwitcher / PRD F-2.6，v1.1 开放）。
 * - 点击展开半模态账本列表（bindSheet），点击账本行回调 onSwitch（页面持久化 + bump）
 * - 底部提供「新建账本」与「管理账本」入口（components 禁止 router，均由页面回调处理）
 * - 当前账本行带主色对勾标记
 */
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys, Result } from '../../constants/AppConstants';
import { Ledger } from '../../model/Ledger';
import { LedgerViewModel } from '../../viewmodel/LedgerViewModel';
import { SettingsService } from '../../service/SettingsService';
import { LogUtil } from '../../utils/LogUtil';

@Component
export struct LedgerSwitcher {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 当前账本名（HomePage 传入） */
  @Prop ledgerName: string = '';
  /** 半模态显隐（$$ 双向绑定，下拉/点击遮罩自动置回 false） */
  @State private showSheet: boolean = false;
  /** 账本列表（展开时加载） */
  @State private ledgers: Ledger[] = [];
  @State private currentLedgerId: number = 1;
  /** 切换账本回调（页面：持久化当前 id + DataBus.bump） */
  onSwitch?: (ledgerId: number) => void;
  /** 新建账本回调（页面弹 InputDialog） */
  onCreate?: () => void;
  /** 管理账本回调（页面路由到 LedgerManagePage） */
  onManage?: () => void;

  /** 展开前刷新账本列表，保证对勾与列表最新 */
  private async openSheet(): Promise<void> {
    const result: Result<Ledger[]> = await LedgerViewModel.load();
    if (result.ok && result.data !== undefined) {
      this.ledgers = result.data;
      this.currentLedgerId = SettingsService.getCurrentLedgerId();
    } else {
      LogUtil.w('LedgerSwitcher', 'load ledgers failed');
    }
    this.showSheet = true;
  }

  @Builder
  private sheetBody() {
    Column() {
      Text($r('app.string.ledger_switch_title'))
        .fontSize($r('app.float.font_title'))
        .fontWeight(FontWeight.Medium)
        .fontColor(palette(this.isDark).textPrimary)
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 8 })

      List({ space: 0 }) {
        ForEach(this.ledgers, (ledger: Ledger) => {
          ListItem() {
            Row({ space: 12 }) {
              Circle()
                .width(12)
                .height(12)
                .fill(ledger.color)

              Text(ledger.name)
                .fontSize($r('app.float.font_body'))
                .fontColor(palette(this.isDark).textPrimary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)

              if (ledger.id === this.currentLedgerId) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize($r('app.float.font_title'))
                  .fontColor([palette(this.isDark).primary])
                  .fontWeight(FontWeight.Medium)
              }
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 12, bottom: 12 })
            .onClick(() => {
              this.showSheet = false;
              if (ledger.id !== this.currentLedgerId && this.onSwitch !== undefined) {
                this.onSwitch(ledger.id);
              }
            })
          }
        }, (ledger: Ledger) => 'switch_ledger_' + ledger.id.toString() + '_' +
          ledger.updatedAt.toString())
      }
      .width('100%')
      .scrollBar(BarState.Off)

      Divider()
        .color(palette(this.isDark).divider)
        .margin({ top: 8, bottom: 4 })

      Row({ space: 12 }) {
        Text('＋')
          .fontSize(18)
          .fontColor(palette(this.isDark).primary)
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
        Text($r('app.string.ledger_create_action'))
          .fontSize($r('app.float.font_body'))
          .fontColor(palette(this.isDark).primary)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })
      .onClick(() => {
        this.showSheet = false;
        if (this.onCreate !== undefined) {
          this.onCreate();
        }
      })

      Row() {
        Text($r('app.string.ledger_manage_action'))
          .fontSize($r('app.float.font_body'))
          .fontColor(palette(this.isDark).textPrimary)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 16 })
      .onClick(() => {
        this.showSheet = false;
        if (this.onManage !== undefined) {
          this.onManage();
        }
      })
    }
    .width('100%')
  }

  build() {
    Column() {
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.book'))
          .fontSize(18)
          .fontColor([palette(this.isDark).textPrimary])
        Text(this.ledgerName)
          .fontSize($r('app.float.font_title'))
          .fontWeight(FontWeight.Medium)
          .fontColor(palette(this.isDark).textPrimary)
          .maxLines(1)
          .maxFontSize($r('app.float.font_title'))
          .minFontSize($r('app.float.font_body'))
        Text('▾')
          .fontSize($r('app.float.font_aux'))
          .fontColor(palette(this.isDark).textSecondary)
      }
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .borderRadius($r('app.float.radius_tag'))
      .onClick(() => {
        this.openSheet();
      })
    }
    .bindSheet($$this.showSheet, this.sheetBody(), {
      height: 420,
      dragBar: true,
      backgroundColor: palette(this.isDark).bgElevated,
      showClose: true
    } as SheetOptions)
  }
}
