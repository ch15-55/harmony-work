# 源码门禁结论：本轮不具备实施修复的条件

> **状态更新（2026-10-18 20:00）：源码已到位，门禁解除。** `harmony/` 已确认为 `com.lifeledger.app` 1.0.0 的真实工程，与 `E:\workset\harmony` 逐字节一致，并已完成构建。修复与验证结果见 [FIXES.md](FIXES.md)。以下内容保留为源码到位前的核查记录，不再代表当前状态。

记录日期：2026-10-18（Asia/Shanghai）。触发任务：按 [实测评估报告](ASSESSMENT.md) 修复 F01–F05 及信息表达问题。

## 结论

**未实施任何应用修改。** 本仓库只有发布包、编译产物和拆包资料，没有任何 DevEco 工程源码或构建配置。在没有源码的情况下改不动这五个缺陷：它们分别位于页面布局、表单避让、组件计算、状态订阅和锁服务中，都不在包配置或资源文件里，改不了 `.json`/`.json5`（后者本就不存在）。

按任务约定与 [仓库规则](../AGENTS.md)：不生成占位 `.ets` 冒充恢复结果，不反编译改写 `.abc`，不修改或重签 `harmony-release-signed.app`。

## 判定依据（本轮实际执行）

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 工程标志文件 | `find` 查 `build-profile.json5`、`oh-package.json5`、`module.json5`、`app.json5`、`hvigorfile.ts`、`AppScope/`、`*.ets` | 全部 0 命中 |
| 源文件计数 | `find . -name '*.ets'` / `'*.json5'` | 0 / 0 |
| 编译产物计数 | `find . -name '*.abc'` / `'*.pa'` | 1 / 17 |
| Git 历史 | `git log --oneline --all` | 无任何提交，无法从历史取回源码 |
| 原包指纹 | `sha256sum harmony-release-signed.app` | `f6062813…de2186f`，与报告一致 |
| 资料一致性 | `python tools/unpack_app.py --check` | `Verified 15 files; 24 routes; 103 module indicators`，退出码 0 |
| 拆包工具测试 | `python -m unittest discover -s tools -p "test_*.py"` | 7 项全部 OK |

后两项只证明"提取资料与原包一致、拆包工具本身正常"，**不是应用构建，也不是功能测试**。

## 缺失的工程文件

以下文件当前均不存在，需从原开发机、备份或原 Git 仓库取回。路径按 [源码接入说明](SOURCE_RECOVERY.md) 的常规结构列出，真实工程以实际为准。

### 一、应用级配置

| 文件 | 用途 | 状态 |
| --- | --- | --- |
| `AppScope/app.json5` | 应用包名、版本、图标、标签 | 缺失 |
| `AppScope/resources/` | 应用级字符串与媒体源文件 | 缺失 |

### 二、模块与构建配置

| 文件 | 用途 | 状态 |
| --- | --- | --- |
| `entry/src/main/module.json5` | 模块声明、abilities、页面入口 | 缺失（`recovered/entry/module.json` 是**编译后合并产物**，字段已展开，不能反向当作源配置） |
| `build-profile.json5`（根与 `entry/`） | 产品、签名、SDK 版本 | 缺失 |
| `oh-package.json5`、`oh-package-lock.json5`（根与 `entry/`） | 依赖声明与锁定 | 缺失 |
| `hvigorfile.ts`（根与 `entry/`）、`hvigor/hvigor-config.json5` | 构建脚本与 Hvigor 版本 | 缺失 |
| `local.properties` 或等价签名配置 | 本机 SDK 与签名路径 | 缺失，且不应入库 |

没有 `build-profile.json5` 与 `hvigorfile.ts`，即使补齐 `.ets` 也无法调用 Hvigor 构建，无法产出可比对的 HAP。

### 三、ArkTS 源码（全部 103 个模块）

字节码线索给出的是模块路径，不是文件内容。已确认存在但完全缺失源码的模块包括：

