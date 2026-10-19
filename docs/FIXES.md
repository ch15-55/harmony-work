# 轻账本 · 现有功能修复记录

日期：2026-10-18（Asia/Shanghai）。依据：[现有功能实测与评价](ASSESSMENT.md)。

## 源码来源与基线

| 项目 | 情况 |
| --- | --- |
| 工程目录 | `harmony/`（DevEco 工程，含 `AppScope/`、`entry/src/main/ets/`、`build-profile.json5`、`oh-package.json5`、`hvigorfile.ts`） |
| 与 `E:\workset\harmony` 比对 | 修改前逐字节一致（108 个 `.ets`），确认为同一份源码 |
| 包名 / 版本 | `com.lifeledger.app` / `1.0.0` / versionCode 1，与发布包一致 |
| 构建环境 | DevEco Studio 自带 SDK（HarmonyOS 6.1.1 / API 24）、Hvigor、Node |
| 构建路径 | 在 `E:\llbuild\run3`（ASCII 路径）全量构建；**工作区路径含中文，Hvigor 直接拒绝**（`00306003 Invalid project path`） |

基线构建在改动前成功（`BUILD SUCCESSFUL`，41s），说明工程本身可编译；改动后再次全量构建成功（48s）。

## 修改文件（22 个）

| 文件 | 对应问题 |
| --- | --- |
| `entry/src/main/ets/pages/AccountEditPage.ets` | F01 |
| `entry/src/main/ets/pages/BudgetSettingPage.ets` | F02 |
| `entry/src/main/ets/components/home/BudgetProgressCard.ets`、`components/chart/DonutChart.ets` | F03 |
| `entry/src/main/ets/components/list/TxListItem.ets`、`utils/MoneyUtil.ets`、`service/SettingsService.ets`、`constants/AppConstants.ets`、`service/ExportService.ets` | F04 |
| `entry/src/main/ets/service/AppLockService.ets`、`utils/CryptoUtil.ets`、`components/common/PinLockOverlay.ets`、`pages/Index.ets`、`pages/AppLockSettingPage.ets`、`pages/PinVerifyPage.ets` | F05、PIN 派生迁移、锁屏无障碍 |
| `entry/src/main/ets/pages/TransactionDetailPage.ets`、`utils/DateUtil.ets`、`utils/LogUtil.ets`、`utils/WindowUtil.ets`、`service/DiagnosticsService.ets`、`components/home/RecentListCard.ets`、`resources/base/element/string.json` | 信息表达与诊断 |

没有新增/删除源文件，没有改包名、作者、协议、权限、依赖与构建配置。

另同步了两份与新策略冲突的工程文档（不属于应用代码）：
- `harmony/docs/PRD.md`：PIN 锁由「错误 5 次仅提示」改为「连续 5 次进入 30 秒等待，持久化」。
- `harmony/docs/ARCHITECTURE.md`：应用锁段落同步为失败计数与等待截止时间写入 Preferences。

`docs/SOURCE_GATE.md` 顶部已标注门禁解除，保留为源码到位前的核查记录。

## 逐项修法

### F01 · 新增账户页状态栏重叠（P1）

原因：`AccountEditPage` 自建顶部 `Row`，未使用统一导航栏，也没有状态栏避让；其他页面走 `NavTitleBar`（内部按 `WindowUtil` 写入的 `STATUS_BAR_HEIGHT_PX` 下移）。

改法：删除自建标题行，改用 `NavTitleBar`，标题按新增/编辑切换，`actionText` 传「保存」，`onBack` 返回、`onAction` 提交。`actionText` 用法与 `AccountManagePage`、`LedgerManagePage` 一致，未新增组件能力。

### F02 · 预算键盘遮挡（P2）

原因：保存按钮与输入框同在一个滚动列里，键盘弹出后页面被压缩，按钮只剩很窄的可见高度。

