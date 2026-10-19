/**
 * 模块职责：Toast 封装（架构 T01 utils/ToastUtil.ets）。
 * - 统一入口，便于全局调整位置与时长
 * - 支持字符串与资源引用两种消息来源
 * - Toast 属于 UI 反馈，只允许在 Page / ViewModel 结果处理处调用
 */
import { promptAction } from '@kit.ArkUI';
import { LogUtil } from './LogUtil';

export class ToastUtil {
  private static readonly TAG: string = 'ToastUtil';
  /** 短 Toast 时长（毫秒） */
  static readonly DURATION_SHORT: number = 1500;
  /** 长 Toast 时长（毫秒） */
  static readonly DURATION_LONG: number = 3000;
  /** 距底部偏移（避开 Tab 栏与悬浮按钮） */
  static readonly BOTTOM_OFFSET: number = 96;

  /** 显示短 Toast（字符串消息） */
  public static show(message: string): void {
    ToastUtil.showInternal(message, ToastUtil.DURATION_SHORT);
  }

  /** 显示长 Toast（字符串消息） */
  public static showLong(message: string): void {
    ToastUtil.showInternal(message, ToastUtil.DURATION_LONG);
  }

  /** 显示短 Toast（资源引用，保证文案统一走 string.json） */
  public static showRes(res: Resource): void {
    ToastUtil.showInternal(res, ToastUtil.DURATION_SHORT);
  }

  /** 显示长 Toast（资源引用） */
  public static showResLong(res: Resource): void {
    ToastUtil.showInternal(res, ToastUtil.DURATION_LONG);
  }

  /**
   * 内部统一发送。
   * promptAction.showToast 在无窗口场景（如 App 后台）可能抛错，这里捕获并只记录日志，
   * 保证调用方无需包裹 try-catch。
   */
  private static showInternal(message: string | Resource, duration: number): void {
    try {
      promptAction.showToast({
        message: message,
        duration: duration,
        bottom: ToastUtil.BOTTOM_OFFSET,
        showMode: promptAction.ToastShowMode.DEFAULT
      });
    } catch (e) {
      LogUtil.w(ToastUtil.TAG, 'showToast failed');
    }
  }
}