- **24 个页面**：`pages/` 下的 `PrivacyPage`、`Index`、`HomePage`、`RecordsPage`、`PlaceholderPage`、`StatisticsPage`、`MinePage`、`RecordEditPage`、`TransactionDetailPage`、`CategoryTxListPage`、`AccountManagePage`、`AccountEditPage`、`LedgerManagePage`、`CategoryManagePage`、`BudgetSettingPage`、`ExportPage`、`BackupPage`、`DiagnosticsPage`、`ThemeSettingPage`、`AppLockSettingPage`、`PinVerifyPage`、`AboutPage`、`PrivacyPolicyPage`、`UserAgreementPage`
- **组件**：`components/common/NavTitleBar`、`components/home/BudgetProgressCard`、`components/home/RecentListCard`、`components/record/AccountSelector` 等
- **服务**：`service/` 下的 `AppLockService`、`BackupService`、`BudgetService`、`DiagnosticsService`、`ExportService`、`TransactionService`、`SettingsService`、`DatabaseManager`、`MigrationManager`、`StatsService`、`AccountService`
- **模型、常量与工具**：`model/`、`constants/`（含 `AccountPresets`、`SchemaConstants`、`AppConstants`）、`utils/`（`MoneyUtil`、`CryptoUtil`、`WindowUtil`）
- **入口 ability**：`EntryAbility` 及生命周期、首启隐私拦截逻辑

### 四、资源源文件与测试

| 内容 | 状态 |
| --- | --- |
| `entry/src/main/resources/base/element/`（`string.json`、`color.json`、`float.json`） | 缺失，只剩编译后的 `resources.index` |
| `resources/base/media/` 源图与 `resources/rawfile/` 源协议文本 | 仅有产物副本，非源目录 |
| `resources/base/profile/main_pages.json` | 有产物副本，源文件缺失 |
| 单元测试与 UI 测试（`entry/src/ohosTest/` 或 `test/`） | 缺失，无从执行回归 |

## 为什么反汇编不能代替源码

`local-data/review/modules.pa` 与 `*.pa` 是 `ark_disasm` 的指令级输出，只能用于事实核对：

- 函数签名已被擦除为泛型，例如 `parseYuanToIntFen(any a0, any a1, any a2, any a3)`，无法还原参数类型、默认值与调用方语义。
- 没有类型声明、导入关系、装饰器结构、注释和组件树层次；ArkUI 的声明式结构在字节码中只剩构建调用序列。
- 反汇编不可回编译。改写指令再重打包会改变签名，等于伪造发布包，违反任务约束。
- 能确认的只有"某函数调用了某成员"这类事实，例如 `BudgetProgressCard.usedPercent` 存在、`CryptoUtil.hashPin` 只调用一次 `sha256Hex`（`digest` 一次）。**这类证据足以定性缺陷，不足以实施修复。**

## 缺陷与待改表面（源码到位后的落点）

以下"落点"是字节码中的模块线索，用于定位改动范围，具体文件路径与行号必须由真实工程确认。全部属于现有功能的修复，不新增业务功能、联网、账号、SDK 或权限。

