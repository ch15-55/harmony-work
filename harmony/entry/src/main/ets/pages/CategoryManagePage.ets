/**
 * 模块职责：分类管理页（架构 T05 / PRD F-3.3）。
 * - 按类型（支出/收入）切换查看全部分类（含已隐藏）
 * - 每行开关：隐藏 / 显示（内置分类可隐藏不可删除，架构 4.3）
 * - 取色全走 palette；文案全走 $r；隐藏动作经 CategoryService.hide 并 bump 全局刷新
 */
import { router } from '@kit.ArkUI';
import { palette } from '../constants/ThemeConstants';
import { AppStorageKeys, CategoryType } from '../constants/AppConstants';
import { Category } from '../model/Category';
import { CategoryService } from '../service/CategoryService';
import { NavTitleBar } from '../components/common/NavTitleBar';
import { LoadingState } from '../components/common/LoadingState';
import { ErrorState } from '../components/common/ErrorState';
import { EmptyState } from '../components/common/EmptyState';
import { TypeSwitchTabs } from '../components/record/TypeSwitchTabs';
import { ToastUtil } from '../utils/ToastUtil';

@Entry
@Component
struct CategoryManagePage {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  @StorageLink(AppStorageKeys.DATA_VERSION) @Watch('onDataChanged') dataVersion: number = 0;

  // 注意：初始值必须为 false。若初始为 true，load() 的防重入守卫
  // 会在 aboutToAppear 首次调用时直接 return，页面将永远卡在加载态。
  @State private loading: boolean = false;
  @State private errorMsg: string = '';
  @State private type: number = CategoryType.EXPENSE;
  @State private list: Category[] = [];

  /**
   * 加载序号：只有最新一次加载的响应生效。
   * 取代原先的 `if (this.loading) return` 守卫——该守卫会在「快速连点类型 Tab」
   * 或「连续切换可见性」时把第二次加载整个丢弃，导致选中类型与列表内容不一致。
   */
  private loadSeq: number = 0;

  /** 数据版本变化 → 自动重载（隐藏/显示后刷新） */
  onDataChanged(): void {
    this.load();
  }

  onPageShow(): void {
    this.load();
  }

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    const seq: number = ++this.loadSeq;
    this.loading = true;
    this.errorMsg = '';
    try {
      const list: Category[] = await CategoryService.listByType(this.type, true);
      if (seq !== this.loadSeq) {
        return; // 已有更新的加载在途，丢弃过期响应
      }
      this.list = list;
    } catch (e) {
      if (seq !== this.loadSeq) {
        return;
      }
      this.errorMsg = (e instanceof Error) ? e.message : getContext(this).resourceManager.getStringSync($r('app.string.common_error_title'));
      this.list = [];
    } finally {
      if (seq === this.loadSeq) {
        this.loading = false;
      }
    }
  }

  private async onSwitchType(type: number): Promise<void> {
    if (type === this.type) {
      return;
    }
    this.type = type;
    await this.load();
  }

  /**
   * visible=true 表示显示（取消隐藏）。
   * CategoryService.hide 内部已 DataBus.bump()，会经 onDataChanged 触发重载；
   * 此处不再重复 load（原实现每次切换都会连查两次）。
   */
  private async onToggleVisible(cat: Category, visible: boolean): Promise<void> {
    try {
      await CategoryService.hide(cat.id, !visible);
    } catch (e) {
      ToastUtil.showRes($r('app.string.toast_operate_failed'));
    }
  }

  build() {
    Column() {
      NavTitleBar({
        title: $r('app.string.page_category_manage_title'),
        showBack: true,
        onBack: (): void => {
          router.back();
        }
      })

      TypeSwitchTabs({
        selected: this.type,
        onTypeChange: (t: number): void => {
          this.onSwitchType(t);
        }
      })
        .padding({ top: 8, bottom: 8 })

      if (this.loading) {
        LoadingState({ rows: 6 })
          .layoutWeight(1)
      } else if (this.errorMsg.length > 0) {
        ErrorState({
          message: this.errorMsg,
          onRetry: (): void => {
            this.load();
          }
        })
          .layoutWeight(1)
      } else if (this.list.length === 0) {
        EmptyState({
          title: $r('app.string.category_empty'),
          iconKey: 'ic_cat_more'
        })
          .layoutWeight(1)
      } else {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.list, (cat: Category) => {
              this.catRow(cat)
            }, (cat: Category) => 'cat_' + cat.id.toString() + '_' + cat.updatedAt.toString())
          }
          .width('100%')
          .padding(16)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).bgPage)
  }

  @Builder
  private catRow(cat: Category) {
    Row({ space: 12 }) {
      Circle()
        .width(12)
        .height(12)
        .fill(cat.color)
        .margin({ left: 4 })

      Text(cat.name)
        .fontSize($r('app.float.font_body'))
        .fontColor(palette(this.isDark).textPrimary)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Toggle({ type: ToggleType.Switch, isOn: !cat.isHidden })
        .selectedColor(palette(this.isDark).primary)
        .onChange((isOn: boolean): void => {
          this.onToggleVisible(cat, isOn);
        })
    }
    .width('100%')
    .height(52)
    .padding({ left: 12, right: 12 })
    .backgroundColor(palette(this.isDark).bgCard)
    .borderRadius($r('app.float.radius_card'))
  }
}