改法：
- 保存按钮移出滚动区，放到页面底部固定操作区，滚动内容只保留「当前预算 + 输入框」。
- 本页 `aboutToAppear` 设 `KeyboardAvoidMode.RESIZE`，页面随键盘收缩，底栏固定在键盘上方；`aboutToDisappear` 恢复 `OFFSET`，不影响其他页面。
- 底栏加 `NAV_INDICATOR_HEIGHT_PX` 底部内边距，避开手势条。

### F03 · 预算比例失真（P2）

原因：`BudgetProgressCard.usedPercent` 用 `Math.ceil`，`0.02 / 200 = 0.01%` 被写成 `1%`。

改法：改为 `usedPercentText()`：`<1%` 显示「<1%」，1%–100% 保留一位小数并去掉 `.0`，超支取整。图形另设最小可见弧长 `MIN_ARC_RATIO = 1%`，只影响 `DonutChart` 单扇区进度环的绘制，不参与文字比例计算。

### F04 · 币种刷新与导出口径（P2）

原因（已确认）：`RecentListCard` 的 `ForEach` key 只含 `id` 与 `updatedAt`；切换币种后数据未变，列表项不会重建，`TxListItem` 里的金额文本保持旧币种。汇总卡因 `@Prop` 数据对象变化而重绘，所以出现「汇总美元、最近记录人民币」同屏。

改法：
- `SettingsService` 在初始化、`setCurrency`、`setCurrencyRate` 时把展示币种与汇率写入 `AppStorage`（`displayCurrency` / `displayRate`）。
- `TxListItem` 订阅这两个键，金额改用 `MoneyUtil.displayIn(分, 币种, 汇率)`；`display()` 也委托同一函数，全站口径单一。
- 只改展示：数据库仍存基础货币分，切换币种不写回任何金额；编辑回填沿用原有「未改输入则保留原值」逻辑。
- CSV 表头改为 `日期,时间,类型,金额(人民币元),分类,一级分类,账户,备注,账本`，明确导出恒为基准人民币，不随显示币种换算。

### F05 · 应用锁重试节制（P2）

原因：`AppLockService.verifyPin` 只比对哈希，没有任何失败计数或等待状态。

改法：
- `Preferences` 新增 `pin_fail_count`、`pin_lock_until`；连续错误 5 次（`PIN_MAX_FAILURES`）写入 30 秒（`PIN_LOCKOUT_MS`）截止时间。
- 等待期内 `verifyPin` 直接返回 false，不做哈希；等待到期后清零计数重新累计；校验成功或重设 PIN 清零。
- 状态在 `Preferences`，后台切换、杀进程、冷启动都保留。
- `PinLockOverlay` 通过宿主传入的 `lockedRemainMs` 回调获取剩余毫秒（组件不直接依赖 Service），期间忽略数字键并显示「密码错误次数过多，请 N 秒后重试」；归零后自动恢复输入。

### 信息表达与诊断

- 交易日期：`DateUtil.isDateOnly(ts)` 判定「只记日期」（`tx_date` 为本地 0 点）。详情页此时不再显示「时间 00:00」，只显示「交易日期 + 星期」与「记录时间」；列表副行同样省略无意义时分；CSV 的时间列留空。
- 详情页「日期」文案改为「交易日期」，与「记录时间」区分。
- 诊断日志：`LogUtil.fail(tag, stage, err)` 只写 `stage=xxx code=yyy`；导出前统一过滤——24 位以上十六进制替换为 `<hex>`，含中文、路径分隔符或 `@` 的文本整条丢弃，仅保留 ASCII 技术文案。`ExportService`、`DiagnosticsService`、`AppLockService`、`WindowUtil` 的异常改为该入口。

## 第二轮：遗留项处理

### 1. PIN 派生升级与兼容迁移

原实现为 `sha256(salt + pin)` 单次摘要，四位 PIN 只有 1 万种组合，校验材料一旦外泄，离线枚举几乎无成本。

