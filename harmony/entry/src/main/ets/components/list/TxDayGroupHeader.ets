/**
 * 模块职责：日分组头（架构 T04 list/TxDayGroupHeader）。
 * - 左：分组标签（今天/昨天/MM-DD 周X，由 DateUtil.dayLabel 产出，随组传入）
 * - 右：当日收入（绿 +）/ 支出（红 -）合计；当日无收入/支出时不渲染对应项
 * 说明：Resource 不能与 string 直接用 + 拼接，标签文案先经 resourceManager 取值。
 */
import { common } from '@kit.AbilityKit';
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';
import { TxGroup } from '../../model/StatsModels';
import { MoneyUtil } from '../../utils/MoneyUtil';

@Component
export struct TxDayGroupHeader {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 日分组（label + income + expense） */
  @Prop group: TxGroup = new TxGroup();

  /** 资源 → 纯文本 */
  private resText(res: Resource): string {
    const context: common.Context = getContext(this) as common.Context;
    return context.resourceManager.getStringSync(res);
  }

  build() {
    Row({ space: 8 }) {
      // 日期强调竖条
      Column()
        .width(3)
        .height(14)
        .borderRadius($r('app.float.radius_tag'))
        .backgroundColor(palette(this.isDark).primary)

      Text(this.group.label)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(palette(this.isDark).textSecondary)
        .layoutWeight(1)

      if (this.group.income > 0) {
        Text(this.resText($r('app.string.stats_type_income')) + ' +' +
          MoneyUtil.display(this.group.income))
          .fontSize($r('app.float.font_aux'))
          .fontColor(palette(this.isDark).income)
          .fontFeature('"tnum" on')
      }
      if (this.group.expense > 0) {
        Text(this.resText($r('app.string.stats_type_expense')) + ' -' +
          MoneyUtil.display(this.group.expense))
          .fontSize($r('app.float.font_aux'))
          .fontColor(palette(this.isDark).expense)
          .fontFeature('"tnum" on')
      }
    }
    .width('100%')
    .padding({ top: 16, bottom: 8, left: 12, right: 12 })
  }
}
