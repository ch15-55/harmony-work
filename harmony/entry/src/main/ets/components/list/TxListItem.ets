/**
 * 模块职责：流水条目（架构 T04 list/TxListItem）。
 * - 左：分类淡色圆 + 系统矢量符号（与记账页同一图标语言）；转账用主色淡底双向箭头
 * - 中：分类名 + 副行（账户 · 备注 · 时间，空段自动剔除）
 * - 右：金额（收入 +绿 / 支出 红 / 转账 主色），金额文本统一 MoneyUtil
 * - 左滑编辑/删除：swipeAction 是 ListItem 的专属属性，无法挂在本组件根 Row 上，
 *   故由页面在 ListItem 上声明（宽度复用本文件导出的 SWIPE_BUTTON_WIDTH），
 *   本组件只负责条目内容与点击；swipeEnabled 保留给调用方标识是否可左滑。
 */
import { palette, cardShadow, cardBorderWidth } from '../../constants/ThemeConstants';
import { AppStorageKeys, TxType } from '../../constants/AppConstants';
import { TxDisplayItem } from '../../model/StatsModels';
import { MoneyUtil } from '../../utils/MoneyUtil';
import { DateUtil } from '../../utils/DateUtil';
import { categorySymbolByName } from '../../constants/IconConstants';
import { common } from '@kit.AbilityKit';

/** 左滑操作按钮宽度（vp）：页面在 ListItem.swipeAction 中复用，保证视觉一致 */
export const SWIPE_BUTTON_WIDTH: number = 64;

@Component
export struct TxListItem {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 展示币种 / 汇率：订阅后切币种即可刷新金额文案（不必等待整页重建） */
  @StorageLink(AppStorageKeys.DISPLAY_CURRENCY) displayCurrency: string = '¥';
  @StorageLink(AppStorageKeys.DISPLAY_RATE) displayRate: number = 1;
  /** 展示 DTO（ViewModel 经 TxDisplayMapper 关联） */
  @Prop item: TxDisplayItem = new TxDisplayItem();
  /** 是否启用左滑操作（首页卡片复用时关闭；左滑本体由页面 ListItem 声明） */
  @Prop swipeEnabled: boolean = true;
  /** 是否以卡片样式渲染（明细页列表流用；首页/分类页由各自容器管理背景，仅用内部 badge） */
  @Prop showCard: boolean = false;
  /** 条目点击（进详情） */
  onItemClick?: (txId: number) => void;

  /** 分类色（转账/缺分类兜底） */
  private blockColor(): string {
    if (this.item.tx.type === TxType.TRANSFER) {
      return palette(this.isDark).primary;
    }
    return this.item.categoryColor;
  }

  /** 分类符号图标：转账用双向箭头，其余按分类名查预置映射（自定义分类回退 more） */
  private badgeSymbol(): Resource {
    if (this.item.tx.type === TxType.TRANSFER) {
      return $r('sys.symbol.arrow_left_arrow_right');
    }
    return categorySymbolByName(this.item.categoryName);
  }

  /** 主标题（转账显示「转账」，其余分类名） */
  private titleText(): string {
    if (this.item.tx.type === TxType.TRANSFER) {
      const context: common.Context = getContext(this) as common.Context;
      return context.resourceManager.getStringSync($r('app.string.record_type_transfer'));
    }
    return this.item.categoryName;
  }

  /** 金额文本：收入带 +，支出/转账不带（色彩区分）；币种与汇率取订阅值，与首页汇总同口径 */
  private amountText(): string {
    if (this.item.tx.type === TxType.INCOME) {
      return '+' + MoneyUtil.displayIn(this.item.tx.amount, this.displayCurrency, this.displayRate);
    }
    return MoneyUtil.displayIn(this.item.tx.amount, this.displayCurrency, this.displayRate);
  }

  /** 金额颜色 */
  private amountColor(): string {
    if (this.item.tx.type === TxType.INCOME) {
      return palette(this.isDark).income;
    }
    if (this.item.tx.type === TxType.TRANSFER) {
      return palette(this.isDark).transfer;
    }
    return palette(this.isDark).expense;
  }

  /** 副行：账户 · 备注 · 时间（空段剔除，避免连续分隔符） */
  private subtitle(): string {
    const segments: string[] = [];
    if (this.item.accountName.length > 0) {
      segments.push(this.item.accountName);
    }
    if (this.item.tx.note.length > 0) {
      segments.push(this.item.tx.note);
    }
    // 只记录日期（本地 0 点）时不展示 00:00，避免把「无时分」误读成午夜交易
    if (!DateUtil.isDateOnly(this.item.tx.txDate)) {
      segments.push(DateUtil.formatTime(this.item.tx.txDate));
    }    let text: string = '';
    for (let i = 0; i < segments.length; i++) {
      if (i > 0) {
        text += ' · ';
      }
      text += segments[i];
    }
    return text;
  }

  build() {
    Row({ space: 12 }) {
      // 中性灰圆 + 分类色符号（极简风：彩只落在图标上）
      Column() {
        SymbolGlyph(this.badgeSymbol())
          .fontSize(20)
          .fontColor([this.blockColor()])
      }
      .width(40)
      .height(40)
      .borderRadius($r('app.float.radius_circle'))
      .backgroundColor(palette(this.isDark).bgElevated)
      .justifyContent(FlexAlign.Center)

      // 分类 + 副行
      Column({ space: 4 }) {
        Text(this.titleText())
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(palette(this.isDark).textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '100%' })
        Text(this.subtitle())
          .fontSize($r('app.float.font_aux'))
          .fontColor(palette(this.isDark).textTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '100%' })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 金额
      Text(this.amountText())
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.amountColor())
        .fontFeature('"tnum" on')
        .maxLines(1)
    }
    .width('100%')
    .height(68)
    .padding(this.showCard ? { left: 12, right: 12, top: 12, bottom: 12 } : { left: 4, right: 4 })
    .backgroundColor(this.showCard ? palette(this.isDark).bgCard : '#00000000')
    .borderRadius(this.showCard ? $r('app.float.radius_card') : $r('app.float.radius_tag'))
    .borderWidth(this.showCard ? cardBorderWidth(this.isDark) : 0)
    .borderColor(palette(this.isDark).border)
    .shadow(this.showCard ? cardShadow(this.isDark) : { radius: 0, color: '#00000000', offsetY: 0 })
    .onClick(() => {
      if (this.onItemClick !== undefined) {
        this.onItemClick(this.item.tx.id);
      }
    })
  }
}