改法：
- 新凭据改用 `PBKDF2(SHA-256)`，10 万次迭代、32 字节派生值（`CryptoUtil.derivePin`，系统 `createKdf('PBKDF2|SHA256')`）。
- 凭据记录压成**单个** Preferences 值 `pin_v2`，格式 `pbkdf2-sha256$迭代次数$盐$派生值`。算法、盐、派生值一次写入，避免迁移中途崩溃留下互不匹配的多键状态。
- 旧格式（`pin_salt` + `pin_hash`）保持可校验：`verifyPin` 先读 `pin_v2`；没有记录时走旧的单次哈希。**旧 PIN 校验成功后**才派生新格式、写 `pin_v2`、再清掉旧的盐与哈希；迁移失败只记日志，不影响本次解锁，旧凭据原样保留。
- 重设 PIN 时直接写新格式并清除旧键；关闭应用锁/忘记密码重置会一并清空 `pin_v2`。
- `hasPin()` 同时识别两种格式，升级用户不会因格式变化被判定为「未设置 PIN」。

需要说明的边界：四位 PIN 的搜索空间本身有限，PBKDF2 只提高单次尝试成本，不能把它描述成强口令保护；迁移路径经代码审查与编译，**尚未在设备上验证旧 PIN 升级后仍可解锁**（本机无模拟器，见下）。

### 2. 锁屏时不再向无障碍服务暴露底层账目

原实现只在视觉上盖了一层 `PinLockOverlay`，锁屏时读屏仍能遍历底层首页内容。现在给 `Index` 的内容容器加 `accessibilityLevel(this.locked ? 'no-hide-descendants' : 'auto')`，锁定态下底层子树不进入无障碍树。未安装第三方无障碍服务实测，结论限于代码层。

### 3. 首页「最近记录 / 查看全部」间距

`RecentListCard` 标题行给标题加 `layoutWeight(1)`，「查看全部」靠右，主次分开。

### 4. 签名配置移出版本库

`harmony/build-profile.json5` 内含本机证书路径与加密后的签名口令。处理方式：
- `.gitignore` 增加 `harmony/build-profile.json5`，该文件只留本机，构建仍照常使用；
- 新增可提交模板 `harmony/build-profile.example.json5`（`signingConfigs` 为空、不含路径与口令），克隆后由 DevEco 重新生成本机签名配置。
- 未改动原文件内容，未输出任何口令，未提交或推送。

### 5. 中文路径构建自动化

Hvigor 拒绝含中文的工程路径（`00306003`），这是工具限制，没有通过改工程规避。新增 `tools/build_ascii.ps1`：把 `harmony/` 同步到 `%TEMP%\lifeledger-build`（ASCII），调用 DevEco 自带 `hvigorw` 构建，再把 HAP 复制到 `local-data/fixes/`。脚本带路径白名单保护（只删除路径含 `lifeledger-build` 的目录），不触碰原工程。

```powershell
powershell -ExecutionPolicy Bypass -File tools\build_ascii.ps1
```

脚本以 UTF-8 BOM 保存，兼容 Windows PowerShell 5.1；已实际运行成功。

## 验证结果

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 改动前基线构建 | 通过 | `BUILD SUCCESSFUL in 41s` |
| 改动后全量构建（两轮） | 通过 | 第一轮 48s；第二轮经 `tools/build_ascii.ps1` 41s / 36s，退出码 0 |
| HAP 产出 | 2.2 MB，`entry-default-signed.hap` | `sha256 094709db…35c0c5`；副本存于 `local-data/fixes/`（被 Git 忽略） |
| 包名 / 版本 | 未变 | 产物 `module.json`：`com.lifeledger.app` / `1.0.0` / versionCode 1 |
| 权限 | 未变，仍为空 | 产物 `module.json` 无 `requestPermissions` |
| 页面注册 | 未变，24 个 | 产物 `resources/base/profile/main_pages.json` |
| 反汇编核对 F03 | 通过 | `usedPercentText` 内 `ceil` 计数 0；字节码含 `<1%` |
| 反汇编核对 F05 | 通过 | 字节码含 `pin_fail_count`、`pin_lock_until` |
| 反汇编核对 F04 | 通过 | 字节码含 `金额(人民币元)`、`displayCurrency`、`displayRate` |
| 反汇编核对 PIN 派生 | 通过 | 字节码含 `PBKDF2|SHA256`、`pbkdf2-sha256`、`pin_v2`，`derivePin` 调用 `createKdf`/`generateSecret` |
| 反汇编核对无障碍 | 通过 | 字节码含 2 处 `accessibilityLevel` |
| 签名配置隔离 | 通过 | `git check-ignore` 命中 `harmony/build-profile.json5`；模板未被忽略 |
| 源码一致性 | 通过 | 沙箱与工作区 `entry/src` 逐字节一致（0 差异） |

