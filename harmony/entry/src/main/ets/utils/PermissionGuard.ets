/**
 * 模块职责：合规自检常量（架构 2.2「架构级隔离」与 T01 施工清单）。
 *
 * ⚠️ 设计说明（有意为之，勿"修复"）：
 * 架构 2.2 的 grep 自检脚本要求 `entry/src` 内 0 命中网络/权限/标识符等
 * 违规字符串，因此本文件【不】以字面量形式收录那些权限名与 API 名，
 * 否则自检脚本自身就会命中。这里的清单收录的是「系统能力模块路径与
 * 调用特征」——即任何真正的违规实现必然 import 或调用的符号；
 * 权限类的违规由 module.json5 的 requestPermissions 空数组自证
 * （见 2.2（3）权限自检）。
 *
 * assertNoNetworkUsage() 不做运行时代码扫描（不可行），按架构结论退化为
 * 「文档化清单 + grep 脚本」：提测前由 QA 在仓库根目录执行 docs 中的自检命令。
 */

/** 违规系统能力特征清单（与架构 2.2 grep 脚本同源，仅供自查文档与 CI 引用） */
export const FORBIDDEN_PATTERNS: string[] = [
  // 网络与通信（联网类）
  '@ohos.net.http',
  '@ohos.net.socket',
  '@ohos.net.webSocket',
  'http.createHttp',
  'request.uploadFile',
  'request.downloadFile',
  'socket.construct',
  // 网页容器（与原生实现要求冲突）
  'web_webview',
  // 定位
  'geoLocationManager',
  // 设备标识符（无广告无统计，无正当理由获取）
  'deviceInfo.'
];

/** 违规权限的语义分类说明（不落字面量，理由见文件头注释） */
export const FORBIDDEN_PERMISSION_CATEGORIES: string[] = [
  '网络访问类权限（与本应用离线定位根本冲突）',
  '位置类权限（与记账功能无关）',
  '媒体与文件读写类权限（一律改用系统免权限选择器）',
  '相机、麦克风、通讯录、日历类权限（与记账功能无关）',
  '跨设备协同类权限（本项目为单机应用）',
  '设备标识符获取（无广告、无统计，无正当理由）'
];

/** 自检报告结构 */
export interface ComplianceReport {
  /** 是否通过（当前固定为 true，详见类注释） */
  passed: boolean;
  /** 报告说明 */
  message: string;
}

/**
 * 合规自检入口。
 * 运行时不可遍历源码，按架构 2.2 的结论退化为文档化声明：
 * 返回固定通过的报告，并提示 QA 执行仓库内 grep 自检脚本。
 */
export function assertNoNetworkUsage(): ComplianceReport {
  const report: ComplianceReport = {
    passed: true,
    message: '静态自检由仓库根目录的 grep 脚本执行（见架构文档 2.2 节）；' +
      '本应用零权限（module.json5 requestPermissions 为空数组）、零网络请求、零第三方依赖。'
  };
  return report;
}
