/**
 * 模块职责：隐私政策全文页（架构 T01，F-7.7 双入口之一）。
 * 文本单一真相源：rawfile/privacy.md（与 AGC 托管一致，架构 2.5）。
 * 渲染策略：读取原文 → 去除 Markdown 标记后以纯文本呈现（v1.0 无 Markdown 渲染器）。
 */
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { router } from '@kit.ArkUI';
import { palette } from '../constants/ThemeConstants';
import { AppStorageKeys } from '../constants/AppConstants';
import { NavTitleBar } from '../components/common/NavTitleBar';

@Entry
@Component
struct PrivacyPolicyPage {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  @State private content: string = '';

  aboutToAppear(): void {
    this.loadContent();
  }

  private loadContent(): void {
    // 直接经 resourceManager 读取 rawfile（pages 层不触碰 fileIo/数据库，架构 3.1）
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const bytes: Uint8Array = ctx.resourceManager.getRawFileContentSync('privacy.md');
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    this.content = this.toPlainText(decoder.decodeToString(bytes));
  }

  /** 去除 Markdown 标记符号（#、**、TODO 注释），保留纯文本可读性 */
  private toPlainText(md: string): string {
    let text: string = md;
    text = text.split('**').join('');
    text = text.split('#').join('');
    // 去除源文件中的上架待办注释行（<!-- ... -->）
    while (text.indexOf('<!--') >= 0) {
      const start: number = text.indexOf('<!--');
      const end: number = text.indexOf('-->');
      if (end < 0 || end <= start) {
        break;
      }
      text = text.substring(0, start) + text.substring(end + 3);
    }
    return text.trim();
  }

  build() {
    Column() {
      NavTitleBar({
        title: $r('app.string.page_privacy_policy_title'),
        onBack: () => {
          router.back();
        }
      })

      if (this.content.length === 0) {
        Column() {
          Text($r('app.string.privacy_load_failed'))
            .fontSize($r('app.float.font_body'))
            .fontColor(palette(this.isDark).textSecondary)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      } else {
        Scroll() {
          Text(this.content)
            .fontSize($r('app.float.font_body'))
            .fontColor(palette(this.isDark).textPrimary)
            .lineHeight(22)
            .padding($r('app.float.page_padding'))
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).bgPage)
  }
}
