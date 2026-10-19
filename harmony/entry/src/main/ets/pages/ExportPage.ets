/**
 * 模块职责：导出数据页（架构 T05 / PRD F-6.1 / F-6.2）。
 * - 范围选择：本月 / 全部（默认本月）
 * - 经 MineViewModel.exportCsv → ExportService.exportViaPicker
 *   （DocumentViewPicker 免权限保存，UTF-8 BOM，9 字段 CSV）
 * - 用户取消保存：ok=true 且 data 为空，静默处理
 */
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { palette } from '../constants/ThemeConstants';
import { AppStorageKeys, Result } from '../constants/AppConstants';
import { DateUtil } from '../utils/DateUtil';
import { MineViewModel } from '../viewmodel/MineViewModel';
import { NavTitleBar } from '../components/common/NavTitleBar';
import { ToastUtil } from '../utils/ToastUtil';

@Entry
@Component
struct ExportPage {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  @State private exporting: boolean = false;
  /** true=本月，false=全部 */
  @State private isCurrentMonth: boolean = true;

  private async doExport(): Promise<void> {
    if (this.exporting) {
      return;
    }
    this.exporting = true;
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const monthKey: string = this.isCurrentMonth ? DateUtil.monthKey(DateUtil.now()) : 'ALL';
      const result: Result<number> = await MineViewModel.exportCsv(context, monthKey);
      if (result.ok) {
        if (result.data !== undefined) {
          // saved：成功 Toast 含条数（export_success_count，%d 占位）
          ToastUtil.show(context.resourceManager
            .getStringSync($r('app.string.export_success_count'), result.data));
        }
        // cancelled：用户取消，静默无 Toast（架构 R8）
      } else {
        // failed：优先用 AlertDialog 展示完整错误码（含 BusinessError.code），便于精准定位
        if (result.detail !== undefined && result.detail.length > 0) {
          AlertDialog.show({
            title: '导出失败',
            message: result.detail + (result.message !== undefined ? '\n\n' + result.message : ''),
            confirm: { value: '知道了', action: (): void => {} }
          });
        } else {
          ToastUtil.show(result.message !== undefined && result.message.length > 0
            ? result.message
            : getContext(this).resourceManager.getStringSync($r('app.string.toast_save_failed')));
        }
      }
    } finally {
      this.exporting = false;
    }
  }

  build() {
    Column() {
      NavTitleBar({
        title: $r('app.string.page_export_title'),
        showBack: true,
        onBack: (): void => {
          router.back();
        }
      })

      Scroll() {
        Column({ space: 12 }) {
          Text($r('app.string.export_month_hint'))
            .fontSize($r('app.float.font_aux'))
            .fontColor(palette(this.isDark).textSecondary)
            .width('100%')
            .padding({ left: 4, top: 4 })

          this.rangeCard()

          Button($r('app.string.export_action'))
            .width('100%')
            .height(48)
            .borderRadius($r('app.float.radius_button'))
            .backgroundColor(palette(this.isDark).primary)
            .fontColor('#FFFFFF')
            .enabled(!this.exporting)
            .onClick((): void => {
              this.doExport();
            })
        }
        .width('100%')
        .padding(16)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).bgPage)
  }

  @Builder
  private rangeCard() {
    Column() {
      this.rangeRow($r('app.string.export_range_current'), true, (): void => {
        this.isCurrentMonth = true;
      })
      Divider()
        .color(palette(this.isDark).divider)
        .strokeWidth(1)
      this.rangeRow($r('app.string.export_range_all'), false, (): void => {
        this.isCurrentMonth = false;
      })
    }
    .width('100%')
    .padding($r('app.float.card_padding'))
    .backgroundColor(palette(this.isDark).bgCard)
    .borderRadius($r('app.float.radius_card'))
  }

  /** value 为该行代表的取值；选中态内部比较 this.isCurrentMonth（响应式，勿改为传布尔参数） */
  @Builder
  private rangeRow(label: Resource, value: boolean, onClick: () => void) {
    Row() {
      Text(label)
        .fontSize($r('app.float.font_body'))
        .fontColor(palette(this.isDark).textPrimary)
        .layoutWeight(1)
      if (this.isCurrentMonth === value) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([palette(this.isDark).primary])
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 4, right: 4 })
    .onClick(onClick)
  }
}
