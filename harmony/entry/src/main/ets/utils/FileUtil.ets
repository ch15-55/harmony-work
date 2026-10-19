/**
 * 模块职责：沙箱文件读写工具（架构 T03 utils/FileUtil.ets）。
 * - 所有路径均限定在应用沙箱 filesDir 下，卸载即清除
 * - 仅薄封装 fileIo，业务语义（CSV 生成、Picker 交互）在 service 层
 * - 本文件不持有状态
 * 分层说明：pages/components 禁止 import fs；如需文件能力一律经由本工具或 service 层。
 */
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { LogUtil } from './LogUtil';

export class FileUtil {
  private static readonly TAG: string = 'FileUtil';

  /**
   * 获取（并确保存在）沙箱子目录路径。
   * @param context 任意 Ability/应用上下文
   * @param sub 相对子目录，如 'export' / 'images'；空串表示 filesDir 本身
   */
  public static ensureDir(context: common.Context, sub: string): string {
    const base: string = context.filesDir;
    const dirPath: string = sub.length === 0 ? base : base + '/' + sub;
    if (!fileIo.accessSync(dirPath)) {
      // recursion=true 逐级创建，已存在时由调用侧 accessSync 保证只建一次
      fileIo.mkdirSync(dirPath, true);
    }
    return dirPath;
  }

  /** 拼接沙箱文件完整路径（不校验存在性） */
  public static sandboxPath(context: common.Context, sub: string, fileName: string): string {
    return FileUtil.ensureDir(context, sub) + '/' + fileName;
  }

  /** 写入全部字节（覆盖写）。返回实际写入字节数。 */
  public static writeBytes(context: common.Context, path: string, bytes: Uint8Array): number {
    let fd: number = -1;
    try {
      fd = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC).fd;
      // SDK writeSync 只接受 ArrayBuffer | string，直接传 Uint8Array 会报 139000020 Invalid argument
      return fileIo.writeSync(fd, bytes.buffer);
    } finally {
      if (fd >= 0) {
        fileIo.closeSync(fd);
      }
    }
  }

  /** 读取文本文件（UTF-8）。文件不存在或读取失败返回空串。 */
  public static readText(path: string): string {
    try {
      if (!fileIo.accessSync(path)) {
        return '';
      }
      const stat: fileIo.Stat = fileIo.statSync(path);
      const fd: number = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY).fd;
      try {
        const buf: ArrayBuffer = new ArrayBuffer(stat.size);
        fileIo.readSync(fd, buf);
        const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
        return decoder.decodeToString(new Uint8Array(buf));
      } finally {
        fileIo.closeSync(fd);
      }
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      LogUtil.e(FileUtil.TAG, 'readText failed: ' + err.message);
      return '';
    }
  }

  /**
   * 按 Picker 授权 URI 读取文本（v1.1 备份恢复，架构 T03）。
   * readText 面向沙箱路径，本方法面向 DocumentViewPicker 返回的 file:// URI。
   * 读取失败返回空串，由调用方判空处理（架构 T03 约定）。
   */
  public static readTextFromUri(uri: string, maxBytes: number = 0): string {
    let fd: number = -1;
    try {
      fd = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY).fd;
      const stat: fileIo.Stat = fileIo.statSync(fd);
      if (maxBytes > 0 && stat.size > maxBytes) {
        LogUtil.w(FileUtil.TAG, 'readTextFromUri rejected oversized file');
        return '';
      }
      const buf: ArrayBuffer = new ArrayBuffer(stat.size);
      fileIo.readSync(fd, buf);
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(new Uint8Array(buf));
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      LogUtil.e(FileUtil.TAG, 'readTextFromUri failed: ' + err.message);
      return '';
    } finally {
      if (fd >= 0) {
        fileIo.closeSync(fd);
      }
    }
  }

  /** 删除文件（不存在时静默成功） */
  public static deleteFile(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      LogUtil.e(FileUtil.TAG, 'deleteFile failed: ' + err.message);
    }
  }

  /**
   * 从沙箱文件复制到目标 URI（CSV/备份导出最终一步，DocumentViewPicker 授权写入）。
   * 直接读取沙箱字节并以 writeSync 写入目标 URI 的描述符：对 file:// 与
   * datashare:// 两类授权 URI 均稳定（copyFileSync(fd→URI-fd) 在部分设备/URI
   * 形态下会因跨文件系统而不生效，导致导出静默失败）。
   */
  public static copyToUri(context: common.Context, sandboxPath: string, targetUri: string): void {
    const srcFile: fileIo.File = fileIo.openSync(sandboxPath, fileIo.OpenMode.READ_ONLY);
    try {
      const stat: fileIo.Stat = fileIo.statSync(srcFile.fd);
      const buf: ArrayBuffer = new ArrayBuffer(stat.size);
      fileIo.readSync(srcFile.fd, buf);
      const bytes: Uint8Array = new Uint8Array(buf);
      // NEXT(API 12+)上 DocumentViewPicker 返回的授权 URI 必须以 READ_WRITE 打开才能写入，
      // 仅 WRITE_ONLY 在部分设备/版本会报 13900001 Operation not permitted。先 READ_WRITE，失败回退 WRITE_ONLY。
      let destFd: number = -1;
      try {
        destFd = fileIo.openSync(targetUri,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC).fd;
      } catch (e) {
        LogUtil.e(FileUtil.TAG, 'copyToUri READ_WRITE failed, fallback WRITE_ONLY: ' + (e as BusinessError).message);
        destFd = fileIo.openSync(targetUri,
          fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC).fd;
      }
      try {
        // SDK writeSync 只接受 ArrayBuffer | string，直接传 Uint8Array 会报 139000020 Invalid argument
        fileIo.writeSync(destFd, bytes.buffer);
      } finally {
        if (destFd >= 0) {
          fileIo.closeSync(destFd);
        }
      }
    } finally {
      fileIo.closeSync(srcFile);
    }
  }
}
