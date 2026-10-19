/**
 * 模块职责：首页资产总览大卡（架构 T04 home/AssetCard）。
 * - 渐变主色背景，白字
 * - 总资产大字（font_display hero 数字，即净资产）+ 信用卡欠款一行明细
 * - 右上角眼睛：金额掩码切换（状态由页面持久化，本组件仅回调）
 * - 金额展示统一走 MoneyUtil（÷100 单点收口）
 * - v1.2 美化：渐变卡文字色全部走色板（textOnGradient*），禁止组件内硬编码
 */
import { palette, cardShadow } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';
import { NetAssetSummary } from '../../model/StatsModels';
import { MoneyUtil } from '../../utils/MoneyUtil';
import { common } from '@kit.AbilityKit';

@Component
export struct AssetCard {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 资产汇总（ViewModel 实时计算结果） */
  @Prop summary: NetAssetSummary = new NetAssetSummary();
  /** 是否隐藏金额（全局掩码状态） */
  @Prop hidden: boolean = false;
  /** 眼睛切换回调（页面持久化） */
  onToggleHide?: () => void;

  /** 资源 → 纯文本（Resource 不能与 string 直接用 + 拼接） */
  private resText(res: Resource): string {
    const context: common.Context = getContext(this) as common.Context;
    return context.resourceManager.getStringSync(res);
  }

  /** 掩码或金额文本（掩码文案取自资源，Resource 不能直接当 string 用） */
  private moneyText(fen: number): string {
    if (this.hidden) {
      const context: common.Context = getContext(this) as common.Context;
      return context.resourceManager.getStringSync($r('app.string.common_amount_mask'));
    }
    return MoneyUtil.display(fen);
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text($r('app.string.home_asset_total'))
          .fontSize($r('app.float.font_aux'))
          .fontColor(palette(this.isDark).textOnGradientSecondary)
        // 眼睛：掩码切换（线条风格系统符号，隐藏态带斜杠）
        SymbolGlyph(this.hidden ? $r('sys.symbol.eye_slash') : $r('sys.symbol.eye'))
          .fontSize(22)
          .fontColor([palette(this.isDark).textOnGradientSecondary])
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .onClick(() => {
            if (this.onToggleHide !== undefined) {
              this.onToggleHide();
            }
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      // hero 数字：总资产即净资产（34fp 展示级字号，等宽数字防跳动）
      Text(this.moneyText(this.summary.netAsset))
        .fontSize($r('app.float.font_display'))
        .fontWeight(FontWeight.Bold)
        .fontColor(palette(this.isDark).textOnGradient)
        .fontFeature('"tnum" on')
        .width('100%')

      // 仅保留信用卡欠款一行明细（hero 已是净资产，不再重复展示）
      Row({ space: 8 }) {
        Text(this.resText($r('app.string.home_asset_debt')))
          .fontSize($r('app.float.font_aux'))
          .fontColor(palette(this.isDark).textOnGradientSecondary)
        Text(this.moneyText(this.summary.totalDebt))
          .fontSize($r('app.float.font_aux'))
          .fontColor(palette(this.isDark).textOnGradient)
          .fontFeature('"tnum" on')
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .borderRadius($r('app.float.radius_card'))
    .linearGradient({
      angle: 135,
      colors: [[palette(this.isDark).gradStart, 0], [palette(this.isDark).gradEnd, 1]]
    })
    .shadow(cardShadow(this.isDark))
  }
}
