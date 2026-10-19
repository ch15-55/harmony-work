# 轻账本（LifeLedger）上架打包 SOP

> 适用范围：把当前 ArkTS 工程打包成可在华为 AppGallery 上架的发布包（.app / 签名 HAP）。
> 当前发布基线：本地记账、多账本、CSV 导出、备份恢复、应用锁与主题设置。
> 本版本未交付每日记账提醒，不申请代理提醒能力，也不得在 AGC 文案、截图或应用简介中宣传提醒。

## 0. 基本信息（固定值）

| 项 | 值 |
| --- | --- |
| 应用名称 | 轻账本（LifeLedger） |
| 包名 bundleName | `com.lifeledger.app` |
| 当前版本 | `1.0.0`（versionCode `1`） |
| 工程路径 | `E:\workset\harmony` |
| 权限声明 | 无 requestPermissions；文件导入导出均通过系统 Picker |

## 1. 上架前置条件（Checklist）

1. 已在 [AppGallery Connect](https://developer.huawei.com/consumer/cn/agconnect/) 创建**项目**与**应用**，包名严格填 `com.lifeledger.app`（与 `AppScope/app.json5` 一致）。
2. 已从 AGC 下载发布证书三件套：`.p12`（密钥库）、`.cer`（证书）、`.p7b`（Profile 授权文件）。
3. 已准备隐私政策 URL，且内容与应用内 `privacy.md` 一致。
4. 已完成 `docs/上架真机验收清单.md` 的 P0 用例并留存真机截图或录屏。
5. 已确认诊断导出与隐私政策一致：诊断文件只含技术运行信息，且由用户通过系统保存面板自行保存。

## 2. 配置发布签名

工程 `build-profile.json5` 已预置两条签名配置：

- `default`：本地自动调试签名，**仅用于开发**。
- `release`：**发布签名占位模板**，material 字段现为 `REPLACE_WITH_*` 占位，需替换成 AGC 证书。

`default` 配置中的口令是 DevEco 加密后的密文，解密依赖本机 `.ohos` 下的签名材料目录。不要把 `.p12`、`.cer`、`.p7b`、`material/` 或发布口令提交进仓库；这些路径已经由 `.gitignore` 排除。

### 方式 A：DevEco 自动签名（推荐，最稳）

1. DevEco Studio 打开工程 → `File → Project Structure → 项目根 → Signing Configs`。
2. 新建配置名 `release`，勾选 **Automatically generate signature**（需登录华为账号且 AGC 应用已存在）。
3. 确认 `Signing` 指向刚生成的 `release` 配置 → `OK`。
4. DevEco 会自动写入本机发布签名配置，并让 `release` 产品引用它。提交代码前确认 `build-profile.json5` 没有包含真实发布证书路径或发布口令。

### 方式 B：手动填写模板节点

直接编辑根 `build-profile.json5`，找到 `name: "release"` 的 signingConfig，把 6 个 material 字段替换为 AGC 下载的真实值：

| 字段 | 填什么 |
| --- | --- |
| `certpath` | AGC 下载的 `.cer` 绝对路径 |
| `storeFile` | AGC 下载的 `.p12` 绝对路径 |
| `profile` | AGC 下载的 `.p7b` 绝对路径 |
| `keyAlias` | 密钥别名（创建证书时自定） |
| `keyPassword` | 密钥密码 |
| `storePassword` | 密钥库密码 |
| `signAlg` | 固定 `SHA256withECDSA` |

> 不要把真实发布证书、Profile 或明文口令提交进工程。需要 CI 时使用受保护的密钥存储，并在构建机运行时注入材料。

发布阻断项：当前 `release` signingConfig 仍为占位模板。必须由应用主体在 AGC 配置正式证书、可访问的隐私政策 URL，并验证客服邮箱后，才可以生成并提交正式发布包。

## 3. 构建发布包

### 3.1 DevEco IDE（推荐路径）

`Build → Build Apps`（或 `Build Haps/App(s) → Build APP(s)`）→ 选择 `release` 产品 / `release` 签名 →
产物位于 `entry/build/outputs/default/` 或 `build/outputs/`（`.app` 为可上架包，内含签名 HAP）。

### 3.2 命令行（本机验证）

DevEco 的打包工具需要使用其自带 JBR。系统 PATH 中的 Oracle Java 19 会导致 `PackageHap` 以 `0xC0000409` 退出。PowerShell 中可使用：

```powershell
$env:DEVECO_SDK_HOME = 'E:\DevEco Studio\sdk'
$env:JAVA_HOME = 'E:\DevEco Studio\jbr'
$env:Path = 'E:\DevEco Studio\jbr\bin;' + $env:Path
& 'E:\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap --mode module --no-daemon --no-incremental
```

成功后确认 `entry/build/default/outputs/default/entry-default-signed.hap` 的时间戳已更新。发布包仍应通过 DevEco 的 `release` 产品与 AGC 正式签名生成。

## 4. 版本号管理

每次提审前自增（在 `AppScope/app.json5`）：

```json5
"versionCode": 2,        // 每次上架 +1，整数递增
"versionName": "1.0.1"   // 语义化版本
```

规则：`versionCode` 必须严格递增，否则 AGC 拒收；`versionName` 跟随展示。

## 5. 上架合规红线（必查）

1. **权限最小化**：当前 `module.json5` 不声明任何运行时权限。导出/备份一律走系统 Picker，不申请存储权限。
2. **禁金融敏感词**：应用文案、分类名不得出现「理财」「投资」「收益」等金融类敏感词。当前收入分类已改名「利息」，请勿回退。
3. **隐私政策口径**：隐私政策中**不得**写「只申请必要权限」之类话术；应如实说明「纯本地运行、不收集不上传任何用户数据」。
4. **备案**：纯本地工具类应用通常可免 APP 备案（以最新政策为准），提审时按 AGC 引导填写。

## 6. 提审材料清单

- 应用图标 / 截图（按 AGC 要求的尺寸与数量）
- 隐私政策 URL
- 应用简介（强调本地、隐私、多账本、备份恢复）
- 与实际版本一致的应用内截图；不得出现或描述尚未交付的记账提醒、图片凭证等功能

## 7. 多环境对照

| 场景 | 产品 product | 签名 | 用途 |
| --- | --- | --- | --- |
| 本地开发/调试 | `default` | `default`（自动调试） | 日常开发与真机调测 |
| 上架发布 | `release` | `release`（AGC 正式证书） | 出 .app 提审 |

> 切换方式：DevEco 的 Signing Configs 选择对应配置；命令行用 `--product release` 指定产品。

## 8. 后续提醒功能的解锁条件

`docs/AGC代理提醒申请说明.md` 仅供未来实现每日记账提醒后申请开放能力使用。只有同时完成以下事项，才可以把提醒写入上架信息：

1. 实现并真机验证 `ReminderService`、提醒设置页及关闭/改时逻辑；
2. 在 `module.json5` 声明最小权限，并同步更新隐私政策、AGC 权限说明和应用简介；
3. 获得 AGC 代理提醒能力批准，并使用正式签名真机验证触发和取消；
4. 补充提醒的回归用例及审核截图。
