/** 本地诊断导出页。导出内容不含账目、备注、账户名或任何密码数据。 */
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { palette } from '../constants/ThemeConstants';
import { AppStorageKeys } from '../constants/AppConstants';
import { DiagnosticsService } from '../service/DiagnosticsService';
import { ExportStatus } from '../service/ExportService';
import { NavTitleBar } from '../components/common/NavTitleBar';
import { ToastUtil } from '../utils/ToastUtil';

@Entry
@Component
struct DiagnosticsPage {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  @State private busy: boolean = false;

  private async exportDiagnostics(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const outcome = await DiagnosticsService.exportViaPicker(this.context());
      if (outcome.status === ExportStatus.SAVED) {
        ToastUtil.showRes($r('app.string.diagnostics_export_success'));
      } else if (outcome.status === ExportStatus.FAILED) {
        ToastUtil.showRes($r('app.string.diagnostics_export_failed'));
      }
    } finally {
      this.busy = false;
    }
  }

  private context(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  build() {
    Column() {
      NavTitleBar({
        title: $r('app.string.page_diagnostics_title'),
        showBack: true,
        onBack: (): void => { router.back(); }
      })
      Column({ space: 16 }) {
        Text($r('app.string.diagnostics_hint'))
          .fontSize($r('app.float.font_body'))
          .fontColor(palette(this.isDark).textSecondary)
          .width('100%')
        Text(this.busy ? $r('app.string.common_loading') : $r('app.string.diagnostics_export_action'))
          .fontSize($r('app.float.font_body'))
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .width('100%')
          .height(48)
          .borderRadius($r('app.float.radius_button'))
          .backgroundColor(this.busy ? palette(this.isDark).textTertiary : palette(this.isDark).primary)
          .onClick((): void => { this.exportDiagnostics(); })
      }
      .width('100%')
      .padding($r('app.float.card_padding'))
      .margin(16)
      .backgroundColor(palette(this.isDark).bgCard)
      .borderRadius($r('app.float.radius_card'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).bgPage)
  }
}
