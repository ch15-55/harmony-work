/**
 * 模块职责：设置行（架构 T01 components/common/SettingItem.ets）。
 * 「我的」页及各设置页通用：标题 + 当前值 + 箭头/开关。
 * 简洁化：不再渲染图标（iconKey 参数保留以兼容既有调用方，已停用）。
 * 点击动作通过回调交给页面（架构 3.1 允许的唯一回调出口）。
 */
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';

@Component
export struct SettingItem {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 图标键（已停用：简洁化不再渲染图标，参数保留兼容旧调用） */
  @Prop iconKey: string = 'ic_common_none';
  /** 标题（静态入参，非装饰器属性） */
  title: string | Resource = '';
  /** 右侧当前值（可选） */
  @Prop valueText: string = '';
  /** 是否渲染开关（开启时忽略箭头） */
  @Prop showToggle: boolean = false;
  /** 开关状态（showToggle=true 时生效） */
  @Prop toggleOn: boolean = false;
  /** 是否为危险操作行（标题红色） */
  @Prop danger: boolean = false;
  /** 是否显示底部分割线 */
  @Prop showDivider: boolean = true;
  /** 点击回调（箭头模式） */
  onItemClick?: () => void;
  /** 开关切换回调（开关模式），参数为新的开关状态 */
  onToggleChange?: (on: boolean) => void;

  build() {
    // build() 只允许一个根节点：行 + 分割线必须包在同一个 Column 内
    Column() {
      Row({ space: 12 }) {
        Text(this.title)
          .fontSize($r('app.float.font_body'))
          .fontColor(this.danger ? palette(this.isDark).danger : palette(this.isDark).textPrimary)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.showToggle) {
          Toggle({ type: ToggleType.Switch, isOn: this.toggleOn })
            .selectedColor(palette(this.isDark).primary)
            .onChange((isOn: boolean) => {
              if (this.onToggleChange !== undefined) {
                this.onToggleChange(isOn);
              }
            })
        } else {
          Row({ space: 4 }) {
            if (this.valueText.length > 0) {
              Text(this.valueText)
                .fontSize($r('app.float.font_body'))
                .fontColor(palette(this.isDark).textSecondary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            Text('›')
              .fontSize(18)
              .fontColor(palette(this.isDark).textTertiary)
          }
          .alignItems(VerticalAlign.Center)
        }
      }
      .width('100%')
      .height(52)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        if (!this.showToggle && this.onItemClick !== undefined) {
          this.onItemClick();
        }
      })

      if (this.showDivider) {
        Divider()
          .color(palette(this.isDark).divider)
          .strokeWidth(1)
          .margin({ left: 56, right: 0 })
      }
    }
    .width('100%')
  }
}
