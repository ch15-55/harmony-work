# 变更日志

本仓库遵循 `类型: 内容` 的提交约定（见 `AGENTS.md`）。以下按版本汇总已验证的改动。

## [1.2.1] - 2026-10-19 — 视觉改版与页面转场动效

> 目标：按 HarmonyOS Design 规范（4vp 网格 / 字号阶梯 / 圆角阶梯 / 克制配色）整体提升美观度，
> 并让页面切换流畅。纯展示层改动，不动数据层、协议与功能。

### 新增
- **主题令牌重构**（`constants/ThemeConstants.ets`）：色板新增渐变卡文字色
  `textOnGradient`/`textOnGradientSecondary`、按压态 `bgPress`、功能色淡底
  `primarySoft`/`expenseSoft`/`incomeSoft`/`warningSoft`；新增 `cardShadow()` /
  `cardBorderWidth()` 统一收口卡片层次（浅色柔和投影、深色 1vp 描边），组件不再散落阴影参数。
- **资源令牌**：`float.json` 新增 `font_display`（34fp 展示级数字）、`radius_card_sm`（12vp），
  卡片阴影半径 8vp → 12vp；浅色页面底色微调。
- **全站转场动效**：19 个页面统一 `pageTransition()`——二级页右侧滑入（Push 300ms EaseOut /
  Pop 280ms EaseIn），记账页底部滑入（模态编辑感），Tabs 根页被覆盖时 -10% 视差左移呼应；
  Tabs 增加 260ms 切换动画。插入脚本 `tools/add_page_transition.py`（幂等）。

### 优化
- 资产大卡：总资产数字升至 34fp 展示级字号，渐变卡文字色全部走色板（消除组件内硬编码色值）。
- 首页月度汇总 / 预算 / 最近记录、统计页四卡、我的页四组、明细页月份切换容器：统一卡片层次。
- 预算「去设置」按钮改淡底样式；记账页金额大字与键盘回显同步 34fp；类型切换胶囊 180ms 平滑过渡。
- 搜索栏加高至 44vp、放大镜符号配色统一；流水条目卡片态统一阴影；空态留白收敛。

### 验证
- 完整构建：`tools/build_ascii.ps1` → `BUILD SUCCESSFUL`（仅原有警告）。
- ArkTS 单测：`tools/test_ascii.ps1` → 26/26 通过，无回归。
- 已知取舍：`stateStyles` 按压态在本机 ArkTS 编译器（ets-loader）存在内部崩溃
  （`Node must have a real position`），已移除相关用法；其余动效（转场/过渡）不受影响。

## [1.2.0] - 2026-10-19 — 测试保障与架构可测性

> 目标：把团队标尺从 6.0/10 提升到各项约 8.5，重点补齐三大致命伤（无 git、无 CI、架构不可测）。

### 新增
- **ArkTS 本地单测套件（26 例，全绿）**：入口 `harmony/entry/src/test/List.test.ets`，
  经 DevEco 工具链 `hvigorw test` 实际编译并运行通过（`BUILD SUCCESSFUL`，`Failure: 0, Error: 0`）。
  - 纯逻辑抽取 `utils/AppLockLogic.ets`（F05 锁屏状态机）、`utils/BudgetTextUtil.ets`（F03 占比文案），
    将可测逻辑从静态 Service 中剥离。
  - 覆盖 MoneyUtil（金额铁律）、多币种换算（F04）、DateUtil（时间铁律）、ServiceLocator DI 注入。
- **服务层 DI 接缝**：`service/ServiceContracts.ets`（接口契约）+ `service/ServiceLocator.ets`
  （轻量定位器，默认绑定经适配器委托真实静态实现，可被测试桩替换）。适配器写法规避 ArkTS
  严格模式对 `as unknown as` 的禁令（`arkts-no-any-unknown`）。
- **测试工具链**：`tools/test_ascii.ps1`（复制到 ASCII 临时目录 → `ohpm install` →
  `hvigorw test`），规避 Hvigor 的中文路径限制（`00306003`）。
- **CI 工作流**：`.github/workflows/build.yml`（`validate` 无需 SDK 跑绿；`harmony-build` 在
  自托管 Runner + SDK 时跑完整构建与 ArkTS 单测）。
- **文档**：`TESTING.md`（如何跑两套测试与限制）、本文件 `CHANGELOG.md`、评分卡 `docs/RUBRIC.md`。

### 修复
- `service/AppLockService.ets`：补充缺失的 `AppConstants` 导入（`isValidPin` 引用
  `AppConstants.PIN_LENGTH`），消除主代码中的未定义引用（此前仅因测试未引入该文件而未被发现）。
- `entry/oh-package.json5`：将 `@ohos/hypium` 固定为 `1.0.29` 并置于 `dependencies`
  （OhmUrl 解析需要，注册表无 `1.0.0`），使本地单测框架可被 `ohpm install` 拉取。

### 验证
- ArkTS 单测：`tools/test_ascii.ps1` → 26/26 通过，退出码 0。
- 完整构建：`tools/build_ascii.ps1` → HAP 构建 `BUILD SUCCESSFUL`，签名配置使用本机
  `build-profile.json5`（已被 `.gitignore` 排除，仓库仅含 `build-profile.example.json5`）。
- Python 工具单测：`python -m unittest discover -s tools -p "test_*.py"` → 7/7 通过。

### 已知限制（非缺陷）
- 本机无 HarmonyOS 模拟器镜像，PIN 迁移、PBKDF2 耗时、锁屏跨重启、读屏等需设备的用例
  已编译就绪但未能在本机运行；其可测部分由纯逻辑抽取 + 桩注入覆盖。
- HarmonyOS SDK 不在 GitHub 托管 Runner 预装，故 ArkTS 单测为本地/自托管门禁。

## [1.1.0] - 前期 — 源码恢复与 F01–F05 修复

- 用户补充原始 DevEco 工程至 `harmony/`；英文路径副本下完成 ArkTS 编译与签名打包。
- 修复 F01–F05（含 PIN PBKDF2 派生、锁屏重试节制、预算占比边界、多币种换算口径、信息表达），
  详见 `docs/FIXES.md` 与 `docs/ASSESSMENT.md`。
- 源包资料保留于 `recovered/`，拆包与复核工具见 `tools/`。

## [1.0.0] - 原始发布包

- 轻账本 HarmonyOS 课程项目初始发布包（本地记账，包名 `com.lifeledger.app`）。