### 未执行的检查（不能算通过）

| 检查 | 状态 | 原因 |
| --- | --- | --- |
| 模拟器安装与界面复现 | **未执行** | 本机没有 HarmonyOS 模拟器镜像/AVD：`hdc list targets` 为空，`C:\Users\33719\.Huawei\Emulator` 无部署镜像，仅存在 Android 模拟器镜像 |
| 键盘遮挡、状态栏重叠的实际观感 | **未执行** | 依赖上一条；布局改动只经编译与代码审查 |
| 失败 5 次进入 30 秒等待、重启后仍生效 | **未执行** | 需要设备验证 Preferences 持久化与倒计时 |
| 切币种后四个入口一致 | **未执行** | 需要设备或预览器验证 |
| 应用单元测试 / UI 测试 | **未执行** | 工程内没有 `ohosTest` 或测试任务 |
| 备份恢复回归 | **未执行** | 未改备份结构，但无设备可复跑原用例 |
| 旧 PIN 迁移后仍可解锁 | **未执行** | 迁移路径经编译与代码审查；无设备可构造旧凭据并验证 |
| PBKDF2 在设备上的耗时 | **未执行** | 10 万次迭代的实际解锁延迟未测 |
| 锁屏时读屏是否真的读不到账目 | **未执行** | 未安装/授权第三方无障碍服务 |

## 未解决的问题与边界

1. **设备/模拟器回归仍缺失（最主要缺口）。** 本机没有 HarmonyOS 模拟器镜像或 AVD，`hdc list targets` 为空；键盘避让、状态栏效果、锁屏倒计时、币种四入口一致、PIN 迁移都只到编译与静态核对，不能写成已通过。
2. **PIN 迁移与派生性能未经设备验证。** 旧凭据走兼容路径、成功后升级为 PBKDF2，逻辑上不会因为升级失败而丢锁；但「旧 PIN 升级后仍可解锁」和 10 万次迭代的解锁延迟需要真机/模拟器复跑。四位 PIN 的空间限制仍在，PBKDF2 不等于强口令保护。
3. **应用锁仍是界面锁，不是数据加密。** 数据库和备份未加密，不能对外表述为加密保护。隐私政策与关于页现有文案没有作出加密承诺，本轮也未新增此类表述。
4. **交易时间语义是设计选择。** 记账页只选日期，`tx_date` 恒为本地 0 点；本轮按「只记录日期」处理展示，未引入新字段或时间选择器。需要精确时间属于功能变更。
5. **诊断日志只做了输出侧过滤。** 阶段与错误码保留、长十六进制与中文自由文本剔除，但未用包含账户名、备注、PIN 的真实样本做回归；日志仍只保留进程内最近 200 条。
6. **统计页图表层次**属于设计建议（总览与分类都用圆环），不是功能缺陷，本轮未改版式。
7. **原地构建仍不支持中文路径。** 已提供 `tools/build_ascii.ps1` 绕过，但没有改工程路径或构建配置去规避 Hvigor 的路径检查。
8. **数据库与备份格式未变。** 未加字段、未改 `schema_version`、未迁移数据；旧备份仍可恢复。旧 PIN 走兼容校验路径，升级只触及 Preferences 中的锁凭据。

## 复核命令

```powershell
# 一键构建（自动复制到 ASCII 临时目录，产物落在 local-data/fixes）
powershell -ExecutionPolicy Bypass -File tools\build_ascii.ps1

# 反汇编核对（可选）
& "E:\DevEco Studio\sdk\default\openharmony\toolchains\ark_disasm.exe" ets\modules.abc modules.pa
```
