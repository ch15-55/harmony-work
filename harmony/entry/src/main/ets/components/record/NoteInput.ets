/**
 * 模块职责：备注输入框（架构 T04 record/NoteInput）。
 * - TextInput + maxLength(100)，右上角字数计数（含超限前的红色预警由
 *   颜色切换体现：≥80 变警示色）
 * - 输入即回调 onNoteChange（页面持有状态，本组件不做持久化）
 */
import { palette } from '../../constants/ThemeConstants';
import { AppConstants, AppStorageKeys } from '../../constants/AppConstants';

@Component
export struct NoteInput {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 当前备注文本 */
  @Prop note: string = '';
  /** 输入回调 */
  onNoteChange?: (note: string) => void;

  /** 字数计数颜色：接近上限转警示色 */
  private counterColor(): string {
    if (this.note.length >= AppConstants.MAX_NOTE_LENGTH - 20) {
      return palette(this.isDark).warning;
    }
    return palette(this.isDark).textTertiary;
  }

  build() {
    Column({ space: 4 }) {
      TextInput({ text: this.note, placeholder: $r('app.string.record_note_hint') })
        .fontSize($r('app.float.font_body'))
        .fontColor(palette(this.isDark).textPrimary)
        .placeholderColor(palette(this.isDark).textTertiary)
        .placeholderFont({ size: 14 })
        .maxLength(AppConstants.MAX_NOTE_LENGTH)
        .backgroundColor(palette(this.isDark).bgElevated)
        .borderRadius($r('app.float.radius_button'))
        .width('100%')
        .height(44)
        .onChange((value: string) => {
          if (this.onNoteChange !== undefined) {
            this.onNoteChange(value);
          }
        })

      Text(this.note.length.toString() + '/' + AppConstants.MAX_NOTE_LENGTH.toString())
        .fontSize($r('app.float.font_aux'))
        .fontColor(this.counterColor())
        .width('100%')
        .textAlign(TextAlign.End)
    }
    .width('100%')
  }
}
