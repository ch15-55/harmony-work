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
  /**
   * 极简模式：输入框去除底色/圆角，融入外层分组卡片（行内编辑观感）。
   * 默认 false 保持独立卡片外观。
   */
  @Prop plain: boolean = false;
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
        .backgroundColor(this.plain ? Color.Transparent : palette(this.isDark).bgElevated)
        .borderRadius(this.plain ? 0 : $r('app.float.radius_button'))
        .width('100%')
        .height(this.plain ? 36 : 44)
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
