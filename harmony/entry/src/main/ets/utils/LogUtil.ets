/**
 * 模块职责：hilog 封装 + 耗时打点（架构 T01/T02）。
 * - 统一 domain/tag 前缀，release 包可通过 hilog 关闭 debug 级别
 * - timeStart/timeEnd 供 StatsService 等验证「统计页 < 300ms」指标（架构 4.7）
 * - errMsg：把任意抛出对象压成一行可读文本，避免调用处到处 JSON.stringify
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 可导出的最小诊断日志单元，不记录账本明细或用户输入。 */
export class LogEntry {
  public time: number = 0;
  public level: string = '';
  public tag: string = '';
  /** 诊断摘要：形如 'stage=copy code=13900011' 或既有技术文案，导出前统一过滤 */
  public message: string = '';
}

/** 兼容 BusinessError 形态的只读错误码视图 */
interface CodedError {
  code?: number;
}

export class LogUtil {
  /** 自定义 domain，方便在 hilog 工具中过滤本应用日志 */
  static readonly DOMAIN: number = 0x5B67;
  private static readonly DEFAULT_TAG: string = 'LifeLedger';
  private static readonly MAX_DIAGNOSTIC_ENTRIES: number = 200;
  /** 24 位以上连续十六进制视为哈希/盐候选，导出时统一脱敏 */
  private static readonly LONG_HEX: RegExp = /[0-9a-fA-F]{24,}/g;
  private static entries: LogEntry[] = [];
  /** 耗时打点表（工具级缓存，不含业务状态） */
  private static readonly timers: Map<string, number> = new Map();

  public static d(tag: string, msg: string): void {
    LogUtil.append('DEBUG', tag, msg);
    hilog.debug(LogUtil.DOMAIN, LogUtil.tagOf(tag), '%{public}s', msg);
  }

  public static i(tag: string, msg: string): void {
    LogUtil.append('INFO', tag, msg);
    hilog.info(LogUtil.DOMAIN, LogUtil.tagOf(tag), '%{public}s', msg);
  }

  public static w(tag: string, msg: string): void {
    LogUtil.append('WARN', tag, msg);
    hilog.warn(LogUtil.DOMAIN, LogUtil.tagOf(tag), '%{public}s', msg);
  }

  public static e(tag: string, msg: string): void {
    LogUtil.append('ERROR', tag, msg);
    hilog.error(LogUtil.DOMAIN, LogUtil.tagOf(tag), '%{public}s', msg);
  }

  /**
   * 结构化失败日志：只记录「操作阶段 + 错误码」。
   * 不拼接 err.message（可能含中文提示、路径、账户名等自由文本），
   * 也不记录 PIN、哈希、盐或任何账目字段。
   */
  public static fail(tag: string, stage: string, e?: Object | null): void {
    let message: string = 'stage=' + LogUtil.stageToken(stage);
    const code: string = LogUtil.errorCode(e);
    if (code.length > 0) {
      message = message + ' code=' + code;
    }
    LogUtil.e(tag, message);
  }

  /** 阶段名只保留字母、数字与下划线，避免把自由文本带进诊断文件 */
  private static stageToken(stage: string): string {
    let result: string = '';
    for (let i = 0; i < stage.length && result.length < 32; i++) {
      const ch: string = stage.charAt(i);
      const code: number = stage.charCodeAt(i);
      const isDigit: boolean = code >= 48 && code <= 57;
      const isLower: boolean = code >= 97 && code <= 122;
      const isUpper: boolean = code >= 65 && code <= 90;
      if (isDigit || isLower || isUpper || ch === '_') {
        result = result + ch;
      }
    }
    return result.length > 0 ? result : 'unknown';
  }

  /** 错误码（BusinessError.code 或普通对象的 code）；无可用码时返回空串 */
  private static errorCode(e?: Object | null): string {
    if (e === undefined || e === null) {
      return '';
    }
    try {
      const coded: CodedError = e as CodedError;
      const value: number | undefined = coded.code;
      if (value === undefined || value === null || !Number.isFinite(value)) {
        return '';
      }
      return Math.trunc(value).toString();
    } catch (ex) {
      return '';
    }
  }

  /**
   * 开始一次耗时打点。
   * @param key 打点标识，同一 key 重复调用会覆盖上一次起点
   */
  public static timeStart(key: string): void {
    LogUtil.timers.set(key, Date.now());
  }

  /**
   * 结束耗时打点并返回毫秒数（同时输出 info 日志）。
   * 未调用过 timeStart 时返回 -1。
   */
  public static timeEnd(key: string): number {
    const start: number | undefined = LogUtil.timers.get(key);
    if (start === undefined) {
      return -1;
    }
    const cost: number = Date.now() - start;
    LogUtil.timers.delete(key);
    LogUtil.i('Perf', key + ' cost ' + cost.toString() + 'ms');
    return cost;
  }

  /** 异常对象 → 可读文本 */
  public static errMsg(e: Object | undefined | null): string {
    if (e === undefined || e === null) {
      return 'unknown error';
    }
    const err: Object = e as Object;
    try {
      return JSON.stringify(err);
    } catch (ex) {
      return err.toString();
    }
  }

  /** 返回副本，诊断导出不能修改进程内日志。 */
  public static snapshot(): LogEntry[] {
    const copy: LogEntry[] = [];
    for (let i = 0; i < LogUtil.entries.length; i++) {
      const source: LogEntry = LogUtil.entries[i];
      const item: LogEntry = new LogEntry();
      item.time = source.time;
      item.level = source.level;
      item.tag = source.tag;
      // 导出前再过滤一次：保留技术阶段/错误码，剔除自由文本与敏感片段
      item.message = LogUtil.diagMessage(source.message);
      copy.push(item);
    }
    return copy;
  }

  private static append(level: string, tag: string, message: string): void {
    const entry: LogEntry = new LogEntry();
    entry.time = Date.now();
    entry.level = level;
    entry.tag = LogUtil.sanitize(tag, 64);
    entry.message = LogUtil.sanitize(message, 240);
    LogUtil.entries.push(entry);
    if (LogUtil.entries.length > LogUtil.MAX_DIAGNOSTIC_ENTRIES) {
      LogUtil.entries.shift();
    }
  }

  /** 日志仅保留单行、定长技术信息，降低误带入用户输入的风险。 */
  private static sanitize(value: string, maxLength: number): string {
    const singleLine: string = value.split('\n').join(' ').split('\r').join(' ');
    return singleLine.length > maxLength ? singleLine.substring(0, maxLength) : singleLine;
  }

  /**
   * 诊断摘要白名单：
   * - 长十六进制串（哈希/盐）替换为 <hex>
   * - 含中文、路径分隔符或 @ 的文本整体丢弃（可能是备注、账户名、错误提示或文件路径）
   * - 其余纯 ASCII 技术文案（如 'stage=copy code=13900011'）保留，便于定位阶段
   */
  private static diagMessage(message: string): string {
    if (message.length === 0) {
      return '';
    }
    const text: string = message.replace(LogUtil.LONG_HEX, '<hex>');
    if (text.indexOf('/') >= 0 || text.indexOf('\\') >= 0 || text.indexOf('@') >= 0) {
      return '';
    }
    for (let i = 0; i < text.length; i++) {
      const code: number = text.charCodeAt(i);
      if (code < 0x20 || code > 0x7E) {
        return '';
      }
    }
    return text.length > 120 ? text.substring(0, 120) : text;
  }

  /** 统一 tag 前缀，便于日志检索 */
  private static tagOf(tag: string): string {
    return LogUtil.DEFAULT_TAG + '/' + tag;
  }
}
