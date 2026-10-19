/**
 * 模块职责：卡片容器（架构 T01 components/common/CardContainer.ets）。
 * 统一卡片视觉：圆角 16vp、浅色模式阴影 / 深色模式 1vp 描边替代阴影（PRD 5.1）。
 * 纯 UI 组件：只依赖色板，不调用 Service、不做路由。
 */
import { palette, cardShadow, cardBorderWidth } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';

@Builder
export function cardEmptyBuilder() {
}

@Component
export struct CardContainer {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 卡片内容 */
  @BuilderParam content: () => void = cardEmptyBuilder;
  /** 内边距覆盖（默认 card_padding；静态入参，非装饰器属性） */
  paddingValue: Resource | number = $r('app.float.card_padding');
  /** 背景色覆盖（默认色板 bgCard，如资产渐变大卡） */
  @Prop backgroundColorValue: string = '';

  private get cardBg(): string {
    if (this.backgroundColorValue.length > 0) {
      return this.backgroundColorValue;
    }
    return palette(this.isDark).bgCard;
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(this.paddingValue)
    .backgroundColor(this.cardBg)
    .borderRadius($r('app.float.radius_card'))
    .borderWidth(cardBorderWidth(this.isDark))
    .borderColor(palette(this.isDark).border)
    .shadow(cardShadow(this.isDark))
  }
}
