/**
 * 模块职责：首次启动隐私弹窗页（架构 2.4 / PRD F-9.1，T01 核心）。
 *
 * 设计要点（为什么是「独立页面伪装弹窗」）：
 * 1. 视觉上：整页遮罩色 + 居中 24vp 圆角卡片，观感等同弹窗；
 * 2. 路由上：它是独立页面，主界面（Index）从未被渲染过，不存在
 *    「先看到主界面再补弹窗」的绕过口子；
 * 3. 不可跳过：onBackPress() 恒返回 true，返回键/侧滑手势全部被拦截；
 * 4. 「不同意并退出」调用 terminateSelf() 真实终止进程回桌面，
 *    不做任何「假装退出」；
 * 5. 默认无勾选态：必须显式点击「同意并继续」。
 *
 * 时序（架构 6.1 ①）：同意 → 写 Preferences → DatabaseManager.init（建表+预置）
 * → router.replaceUrl 进入主界面（replace 而非 push，杜绝回退到隐私页）。
 */
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { palette } from '../constants/ThemeConstants';
import { AppStorageKeys } from '../constants/AppConstants';
import { RouteConstants } from '../constants/RouteConstants';
import { SettingsService } from '../service/SettingsService';
import { DatabaseManager } from '../service/DatabaseManager';
import { ToastUtil } from '../utils/ToastUtil';
import { LogUtil } from '../utils/LogUtil';

@Entry
@Component
struct PrivacyPage {
  private static readonly TAG: string = 'PrivacyPage';
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 同意处理中标记：防止重复点击造成数据库重复初始化 */
  @State private submitting: boolean = false;
  /** 摘要 4 条（文案走 string.json，与隐私政策全文一致） */
  @State private summaryKeys: Resource[] = [
    $r('app.string.privacy_point_collect'),
    $r('app.string.privacy_point_storage'),
    $r('app.string.privacy_point_network'),
    $r('app.string.privacy_point_sdk')
  ];

  /**
   * 完全拦截返回键与返回手势。
   * 返回 true 表示本页面已消费该事件，系统不再执行默认返回。
   */
  onBackPress(): boolean {
    return true;
  }

  /** 「同意并继续」：写 Preferences → 初始化数据库 → replaceUrl 进主界面 */
  private async onAgree(): Promise<void> {
    if (this.submitting) {
      return;
    }
    this.submitting = true;
    SettingsService.setPrivacyAgreed(true);
    try {
      const uiContext: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      await DatabaseManager.getInstance().init(uiContext);
      await router.replaceUrl({ url: RouteConstants.INDEX });
    } catch (e) {
      // 建表/预置失败：回滚同意状态？不回滚——保留同意标记，进入主界面后由页面
      // ErrorState 呈现；此处提示失败原因，避免无声卡死
      this.submitting = false;
      LogUtil.e(PrivacyPage.TAG, 'agree flow failed');
      ToastUtil.showRes($r('app.string.toast_operate_failed'));
    }
  }

  /** 「不同意并退出」：真实终止进程回桌面（审核硬要求） */
  private async onDisagree(): Promise<void> {
    const uiContext: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    try {
      await uiContext.terminateSelf();
    } catch (e) {
      // terminateSelf 失败极罕见；兜底记录日志，不伪造退出成功
      LogUtil.e(PrivacyPage.TAG, 'terminateSelf failed');
    }
  }

  /** 查看隐私政策全文 */
  private goPrivacyPolicy(): void {
    router.pushUrl({ url: RouteConstants.PRIVACY_POLICY })
      .catch((e: Object) => {
        LogUtil.e(PrivacyPage.TAG, 'pushUrl PRIVACY_POLICY failed');
      });
  }

  /** 查看用户协议全文 */
  private goUserAgreement(): void {
    router.pushUrl({ url: RouteConstants.USER_AGREEMENT })
      .catch((e: Object) => {
        LogUtil.e(PrivacyPage.TAG, 'pushUrl USER_AGREEMENT failed');
      });
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 弹窗卡片（85% 宽，24vp 顶部圆角语义→整卡 24vp）
      Column() {
        // 标题
        Text($r('app.string.privacy_dialog_title'))
          .fontSize($r('app.float.font_title'))
          .fontWeight(FontWeight.Bold)
          .fontColor(palette(this.isDark).textPrimary)
          .margin({ top: 24 })

        Text($r('app.string.privacy_dialog_subtitle'))
          .fontSize($r('app.float.font_aux'))
          .fontColor(palette(this.isDark).textSecondary)
          .margin({ top: 6 })

        // 摘要 4 条
        Column({ space: 12 }) {
          ForEach(this.summaryKeys, (item: Resource) => {
            Row({ space: 8 }) {
              Text('·')
                .fontSize($r('app.float.font_body'))
                .fontWeight(FontWeight.Bold)
                .fontColor(palette(this.isDark).primary)
              Text(item)
                .fontSize($r('app.float.font_body'))
                .fontColor(palette(this.isDark).textPrimary)
                .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }, (item: Resource) => JSON.stringify(item))
        }
        .margin({ top: 18 })
        .padding($r('app.float.card_padding'))
        .width('100%')
        .borderRadius($r('app.float.radius_button'))
        .backgroundColor(palette(this.isDark).bgPage)

        // 全文链接（只放链接不复制全文，避免两处文本不一致，架构 2.5）
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          Text($r('app.string.privacy_links_tip'))
            .fontSize($r('app.float.font_aux'))
            .fontColor(palette(this.isDark).textSecondary)
          Text($r('app.string.privacy_policy_name'))
            .fontSize($r('app.float.font_aux'))
            .fontColor(palette(this.isDark).primary)
            .onClick(() => {
              this.goPrivacyPolicy();
            })
          Text($r('app.string.privacy_and'))
            .fontSize($r('app.float.font_aux'))
            .fontColor(palette(this.isDark).textSecondary)
          Text($r('app.string.privacy_agreement_name'))
            .fontSize($r('app.float.font_aux'))
            .fontColor(palette(this.isDark).primary)
            .onClick(() => {
              this.goUserAgreement();
            })
        }
        .margin({ top: 14 })
        .width('100%')

        // 主按钮：同意并继续
        Text($r('app.string.privacy_btn_agree'))
          .fontSize($r('app.float.font_body'))
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ top: 13, bottom: 13 })
          .borderRadius($r('app.float.radius_button'))
          .linearGradient({
            angle: 135,
            colors: [[palette(this.isDark).gradStart, 0], [palette(this.isDark).gradEnd, 1]]
          })
          .opacity(this.submitting ? 0.6 : 1)
          .margin({ top: 22 })
          .onClick(() => {
            this.onAgree();
          })

        // 次按钮：不同意并退出（真实退出）
        Text($r('app.string.privacy_btn_disagree'))
          .fontSize($r('app.float.font_body'))
          .fontColor(palette(this.isDark).textSecondary)
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          .margin({ top: 10 })
          .onClick(() => {
            this.onDisagree();
          })

        Blank().height(20)
      }
      .width('88%')
      .padding({ left: 20, right: 20 })
      .backgroundColor(palette(this.isDark).bgCard)
      .borderRadius($r('app.float.radius_sheet'))
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).mask)
  }
}
