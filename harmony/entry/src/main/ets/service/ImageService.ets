/**
 * 模块职责：图片凭证服务（架构 T03：v1.0 仅接口骨架，D4 定稿 v1.1 启用）。
 * v1.1 计划（备忘，供后续增量实现）：
 * - pickImages：photoAccessHelper.PhotoViewPicker.select（免权限，最多 3 张）
 * - copyToSandbox：Picker URI 必须复制进沙箱（临时授权会失效），可选压缩
 * - deleteByTx：删除流水时同步删除沙箱图片，避免孤儿文件
 * v1.0 RecordEditPage 不渲染图片区，任何调用都会得到明确的未启用异常。
 */
import { ErrorMessages } from '../constants/ErrorMessages';

export class ImageService {

  /** 选择凭证图片（v1.1 启用） */
  public static async pickImages(maxCount: number): Promise<string[]> {
    throw new Error(ErrorMessages.IMAGE_NOT_ENABLED);
  }

  /** 复制 Picker URI 到应用沙箱并返回永久路径（v1.1 启用） */
  public static async copyToSandbox(uri: string, txId: number, index: number): Promise<string> {
    throw new Error(ErrorMessages.IMAGE_NOT_ENABLED);
  }

  /** 删除流水时同步清理其沙箱图片（v1.1 启用） */
  public static async deleteByTx(txId: number): Promise<void> {
    throw new Error(ErrorMessages.IMAGE_NOT_ENABLED);
  }
}
