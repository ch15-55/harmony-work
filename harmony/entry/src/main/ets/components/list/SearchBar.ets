/**
 * 模块职责：检索栏（架构 T04 list/SearchBar）。
 * - 实时关键词，300ms 防抖后回调 onSearch（避免逐字符打库）
 * - 组件销毁清定时器；外部清空（切月份等）可调 clear()
 * - 空关键词回调空串（页面按「非搜索态」处理）
 */
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';

/** 防抖间隔（架构约定 300ms） */
const DEBOUNCE_MS: number = 300;

@Component
export struct SearchBar {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 关键词确认回调（含空串=退出搜索态） */
  onSearch?: (keyword: string) => void;
  @State private keyword: string = '';
  /** 防抖定时器 id（-1=无挂起任务） */
  private timerId: number = -1;

  aboutToDisappear(): void {
    // 组件销毁必须清防抖定时器，避免销毁后回调引发空引用
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }

  /** 外部清空（页面切月份/重置筛选时调用，不触发回调） */
  public clear(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
    this.keyword = '';
  }

  private onInput(value: string): void {
    this.keyword = value;
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
    }
    this.timerId = setTimeout(() => {
      this.timerId = -1;
      if (this.onSearch !== undefined) {
        this.onSearch(this.keyword);
      }
    }, DEBOUNCE_MS);
  }

  build() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(14)
      TextInput({ text: this.keyword, placeholder: $r('app.string.list_search_hint') })
        .fontSize($r('app.float.font_body'))
        .fontColor(palette(this.isDark).textPrimary)
        .placeholderColor(palette(this.isDark).textTertiary)
        .placeholderFont({ size: 14 })
        .backgroundColor(Color.Transparent)
        .padding(0)
        .layoutWeight(1)
        .onChange((value: string) => {
          this.onInput(value);
        })
        .onSubmit(() => {
          // 立即搜索：跳过防抖
          if (this.timerId !== -1) {
            clearTimeout(this.timerId);
            this.timerId = -1;
          }
          if (this.onSearch !== undefined) {
            this.onSearch(this.keyword);
          }
        })
      if (this.keyword.length > 0) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(14)
          .fontColor([palette(this.isDark).textTertiary])
          .padding(8)
          .onClick(() => {
            this.onInput('');
          })
      }
    }
    .width('100%')
    .height(40)
    .padding({ left: 12, right: 8 })
    .borderRadius($r('app.float.radius_button'))
    .backgroundColor(palette(this.isDark).bgElevated)
  }
}
