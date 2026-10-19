/**
 * 模块职责：账本管理页（PRD F-10.2 / F-10.3，架构 T02）。
 * - 列出全部账本（当前账本标记「使用中」），新建走右上角「新建」
 * - 新建/重命名弹层：名称 TextInput（上限 20 字符）+ 色点（简洁化：无图标）
 * - 删除 → ConfirmDialog 二次确认（LedgerService 校验拦截：默认账本/最后一本/有流水）
 * - 切换走 LedgerService.switchTo（持久化 + bump 由 service 触发）
 * - 三态齐全：LoadingState / ErrorState / EmptyState；写操作后 DataBus.bump 自动刷新
 */
import { router } from '@kit.ArkUI';
import { palette } from '../constants/ThemeConstants';
import { AppConstants, AppStorageKeys, Result } from '../constants/AppConstants';
import { Ledger } from '../model/Ledger';
import { LedgerService, LEDGER_COLOR_CHOICES } from '../service/LedgerService';
import { LedgerViewModel } from '../viewmodel/LedgerViewModel';
import { SettingsService } from '../service/SettingsService';
import { IconConstants } from '../constants/IconConstants';
import { NavTitleBar } from '../components/common/NavTitleBar';
import { LoadingState } from '../components/common/LoadingState';
import { ErrorState } from '../components/common/ErrorState';
import { EmptyState } from '../components/common/EmptyState';
import { ConfirmDialog } from '../components/common/ConfirmDialog';
import { ToastUtil } from '../utils/ToastUtil';
import { LogUtil } from '../utils/LogUtil';

@Entry
@Component
struct LedgerManagePage {
  private static readonly TAG: string = 'LedgerManagePage';
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  @StorageLink(AppStorageKeys.DATA_VERSION) @Watch('onDataChanged') dataVersion: number = 0;
  @State private ledgers: Ledger[] = [];
  @State private currentLedgerId: number = 1;
  @State private loading: boolean = true;
  @State private loadFailed: boolean = false;

  // ---------- 新建 / 重命名弹层状态（0 = 新建模式） ----------
  @State private editorOpen: boolean = false;
  @State private editingId: number = 0;
  @State private inputName: string = '';
  @State private selectedColor: string = LEDGER_COLOR_CHOICES[0];

  /** 待删除的账本 id */
  @State private deleteTargetId: number = 0;
  /** 提交中防重复点击 */
  @State private submitting: boolean = false;

