/**
 * 模块职责：首页 ViewModel（架构 T03）。
 * 无状态服务编排层：load() 一次聚合资产总览 / 本月结余 / 预算进度 / 最近流水，
 * 页面持 @State 接收结果。不继承响应式基类，不持有 UI 状态。
 */
import { Transaction } from '../model/Transaction';
import { Ledger } from '../model/Ledger';
import { AccountBalance, BudgetProgress, MonthSummary, NetAssetSummary, TxDisplayItem } from '../model/StatsModels';
import { AccountService } from '../service/AccountService';
import { BudgetService } from '../service/BudgetService';
import { StatsService } from '../service/StatsService';
import { SettingsService } from '../service/SettingsService';
import { LedgerService } from '../service/LedgerService';
import { SeedDataManager } from '../service/SeedDataManager';
import { TxDisplayMapper } from './TxDisplayMapper';
import { AppConstants, ThemeMode } from '../constants/AppConstants';
import { DateUtil } from '../utils/DateUtil';

/** 首页一次加载数据包 */
export class HomeData {
  public ledgerName: string = SeedDataManager.DEFAULT_LEDGER_NAME;
  public currency: string = AppConstants.DEFAULT_CURRENCY;
  public amountHidden: boolean = false;
  public asset: NetAssetSummary = new NetAssetSummary();
  public monthSummary: MonthSummary = new MonthSummary();
  public monthKey: string = '';
  /** 未设置预算时为 null（预算卡渲染"去设置"） */
  public budget: BudgetProgress | null = null;
  public recent: TxDisplayItem[] = [];
  /** 账户余额映射（账户相关卡片与最近流水展示用） */
  public balances: Map<number, AccountBalance> = new Map();

  /** 克隆自身（浅拷贝引用字段），用于触发 @State 引用变化重渲染 */
  public clone(): HomeData {
    const copy: HomeData = new HomeData();
    copy.ledgerName = this.ledgerName;
    copy.currency = this.currency;
    copy.amountHidden = this.amountHidden;
    copy.asset = this.asset;
    copy.monthSummary = this.monthSummary;
    copy.monthKey = this.monthKey;
    copy.budget = this.budget;
    copy.recent = this.recent;
    copy.balances = this.balances;
    return copy;
  }
}

export class HomeViewModel {

  /** 聚合加载（任一子项失败抛业务异常，由页面 catch 转 ErrorState） */
  public static async load(): Promise<HomeData> {
    const data: HomeData = new HomeData();
    data.monthKey = DateUtil.monthKey(DateUtil.now());
    data.currency = SettingsService.getCurrency();
    data.amountHidden = SettingsService.isAmountHidden();

    // 先解析并校验当前账本（持久化 id 失效时回退默认账本），再并发取数
    const ledger = await LedgerService.resolveCurrent();
    data.ledgerName = ledger.name;

    const tasks: Promise<void>[] = [];
    // 并发取数：四路互不依赖，缩短首页首帧
    tasks.push(AccountService.getNetAsset().then((asset: NetAssetSummary) => {
      data.asset = asset;
    }));
    tasks.push(StatsService.getMonthSummary(data.monthKey).then((summary: MonthSummary) => {
      data.monthSummary = summary;
    }));
    tasks.push(BudgetService.getProgress(data.monthKey).then((progress: BudgetProgress | null) => {
      data.budget = progress;
    }));
    tasks.push(AccountService.getAllBalances().then((balances: Map<number, AccountBalance>) => {
      data.balances = balances;
    }));
    tasks.push(StatsService.getRecent(AppConstants.RECENT_COUNT)
      .then((list: Transaction[]) => TxDisplayMapper.resolve(list))
      .then((items: TxDisplayItem[]) => {
        data.recent = items;
      }));
    await Promise.all(tasks);
    return data;
  }

  /** 金额隐藏切换（持久化 + 返回新状态） */
  public static async toggleAmountHidden(): Promise<boolean> {
    const next: boolean = !SettingsService.isAmountHidden();
    SettingsService.setAmountHidden(next);
    return next;
  }

  /** 主题模式读取（AssetCard 深浅色由 AppStorage 驱动，此处备用） */
  public static currentThemeMode(): number {
    return SettingsService.getThemeMode();
  }

  /** 主题是否跟随系统（设置页展示当前值用） */
  public static isSystemTheme(): boolean {
    return SettingsService.getThemeMode() === ThemeMode.SYSTEM;
  }
}
