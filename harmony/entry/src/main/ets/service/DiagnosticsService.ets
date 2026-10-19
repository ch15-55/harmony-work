/**
 * 本地诊断导出：仅导出版本、运行状态与脱敏技术日志，绝不读取账本业务表。
 */
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConstants } from '../constants/AppConstants';
import { CURRENT_SCHEMA_VERSION } from './SchemaConstants';
import { DatabaseManager } from './DatabaseManager';
import { SettingsService } from './SettingsService';
import { ExportOutcome, ExportStatus } from './ExportService';
import { FileUtil } from '../utils/FileUtil';
import { LogEntry, LogUtil } from '../utils/LogUtil';

class DiagnosticsReport {
  public app: string = AppConstants.BACKUP_APP_NAME;
  public appVersion: string = '1.0.0';
  public schemaVersion: number = CURRENT_SCHEMA_VERSION;
  public exportedAt: number = 0;
  public databaseReady: boolean = false;
  public databaseReadOnly: boolean = false;
  public currentLedgerId: number = 0;
  public logs: LogEntry[] = [];
}

export class DiagnosticsService {
  private static readonly TAG: string = 'DiagnosticsService';
  private static readonly FILE_PREFIX: string = '轻账本_诊断_';

  /** 系统 Picker 保存，不请求存储权限；用户取消返回 cancelled。 */
  public static async exportViaPicker(context: common.UIAbilityContext): Promise<ExportOutcome> {
    const outcome: ExportOutcome = new ExportOutcome();
    LogUtil.i(DiagnosticsService.TAG, 'diagnostic export requested');
    const report: DiagnosticsReport = new DiagnosticsReport();
    const db: DatabaseManager = DatabaseManager.getInstance();
    report.exportedAt = Date.now();
    report.databaseReady = db.isReady();
    report.databaseReadOnly = db.isReadOnly();
    report.currentLedgerId = SettingsService.getCurrentLedgerId();
    report.logs = LogUtil.snapshot();

    const fileName: string = DiagnosticsService.FILE_PREFIX + DiagnosticsService.timestamp(report.exportedAt) + '.json';
    const sandboxFile: string = FileUtil.sandboxPath(context, 'diagnostics', fileName);
    try {
      const encoder: util.TextEncoder = new util.TextEncoder();
      FileUtil.writeBytes(context, sandboxFile, encoder.encodeInto(JSON.stringify(report)));
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      LogUtil.fail(DiagnosticsService.TAG, 'temp_file', err);
      outcome.status = ExportStatus.FAILED;
      outcome.failurePoint = 'temp_file';
      return outcome;
    }

    try {
      const pickerInstance: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSaveOptions = {
        newFileNames: [fileName],
        fileSuffixChoices: ['.json']
      };
      const uris: Array<string> = await pickerInstance.save(options);
      if (uris.length === 0) {
        outcome.status = ExportStatus.CANCELLED;
        return outcome;
      }
      FileUtil.copyToUri(context, sandboxFile, uris[0]);
      outcome.status = ExportStatus.SAVED;
      outcome.count = report.logs.length;
      outcome.uri = uris[0];
      LogUtil.i(DiagnosticsService.TAG, 'diagnostic export saved');
      return outcome;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      LogUtil.fail(DiagnosticsService.TAG, 'picker_or_copy', err);
      outcome.status = ExportStatus.FAILED;
      outcome.failurePoint = 'picker_or_copy';
      return outcome;
    } finally {
      FileUtil.deleteFile(sandboxFile);
    }
  }

  private static timestamp(time: number): string {
    const date: Date = new Date(time);
    return date.getFullYear().toString() + DiagnosticsService.two(date.getMonth() + 1) +
      DiagnosticsService.two(date.getDate()) + '_' + DiagnosticsService.two(date.getHours()) +
      DiagnosticsService.two(date.getMinutes()) + DiagnosticsService.two(date.getSeconds());
  }

  private static two(value: number): string {
    return value < 10 ? '0' + value.toString() : value.toString();
  }
}