  private deleteDialog: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({
      title: $r('app.string.ledger_delete_title'),
      message: $r('app.string.ledger_delete_confirm'),
      danger: true,
      onConfirmed: (): void => {
        this.doDelete(this.deleteTargetId);
      }
    }),
    autoCancel: true,
    customStyle: false
  });

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
    const result: Result<Ledger[]> = await LedgerViewModel.load();
    if (result.ok && result.data !== undefined) {
      this.ledgers = result.data;
      this.currentLedgerId = SettingsService.getCurrentLedgerId();
      this.loadFailed = false;
    } else {
      LogUtil.e(LedgerManagePage.TAG, 'load ledgers failed');
      this.loadFailed = true;
    }
    this.loading = false;
  }

  /** 打开新建弹层（默认图标与第一个色点） */
  private openCreate(): void {
    this.editingId = 0;
    this.inputName = '';
    this.selectedColor = LEDGER_COLOR_CHOICES[this.ledgers.length % LEDGER_COLOR_CHOICES.length];
    this.editorOpen = true;
  }

  /** 打开重命名弹层（回填名称，图标/颜色沿用原值） */
  private openRename(ledger: Ledger): void {
    this.editingId = ledger.id;
    this.inputName = ledger.name;
    this.selectedColor = ledger.color;
    this.editorOpen = true;
  }

  private async submitEditor(): Promise<void> {
    if (this.submitting) {
      return;
    }
    this.submitting = true;
    if (this.editingId === 0) {
      const result: Result<number> =
        await LedgerViewModel.createLedger(this.inputName, IconConstants.DEFAULT_LEDGER_ICON_KEY,
          this.selectedColor);
      if (result.ok) {
        ToastUtil.showRes($r('app.string.ledger_create_success'));
        this.editorOpen = false;
      } else {
        ToastUtil.show(result.message !== undefined ? result.message : '');
      }
    } else {
      const result: Result<boolean> =
        await LedgerViewModel.renameLedger(this.editingId, this.inputName,
          IconConstants.DEFAULT_LEDGER_ICON_KEY, this.selectedColor);
      if (result.ok) {
        ToastUtil.showRes($r('app.string.ledger_rename_success'));
        this.editorOpen = false;
      } else {
        ToastUtil.show(result.message !== undefined ? result.message : '');
      }
    }
    this.submitting = false;
  }

  private async doDelete(id: number): Promise<void> {
    const result: Result<boolean> = await LedgerViewModel.deleteLedger(id);
    if (result.ok) {
      ToastUtil.showRes($r('app.string.toast_delete_success'));
    } else {
      ToastUtil.show(result.message !== undefined ? result.message : '');
    }
  }

  /** 切换使用该账本（F-10.4 全局生效：switchTo 内部持久化 + bump 驱动全站刷新） */
  private async useLedger(ledger: Ledger): Promise<void> {
    if (ledger.id === this.currentLedgerId) {
      return;
    }
    try {
      await LedgerService.switchTo(ledger.id);
      this.currentLedgerId = ledger.id;
      ToastUtil.showRes($r('app.string.ledger_switch_success'));
    } catch (e) {
      const err: Error = e as Error;
      ToastUtil.show(err.message);
    }
  }

  private openDelete(ledger: Ledger): void {
    this.deleteTargetId = ledger.id;
    this.deleteDialog.open();
  }

  build() {
    Column() {
      NavTitleBar({
        title: $r('app.string.page_ledger_manage_title'),
        showBack: true,
        actionText: $r('app.string.ledger_create_action'),
        onBack: (): void => { router.back(); },
        onAction: (): void => { this.openCreate(); }
      })

      if (this.loading) {
        LoadingState({ rows: 3, rowHeight: 64 })
      } else if (this.loadFailed) {
        ErrorState({ onRetry: (): void => { this.load(); } })
      } else if (this.ledgers.length === 0) {
        EmptyState({ title: $r('app.string.common_empty_title') })
      } else {
        this.list()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).bgPage)
    .bindSheet($$this.editorOpen, this.editorSheet(), {
      height: 380,
      dragBar: true,
      backgroundColor: palette(this.isDark).bgElevated,
      showClose: true
    } as SheetOptions)
  }

  @Builder
  private list() {
    List({ space: 0 }) {
      ForEach(this.ledgers, (ledger: Ledger) => {
        ListItem() {
          this.ledgerRow(ledger)
        }
      }, (ledger: Ledger) => 'ledger_' + ledger.id.toString() + '_' +
        ledger.updatedAt.toString())
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .padding({ left: 16, right: 16, top: 8 })
  }

  @Builder
  private ledgerRow(ledger: Ledger) {
    Row({ space: 12 }) {
      Circle()
        .width(12)
        .height(12)
        .fill(ledger.color)

      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text(ledger.name)
            .fontSize($r('app.float.font_body'))
            .fontColor(palette(this.isDark).textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (ledger.id === this.currentLedgerId) {
            Text($r('app.string.ledger_in_use_tag'))
              .fontSize($r('app.float.font_aux'))
              .fontColor(palette(this.isDark).primary)
          }
          if (ledger.isDefault) {
            Text($r('app.string.ledger_default_tag'))
              .fontSize($r('app.float.font_aux'))
              .fontColor(palette(this.isDark).textTertiary)
          }
        }
        .width('100%')

        if (ledger.id !== this.currentLedgerId) {
          Text($r('app.string.ledger_switch_hint'))
            .fontSize($r('app.float.font_aux'))
            .fontColor(palette(this.isDark).primary)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .onClick(() => {
        this.openRename(ledger);
      })

      if (ledger.id !== this.currentLedgerId) {
        Text($r('app.string.ledger_use_action'))
          .fontSize($r('app.float.font_aux'))
          .fontColor(palette(this.isDark).primary)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius($r('app.float.radius_tag'))
          .backgroundColor(palette(this.isDark).primary + '14')
          .onClick(() => {
            this.useLedger(ledger);
          })

        // 默认账本不可删（LedgerService 亦拦截，UI 双保险），删除入口对其隐藏
        if (!ledger.isDefault) {
          Text($r('app.string.common_delete'))
            .fontSize($r('app.float.font_aux'))
            .fontColor(palette(this.isDark).danger)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius($r('app.float.radius_tag'))
            .backgroundColor(palette(this.isDark).danger + '14')
            .onClick(() => {
              this.openDelete(ledger);
            })
        }
      }
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
  }

  /** 新建 / 重命名弹层：名称输入 + 色点（简洁化：无图标选择） */
  @Builder
  private editorSheet() {
    Column() {
      Text(this.editingId === 0
        ? $r('app.string.ledger_create_title')
        : $r('app.string.ledger_rename_title'))
        .fontSize($r('app.float.font_title'))
        .fontWeight(FontWeight.Medium)
        .fontColor(palette(this.isDark).textPrimary)
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 8 })

      TextInput({
        text: this.inputName,
        placeholder: $r('app.string.ledger_name_hint')
      })
        .type(InputType.Normal)
        .maxLength(AppConstants.LEDGER_NAME_MAX_LENGTH)
        .fontSize($r('app.float.font_body'))
        .fontColor(palette(this.isDark).textPrimary)
        .placeholderColor(palette(this.isDark).textTertiary)
        .backgroundColor(palette(this.isDark).bgCard)
        .borderRadius($r('app.float.radius_tag'))
        .margin({ left: 20, right: 20 })
        .onChange((value: string) => {
          this.inputName = value;
        })

      Text($r('app.string.ledger_color_label'))
        .fontSize($r('app.float.font_aux'))
        .fontColor(palette(this.isDark).textSecondary)
        .width('100%')
        .padding({ left: 20, right: 20, top: 14, bottom: 6 })

      Row({ space: 14 }) {
        ForEach(LEDGER_COLOR_CHOICES, (color: string) => {
          Text('')
            .width(28)
            .height(28)
            .borderRadius(14)
            .backgroundColor(color)
            .border({
              width: this.selectedColor === color ? 3 : 0,
              color: palette(this.isDark).textPrimary
            })
            .onClick(() => {
              this.selectedColor = color;
            })
        }, (color: string) => 'ledger_color_' + color)
      }
      .width('100%')
      .padding({ left: 20, right: 20 })

      Blank()

      Button($r('app.string.common_confirm'))
        .width('100%')
        .height(44)
        .margin({ left: 20, right: 20, bottom: 16 })
        .borderRadius($r('app.float.radius_button'))
        .backgroundColor(palette(this.isDark).primary)
        .fontColor('#FFFFFF')
        .enabled(!this.submitting && this.inputName.trim().length > 0)
        .onClick(() => {
          this.submitEditor();
        })
    }
    .width('100%')
    .height('100%')
  }
}
