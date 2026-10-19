/**
 * 模块职责：Tab3 占位兜底（架构 T01）。
 * 中置「＋」按钮在 Index.onChange 中被拦截并改为拉起记账页，
 * 本页面在正常交互下永不展示，仅作为 Tabs 第 3 位的结构占位。
 */
import { palette } from '../constants/ThemeConstants';
import { AppStorageKeys } from '../constants/AppConstants';

@Entry
@Component
export struct PlaceholderPage {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;

  build() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor(palette(this.isDark).bgPage)
  }
}
