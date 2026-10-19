/**
 * 模块职责：账户选择器（架构 T04 record/AccountSelector）。
 * 触发行展示当前选中账户（图标+名称+余额），点击经 bindSheet 弹出底部
 * 账户列表；选中即回调并收起。余额由页面传入（AccountService 实时计算，
 * 本组件不做任何金额算术，展示统一走 MoneyUtil）。
 * 空账户列表时 sheet 内渲染 record_no_account 提示（全站空态要求）。
 */
import { palette } from '../../constants/ThemeConstants';
import { AppStorageKeys } from '../../constants/AppConstants';
import { IconConstants } from '../../constants/IconConstants';
import { MoneyUtil } from '../../utils/MoneyUtil';

/** 账户选择项（页面/ViewModel 组装，组件不触达数据层） */
export class AccountOption {
  public id: number = 0;
  public name: string = '';
  public icon: string = IconConstants.DEFAULT_ICON_KEY;
  public color: string = '#5B67F5';
  /** 实时余额（分） */
  public balance: number = 0;
}

@Component
export struct AccountSelector {
  @StorageLink(AppStorageKeys.IS_DARK) isDark: boolean = false;
  /** 候选账户 */
  @Prop options: AccountOption[] = [];
  /** 当前选中账户 id（0=未选择） */
  @Prop selectedId: number = 0;
  /** 左侧标签文案（「账户」/「转出」/「转入」） */
  @Prop labelRes: Resource = $r('app.string.record_account_label');
  /** 选中回调 */
  onSelected?: (accountId: number) => void;
  /** sheet 显隐（$$ 双向绑定 bindSheet） */
  @State private sheetShow: boolean = false;

  /** 当前选中项（未选中返回 null） */
  private currentOption(): AccountOption | null {
    for (let i = 0; i < this.options.length; i++) {
      if (this.options[i].id === this.selectedId) {
        return this.options[i];
      }
    }
    return null;
  }

  build() {
    Row({ space: 8 }) {
      Text(this.labelRes)
        .fontSize($r('app.float.font_body'))
        .fontColor(palette(this.isDark).textSecondary)

      if (this.currentOption() === null) {
        Text($r('app.string.record_no_account'))
          .fontSize($r('app.float.font_body'))
          .fontColor(palette(this.isDark).textTertiary)
          .layoutWeight(1)
      } else {
        Row({ space: 8 }) {
          Text(IconConstants.iconGlyph(this.currentOption()!.icon))
            .fontSize(18)

          Text(this.currentOption()!.name)
            .fontSize($r('app.float.font_body'))
            .fontColor(palette(this.isDark).textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(MoneyUtil.display(this.currentOption()!.balance))
            .fontSize($r('app.float.font_aux'))
            .fontColor(palette(this.isDark).textSecondary)
            .layoutWeight(1)
            .textAlign(TextAlign.End)
        }
        .layoutWeight(1)

        Text('›')
          .fontSize($r('app.float.font_title'))
          .fontColor(palette(this.isDark).textTertiary)
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: $r('app.float.card_padding'), right: $r('app.float.card_padding') })
    .borderRadius($r('app.float.radius_button'))
    .backgroundColor(palette(this.isDark).bgElevated)
    .onClick(() => {
      this.sheetShow = true;
    })
    .bindSheet($$this.sheetShow, this.sheetBuilder(), {
      height: 360,
      dragBar: false,
      showClose: false
    })
  }

  /** 底部账户列表 sheet（PRD：图标+名称+余额） */
  @Builder
  private sheetBuilder() {
    Column({ space: 8 }) {
      Text($r('app.string.record_account_label'))
        .fontSize($r('app.float.font_title'))
        .fontWeight(FontWeight.Medium)
        .fontColor(palette(this.isDark).textPrimary)
        .padding({ top: 16 })

      Divider()
        .color(palette(this.isDark).divider)

      if (this.options.length === 0) {
        // 空态：账户全被删除时
        Text($r('app.string.record_no_account'))
          .fontSize($r('app.float.font_body'))
          .fontColor(palette(this.isDark).textTertiary)
          .padding({ top: 40, bottom: 40 })
      } else {
        List() {
          ForEach(this.options, (option: AccountOption) => {
            ListItem() {
              Row({ space: 12 }) {
                Text(IconConstants.iconGlyph(option.icon))
                  .fontSize(20)

                Text(option.name)
                  .fontSize($r('app.float.font_body'))
                  .fontColor(palette(this.isDark).textPrimary)
                  .layoutWeight(1)

                Text(MoneyUtil.display(option.balance))
                  .fontSize($r('app.float.font_body'))
                  .fontColor(option.id === this.selectedId
                    ? palette(this.isDark).primary
                    : palette(this.isDark).textSecondary)
              }
              .width('100%')
              .height(52)
              .padding({ left: 16, right: 16 })
              .backgroundColor(option.id === this.selectedId
                ? palette(this.isDark).bgPage
                : Color.Transparent)
            }
            .onClick(() => {
              if (this.onSelected !== undefined) {
                this.onSelected(option.id);
              }
              this.sheetShow = false;
            })
          }, (option: AccountOption) => 'acc_' + option.id.toString() + '_' +
            option.balance.toString())
        }
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(palette(this.isDark).bgCard)
  }
}
