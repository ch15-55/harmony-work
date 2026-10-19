# 测试与验证

本仓库有两类自动化测试，覆盖的边界不同，请勿混为一谈（见 `AGENTS.md` 第 1、7 节）：

| 测试 | 运行环境 | 是否需要 DevEco/SDK | 说明 |
| --- | --- | --- | --- |
| Python 工具单测 | 任意装了 Python 3.10+ 的机器 | 否 | 拆包工具的路径安全、覆盖保护、复核逻辑 |
| ArkTS 本地单测 | 本机 DevEco Studio + HarmonyOS SDK | 是 | 金额/日期/锁屏纯逻辑，以及服务层 DI 注入 |

## 1. Python 工具单测（无需 SDK）

只用标准库，验证 `tools/unpack_app.py` 等工具的健壮性。在仓库根目录执行：

```powershell
python -m unittest discover -s tools -p "test_*.py" -v
```

`tools/test_unpack_app.py` 的用例不依赖原发布包，克隆后即跑绿；`unpack_app.py --check`
才需要把原 `.app` 放回本地（参见 `README.md`）。

## 2. ArkTS 本地单测（需 DevEco Studio + SDK）

### 2.1 为什么需要英文临时目录

Hvigor 拒绝含中文字符的工程路径（`00306003`）。本仓库位于含中文的目录，
直接原地跑 `hvigorw test` 会失败。脚本 `tools/test_ascii.ps1` 负责把
`harmony/` 复制到 `%TEMP%\lifeledger-test`（ASCII 路径），再调用 DevEco 自带的
`hvigorw` 运行单测，最后把结果留在临时目录。

### 2.2 运行步骤

```powershell
# 默认查找 E:\DevEco Studio；DevEco 装到别处时用 -DevEcoHome 指定
powershell -ExecutionPolicy Bypass -File tools\test_ascii.ps1
```

脚本会：

1. 校验本机 `harmony/build-profile.json5`（含签名配置，已被 `.gitignore` 排除）存在；
2. 复制工程到 ASCII 临时目录；
3. 设置 `DEVECO_SDK_HOME` 并运行 `ohpm install`（拉取 `@ohos/hypium` 测试框架）；
4. 运行 `hvigorw --mode module -p product=default test`；
5. 输出 `hvigor test exit code`；`0` 表示构建与测试均通过。

### 2.3 测试结果位置

```
%TEMP%\lifeledger-test\entry\.test\default\intermediates\test\coverage_data\test_result.txt
```

该文件逐条列出每个 `class` / `test` 的 `result=Success|Failure|Error`，末尾有汇总
（`Tests run / Failure / Error / Pass / Ignore`）。提交前请确认 `Failure: 0, Error: 0`。

## 3. 测试覆盖范围

入口固定为 `harmony/entry/src/test/List.test.ets`（Hvigor 的单元测试插件硬编码了该路径）。
当前用例（截至 v1.2）：

- **BudgetTextUtil**（F03）：预算占比文案边界——0%、`<1%`（旧逻辑 `Math.ceil` 会误显 1%）、
  1%~100% 一位小数、超支整数百分比。
- **AppLockLogic**（F05）：纯逻辑锁屏状态机——连续错误达上限进入等待期、等待期内顺延截止、
  成功清零、过期归一化、跨重启的数据持久化形态、`attemptsLeft` 计数。
- **MoneyUtil**：金额铁律——分→元格式化（符号/千分位/两位小数）、收入 `+` 号、
  元字符串→分（规避浮点误差）、非法输入归零、CSV 专用格式。
- **MoneyUtil 多币种**（F04）：展示由基础金额换算、绝不回写基准、非法汇率回退 1 避免 `Infinity`。
- **DateUtil**：时间铁律——`isDateOnly`、`formatDate/formatTime`、`monthKey/monthLabel`、
  `startOfMonth/endOfMonth` 左闭右开月区间。
- **ServiceLocator**（DI）：默认绑定指向真实实现且纯函数服务可直接驱动；可注入内存桩脱离
  Preferences/加密库验证；`reset()` 恢复真实实现。

## 4. 尚未能在本机跑的测试（限制）

本机没有可用的 HarmonyOS 模拟器镜像（`hdc list targets` 为空），以下用例已编译就绪、
属于「已编译待运行」，需要真实设备/模拟器才能验证：

- PIN 迁移（旧 SHA-256 凭据 → PBKDF2 新格式）成功即升级；
- PBKDF2 派生耗时与锁定交互；
- 锁屏等待期跨后台切换/进程重启的端到端表现；
- 读屏无障碍（TalkBack/屏幕朗读）的口令输入播报。

它们依赖 `@kit.ArkData` / `@kit.AbilityKit` 等运行期能力，无法在本地单测运行时驱动，
因此以纯逻辑抽取（`AppLockLogic`）配合桩注入（`ServiceLocator`）来覆盖其可测部分。

## 5. 持续集成（CI）

`.github/workflows/build.yml` 含两个 job：

- `validate`：在任何 GitHub 托管 Runner 上跑绿——Python 工具单测 + 签名文件未被提交校验
  + 结构健全性检查（测试入口、`oh-package.json5` 存在）。
- `harmony-build`：仅当仓库变量 `RUN_HARMONY_BUILD=true` 且自托管 Runner 上设置了
  `DEVECO_SDK_HOME` 时触发，调用 `tools/test_ascii.ps1` 跑完整 HAP 构建与 ArkTS 单测。
  未配置时自动跳过，避免 GitHub 托管 Runner（无 SDK）误报失败。

说明：GitHub 公开 Runner 不预装 HarmonyOS SDK，且 SDK 分发需 AGC 授权，故 ArkTS 单测
作为本地/自托管门禁，而非 GitHub 托管 Runner 门禁。