| 编号 | 待改模块（线索） | 修法要点 | 验收判据 |
| --- | --- | --- | --- |
| F01 新增账户页状态栏重叠 | `pages/AccountEditPage`、`components/common/NavTitleBar`、`utils/WindowUtil` | 接入统一导航组件与实际避让区（顶部安全区/状态栏高度从窗口信息取），去掉硬编码顶部高度 | 标题、返回、保存完整可见；UI 树存在可点击"保存"节点；保存后账户出现在列表；深色、小屏、大字号复测 |
| F02 预算键盘遮挡 | `pages/BudgetSettingPage` | 表单放入可滚动容器并启用键盘避让，提交入口随键盘上移或保持可见 | 键盘弹出时输入框与保存按钮均完整可见且可点击，保存成功；收键盘后布局不跳变 |
| F03 预算比例失真 | `components/home/BudgetProgressCard`（`usedPercent`） | 去掉向上取整；低于 1% 显示"<1%"，其余保留 1 位小数；进度弧的最小可见长度与文字比例分开处理 | 200 元预算、0.02 元支出显示"<1%"；1% 边界显示正确；预算为 0 不除零 |
| F04 币种刷新不一致 | `components/home/RecentListCard`、`utils/MoneyUtil`、`service/SettingsService` | 金额格式化收敛到单一入口，显示币种与汇率作为显式入参；最近记录订阅与首页汇总同一状态源 | 切换币种后汇总、最近记录、明细、详情四处口径一致；切换只影响显示，数据库基准分不变；重启后一致 |
| F04 CSV 单位 | `service/ExportService` | 表头或首行说明标注导出金额单位为基准人民币（分转元），不随显示币种变化 | 美元显示状态下导出，文件明确标注单位；金额与库内基准值一致 |
| F05 应用锁重试 | `service/AppLockService`（`verifyPin`）、`utils/CryptoUtil`（`hashPin`） | 失败次数与锁定截止时间持久化，连续 5 次后至少 30 秒；后台切换与重启不清除；成功验证重置计数 | 5 次错误后正确 PIN 仍被拒并显示剩余等待；杀进程重启仍处于等待；到期后正确 PIN 解锁且计数归零 |
| F05 PIN 派生（改动需迁移） | `utils/CryptoUtil`、`service/AppLockService` | 若要换迭代式派生，必须带算法版本标记；旧哈希可继续验证，成功时迁移；不存明文 | 旧 PIN 升级后仍可解锁并完成迁移；迁移后新派生生效；失败不破坏原校验材料 |
| 交易时间表达 | `pages/TransactionDetailPage`、`pages/RecordEditPage`、`model` | 只记录日期时按日期展示，不显示 00:00；记录时间与交易日期分别标注 | 详情同时可区分"交易日期"与"记录时间"，无无意义时分 |
| 诊断日志 | `service/DiagnosticsService` | 输出白名单错误码与操作阶段，禁止写入金额、备注、账户名、PIN、哈希、盐 | 导出样本含非空错误码与阶段；检索不到上述敏感字段 |

数据库与备份格式保持不变：金额仍是整数分，七张表与索引不动，`schema_version` 不升级，备份 JSON 结构兼容。

## 本轮检查执行情况

| 检查 | 是否执行 | 说明 |
| --- | --- | --- |
| 读取仓库规则与测评报告 | 执行 | `AGENTS.md`、`README.md`、`docs/ASSESSMENT.md`、`docs/SOURCE_RECOVERY.md` |
| 源码存在性核查 | 执行 | 文件系统 + Git 历史，均无 |
| 原包指纹与资料一致性 | 执行 | SHA-256 与 `--check` 均符合 |
| 拆包工具单元测试 | 执行 | 7/7 通过 |
| 应用构建 | **未执行** | 无 `build-profile.json5`、无 `hvigorfile.ts`、无源码，命令不存在 |
| 应用单元/UI 测试 | **未执行** | 仓库内无应用测试代码 |
| 模拟器安装与界面复现 | **未执行** | 本轮没有修改，无需回归；往轮结果见测评报告，不能算作本轮验证 |
| 缺陷修复验证 | **未执行** | 未实施修改，任何"已修复"表述都不成立 |

## 解除阻塞的条件

1. 取回原 DevEco 工程根目录，至少包含 `AppScope/`、`entry/src/main/ets/`、`entry/src/main/module.json5`、`build-profile.json5`、`oh-package.json5`、Hvigor 配置。
2. 在原环境完成一次基线构建，记录 DevEco、SDK、Hvigor 版本与实际命令，确认包名 `com.lifeledger.app`、版本 `1.0.0` 和 24 个页面与现有包一致。
3. 按 [源码接入说明](SOURCE_RECOVERY.md) 把工程接为仓库根工程，保留 `recovered/` 与 `docs/` 作为基线；不覆盖既有 `README.md`、`AGENTS.md`。
4. 之后按 F01 → F02 → F03 → F04 → F05 的顺序做最小改动，每条独立提交，附实际构建与模拟器复现结果。

源码未到位前，本仓库可继续做的只有文档与拆包工具层面的工作。
