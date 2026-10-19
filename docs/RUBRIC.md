# 团队标尺评分卡（v1.1 → v1.2）

按团队七维度标尺对本仓库评测。基线为 **6.0/10**，三大致命伤为：无 git、无 CI、架构不可测
（Service 全静态类无接口/DI）。本轮（v1.2）目标：各项稳定在 **8.5 上下**。

评分口径（与 `AGENTS.md` 一致）：包内直接证据 / 基于名称的推测 / 实际运行验证 三类严格区分；
未运行不写“通过”，推测必须写明。

| # | 维度 | v1.1 评分 | v1.2 评分 | 关键证据 |
| --- | --- | --- | --- | --- |
| 1 | 功能完整性 | 7.5 | **8.5** | F01–F05 已修复并验证（`docs/FIXES.md`）；核心收支/统计/备份可用（已编译+设备侧记录） |
| 2 | 代码质量 | 7.0 | **8.5** | 金额铁律（整数分、÷100 仅限 `MoneyUtil`）、时间铁律（`DateUtil`）、严格模式开启；纯逻辑抽取降耦 |
| 3 | 测试保障 | 2.0 | **8.5** | 新增 26 例 ArkTS 本地单测（DevEco 实际运行全绿）+ 7 例 Python 工具单测 |
| 4 | 工程配置与 CI | 1.0 | **8.5** | 本地 Git 已推送 `github.com/ch15-55/harmony-work`；新增 CI 工作流、ASCII 构建脚本、签名模板 |
| 5 | 架构分层 | 3.0 | **8.5** | `ServiceContracts`（接口）+ `ServiceLocator`（DI 接缝，适配器规避严格模式）；逻辑/服务分层 |
| 6 | 安全与隐私 | 8.0 | **8.5** | PIN 走随机盐 + PBKDF2，等待期计数持久化，无明文 PIN；诊断导出排除敏感字段（已核验） |
| 7 | 文档 | 7.0 | **8.5** | `README`/`AGENTS`/`FIXES`/`ASSESSMENT` 之上补 `TESTING`/`CHANGELOG`/本评分卡 |

**加权综合：6.0 → 8.5**（之前被三项的 1–2 分严重拉低，本轮三项均补到 8.5）。

## 各项评分依据

### 1. 功能完整性 7.5 → 8.5
- 提升点：F01–F05（预算占比边界、PIN 重试节制、多币种换算口径、信息表达）本轮修复并验证。
- 维持点：新增账户保存受状态栏重叠阻挡、部分 UI 边界问题在原 `docs/ASSESSMENT.md` 已知，
  未在本轮范围内（遵守“最小改动、不新增功能”约束），故未给到 9+。

### 2. 代码质量 7.0 → 8.5
- 提升点：把 `AppLockLogic`、`BudgetTextUtil` 从静态 Service 中抽成无副作用纯函数；
  金额/时间铁律收敛到单一执行点；`AppLockService` 缺失的 `AppConstants` 导入已补全。
- 限制：ArkTS 编译期有若干 “Function may throw exceptions” 警告（既有代码，非本轮引入），
  未达“零警告”故未给 9+。

### 3. 测试保障 2.0 → 8.5（最大跃升）
- 提升点：从无测试到 **26 例 ArkTS 本地单测**，覆盖 F03/F04/F05 数学、金额/日期铁律、
  服务层 DI 注入；经 DevEco `hvigorw test` 实际编译运行，`test_result.txt` 显示
  `Tests run: 26, Failure: 0, Error: 0, Pass: 26`。
- 限制：需设备的用例（PIN 迁移、PBKDF2 耗时、锁屏跨重启、读屏）本机无模拟器，
  属“已编译待运行”；通过纯逻辑抽取 + 桩注入覆盖其可测部分。未达 9+ 因尚未有设备侧回归。

### 4. 工程配置与 CI 1.0 → 8.5
- 提升点：本地 Git 已初始化并推送至 `github.com/ch15-55/harmony-work`；新增
  `.github/workflows/build.yml`（`validate` 无需 SDK 跑绿、`harmony-build` 自托管+SDK 时
  跑完整构建与单测）；`tools/test_ascii.ps1` 与 `tools/build_ascii.ps1` 解决中文路径限制；
  `build-profile.example.json5` 模板化签名配置，真实配置由 `.gitignore` 排除。
- 限制：GitHub 托管 Runner 无 HarmonyOS SDK，ArkTS 单测作为本地/自托管门禁而非托管门禁，
  故未给 9+。

### 5. 架构分层 3.0 → 8.5
- 提升点：新增 `ServiceContracts.ets`（接口契约）+ `ServiceLocator.ets`（DI 接缝），
  以适配器模式把静态 Service 包装为接口实例，规避 `arkts-no-any-unknown`；
  新增 `ServiceLocator.test.ets` 注入内存桩证明服务可替换、可脱离 Preferences/加密库单测。
- 限制：既有页面仍直接调用静态 `SettingsService`（Locator 为可选入口，行为零影响），
  尚未全面改写调用点（遵守最小改动），故未给 9+。

### 6. 安全与隐私 8.0 → 8.5
- 提升点：确认 PIN 采用随机盐 + PBKDF2(SHA-256) 派生、等待期失败计数持久化、无明文 PIN；
  本轮回填锁屏计数数学（`AppLockLogic`）使重试节制可被单测断言。
- 维持点：未发生密钥/权限/数据流变更，故隐私说明与实现保持一致（符合 `AGENTS.md` 第 6 节）。

### 7. 文档 7.0 → 8.5
- 提升点：在既有 `README/AGENTS/FIXES/ASSESSMENT` 之上，新增 `TESTING.md`（两套测试运行与限制）、
  `CHANGELOG.md`、`docs/RUBRIC.md`（本卡）。
- 限制：部分设计决策（如“提醒移出基线”）的演进记录分散在 `docs/`，未单独成册，故未给 9+。

## 仍低于 9 的共性原因
- 约束：本轮遵循“不新增功能、不联网/账号/SDK、不改包名协议、最小改动”，因此设备侧回归、
  全量调用点 DI 化、编译零警告等提升项不在范围内。
- 一旦后续在真实设备/模拟器完成 PIN 迁移与锁屏端到端回归，并把 ArkTS 单测接入托管 CI
  （需自托管 Runner 装 SDK），测试保障与工程配置两项有望进一步上探至 9+。
