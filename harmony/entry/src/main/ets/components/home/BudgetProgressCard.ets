/**
 * 模块职责：预算进度卡（架构 T04 home/BudgetProgressCard）。
 * - 复用 DonutChart 单扇区（环形进度），剩余部分画底环灰
 * - level 驱动配色（数据驱动）：NORMAL 主色 / WARN 警示黄 / OVER 支出红
 * - 未设预算（total=0）：文案 + 「去设置」按钮回调 onGoSetting
 * - 展示：已用 / 剩余 / 日均可用（剩余天数由 StatsService 计算入 DTO）
 */
import { palette } from '../../constants/ThemeConstants';
import { AppConstants, AppStorageKeys, BudgetLevel } from '../../constants/AppConstants';
import { BudgetProgress, CategorySlice } from '../../model/StatsModels';
import { MoneyUtil } from '../../utils/MoneyUtil';
import { DonutChart } from '../chart/DonutChart';

/** 进度环最小可见弧长占比（仅影响图形，不参与百分比文字计算） */
const MIN_ARC_RATIO: number = 0.01;

@Component
export struct BudgetProgressCard {
  @StorageLink(AppStorageKeys.IS_DARK) @Watch('rebuildSlices') isDark: boolean = false;
  /** 预算进度 DTO（ViewModel 提供；null 等价于未设置） */
  @Prop @Watch('rebuildSlices') progress: BudgetProgress | null = null;
  /** 是否播放入场动画（页面 onPageHide 后重进时可关） */
  @Prop animate: boolean = true;
  /** 「去设置」回调 */
  onGoSetting?: () => void;
  /**
   * 单扇区数据缓存：build 内不再每次新建数组，避免 DonutChart 的 @Prop slices
   * 引用每帧都变 → 每次首页重渲染（含记账 bump 后 reload）都重绘并重新播放入场动画。
   * 仅在进度 / 主题变化时重建（@Watch），普通重渲染沿用稳定引用。
   */
  @State private sliceCache: CategorySlice[] = [];

  aboutToAppear(): void {
    this.rebuildSlices();
  }

  /** 进度或主题变化才重建切片（引用稳定 → 普通重渲染不再触发图表重绘/重动画） */
  private rebuildSlices(): void {
    const slice: CategorySlice = new CategorySlice();
    if (this.progress !== null) {
      slice.amount = this.progress.used;
      slice.ratio = 1;
    }
    slice.color = this.levelColor();
    this.sliceCache = [slice];
  }

  /** level → 进度色（数据驱动，不硬编码业务色） */
  private levelColor(): string {
    const level: number = this.progress === null ? BudgetLevel.NORMAL : this.progress.level;
    if (level === BudgetLevel.OVER) {
      return palette(this.isDark).expense;
    }
    if (level === BudgetLevel.WARN) {
      return palette(this.isDark).warning;
    }
    return palette(this.isDark).primary;
  }

  /**
   * 已用占比文案：按真实比例展示，不再向上取整。
   * - 低于 1% 显示「<1%」，避免 0.01% 被写成 1%
   * - 1% ~ 100% 保留一位小数，整数时不显示 .0
   * - 超支保持整数，便于一眼看出超出幅度
   */
  private usedPercentText(): string {
    if (this.progress === null || this.progress.total <= 0 || this.progress.used <= 0) {
      return '0%';
    }
    const percent: number = this.progress.used / this.progress.total * 100;
    if (percent < 1) {
      return '<1%';
    }
    if (percent < 100) {
      const fixed: string = percent.toFixed(1);
      const trimmed: string = fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
      return trimmed + '%';
    }
    return Math.round(percent).toString() + '%';
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text($r('app.string.home_budget_title'))
          .fontSize($r('app.float.font_title'))
          .fontWeight(FontWeight.Medium)
          .fontColor(palette(this.isDark).textPrimary)
      }
      .width('100%')

      if (this.progress === null || this.progress.total <= 0) {
        // 未设预算空态
        Column({ space: 12 }) {
          Text($r('app.string.home_budget_not_set'))
            .fontSize($r('app.float.font_body'))
            .fontColor(palette(this.isDark).textSecondary)
          Text($r('app.string.home_budget_go_setting'))
            .fontSize($r('app.float.font_body'))
            .fontColor(palette(this.isDark).primary)
            .padding({ left: 24, right: 24, top: 8, bottom: 8 })
            .borderRadius($r('app.float.radius_button'))
            .border({ width: 1, color: palette(this.isDark).primary })
            .onClick(() => {
              if (this.onGoSetting !== undefined) {
                this.onGoSetting();
              }
            })
        }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
      } else {
        Row({ space: 16 }) {
          DonutChart({
            slices: this.sliceCache,
            backgroundRemain: Math.max(0, this.progress!.total - this.progress!.used),
            minArcRatio: MIN_ARC_RATIO,
            centerText: this.usedPercentText(),
            centerSubText: MoneyUtil.display(this.progress!.used),
            animate: this.animate
          })
            .width(120)
            .height(120)

          Column({ space: 8 }) {
            Row({ space: 6 }) {
              Text($r('app.string.home_budget_used'))
                .fontSize($r('app.float.font_aux'))
                .fontColor(palette(this.isDark).textSecondary)
              Text(MoneyUtil.display(this.progress!.used))
                .fontSize($r('app.float.font_body'))
                .fontColor(this.levelColor())
                .fontFeature('"tnum" on')
            }

            Row({ space: 6 }) {
              Text($r('app.string.home_budget_remain'))
                .fontSize($r('app.float.font_aux'))
                .fontColor(palette(this.isDark).textSecondary)
              Text(MoneyUtil.display(this.progress!.remain))
                .fontSize($r('app.float.font_body'))
                .fontColor(this.progress!.remain < 0
                  ? palette(this.isDark).expense
                  : palette(this.isDark).textPrimary)
                .fontFeature('"tnum" on')
            }

            Row({ space: 6 }) {
              Text($r('app.string.home_budget_daily'))
                .fontSize($r('app.float.font_aux'))
                .fontColor(palette(this.isDark).textSecondary)
              Text(MoneyUtil.display(this.progress!.dailyAvailable))
                .fontSize($r('app.float.font_body'))
                .fontColor(palette(this.isDark).textPrimary)
                .fontFeature('"tnum" on')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding($r('app.float.card_padding'))
    .borderRadius($r('app.float.radius_card'))
    .backgroundColor(palette(this.isDark).bgCard)
  }
}
