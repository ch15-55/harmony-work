/**
 * 模块职责：关于页（架构 T05 / PRD F-7.9）。
 * 审核关键：显著展示「完全离线、不收集不上传、无第三方库」，并给出版本号、
 * 隐私政策与用户协议入口（反馈邮箱仅保留在隐私政策/用户协议文本中）。
 */
import { router } from '@kit.ArkUI';
import { bundleManager } from '@kit.AbilityKit';
import { palette } from '../constants/ThemeConstants';
import { AppStorageKeys } from '../constants/AppConstants';
import { RouteConstants } from '../constants/RouteConstants';
import { NavTitleBar } from '../components/common/NavTitleBar';
import { SettingItem } from '../components/common/SettingItem';
import { LogUtil } from '../utils/LogUtil';

@Entry
@Component
struct AboutPage {
  /** 页面转场：二级页统一右侧滑入（v1.2 美化） */
  pageTransition() {
    PageTransitionEnter({ type: RouteType.Push, duration: 300, curve: Curve.EaseOut })
      .slide(SlideEffect.Right)
    PageTransitionExit({ type: RouteType.Pop, duration: 280, curve: Curve.EaseIn })
      .slide(SlideEffect.Right)
  }

  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  @State private version: string = '';

  aboutToAppear(): void {
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      this.version = info.versionName;
    } catch (e) {
      LogUtil.e('AboutPage', 'getBundleInfo failed');
      this.version = '';
    }
  }

  private go(url: string): void {
    router.pushUrl({ url: url })
      .catch((e: Object) => {
        LogUtil.e('AboutPage', 'pushUrl failed: ' + url);
      });
  }

  build() {
    Column() {
      NavTitleBar({
        title: $r('app.string.page_about_title'),
        showBack: true,
        onBack: (): void => {
          router.back();
        }
      })

      Scroll() {
        Column({ space: 12 }) {
          // 应用名 + 版本 + 一句话简介
          Column({ space: 6 }) {
            Text($r('app.string.app_name'))
              .fontSize($r('app.float.font_title'))
              .fontWeight(FontWeight.Bold)
              .fontColor(palette(this.isDark).textPrimary)
            Row({ space: 8 }) {
              Text($r('app.string.about_version_label'))
                .fontSize($r('app.float.font_aux'))
                .fontColor(palette(this.isDark).textSecondary)
              Text(this.version)
                .fontSize($r('app.float.font_aux'))
                .fontColor(palette(this.isDark).textSecondary)
            }
            .width('100%')
            Text($r('app.string.app_slogan'))
              .fontSize($r('app.float.font_aux'))
              .fontColor(palette(this.isDark).textTertiary)
              .width('100%')
              .margin({ top: 4 })
          }
          .width('100%')
          .padding($r('app.float.card_padding'))
          .backgroundColor(palette(this.isDark).bgCard)
          .borderRadius($r('app.float.radius_card'))

          // 离线 / 无 SDK 声明
          Column({ space: 8 }) {
            Text($r('app.string.about_offline_title'))
              .fontSize($r('app.float.font_body'))
              .fontWeight(FontWeight.Medium)
              .fontColor(palette(this.isDark).textPrimary)
            Text($r('app.string.about_offline_desc'))
              .fontSize($r('app.float.font_aux'))
              .fontColor(palette(this.isDark).textSecondary)
            Text($r('app.string.about_nosdk_title'))
              .fontSize($r('app.float.font_body'))
              .fontWeight(FontWeight.Medium)
              .fontColor(palette(this.isDark).textPrimary)
              .margin({ top: 4 })
            Text($r('app.string.about_nosdk_desc'))
              .fontSize($r('app.float.font_aux'))
              .fontColor(palette(this.isDark).textSecondary)
          }
          .width('100%')
          .padding($r('app.float.card_padding'))
          .backgroundColor(palette(this.isDark).bgCard)
          .borderRadius($r('app.float.radius_card'))

          // 入口组
          Column() {
            SettingItem({
              iconKey: 'ic_common_book',
              title: $r('app.string.about_privacy_entry'),
              showDivider: true,
              onItemClick: (): void => { this.go(RouteConstants.PRIVACY_POLICY); }
            })
            SettingItem({
              iconKey: 'ic_common_book',
              title: $r('app.string.about_agreement_entry'),
              showDivider: false,
              onItemClick: (): void => { this.go(RouteConstants.USER_AGREEMENT); }
            })
          }
          .width('100%')
          .borderRadius($r('app.float.radius_card'))
          .backgroundColor(palette(this.isDark).bgCard)
          .clip(true)

          Text($r('app.string.about_copyright'))
            .fontSize($r('app.float.font_aux'))
            .fontColor(palette(this.isDark).textTertiary)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 16, bottom: 24 })
        }
        .width('100%')
        .padding({ top: 8, bottom: 16 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).bgPage)
  }
}
