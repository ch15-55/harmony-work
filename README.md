# 轻账本 · HarmonyOS 课程项目

轻账本是面向手机的本地记账应用。本仓库包含用户补充的原始源码、发布包提取资料、实测评估和开发规范。

**原始源码已补充至 `harmony/`。** 在英文临时路径副本中，已完成 `default@CompileArkTS` 编译与签名打包，产出 `entry-default-signed.hap`（包名、版本、权限与发布包一致）；中文原路径仍被 Hvigor 的路径检查拒绝。源码核验见 [源码核验](docs/SOURCE_REVIEW.md)，F01–F05 的修复与验证结果见 [修复记录](docs/FIXES.md)。**尚未完成设备/模拟器上的界面回归**，因为本机没有可用的 HarmonyOS 模拟器镜像。

`harmony/build-profile.json5` 含本机证书路径与签名口令，已加入 `.gitignore`，只保留在本机；仓库提交的是不含密钥的 `harmony/build-profile.example.json5`。本轮未修改原配置内容，也未提交或推送。

## 已确认的信息

| 项目 | 结果 |
| --- | --- |
| 应用名 | 轻账本，来自包内隐私政策和用户协议 |
| 包名 / 版本 | `com.lifeledger.app` / `1.0.0` |
| 模块 / 构建模式 | 单个 `entry` 模块 / `release` |
| 设备 / API | `phone` / compatible 20、target 20 |
| 编译 SDK 字段 | `26.0.0.105`，不据此推断 IDE 版本 |
| 页面注册 | 24 个，包含记账、统计、预算、备份、应用锁等 |
| 模块线索 | 103 条字节码中的模块路径，不能视为已恢复的源文件 |
| 权限声明 | 包内 `module.json` 未声明 `requestPermissions` |

已在独立的 HarmonyOS 6.1.1 / API 24 手机模拟器中安装并测试原发布包。核心收支、编辑删除、统计及备份恢复可用；新增账户保存受到状态栏重叠问题阻挡，另有预算、币种刷新问题。应用锁不做重试惩罚是原 PRD 的选择，属于加固建议。详细复现、截图和覆盖范围见 [实测评估报告](docs/ASSESSMENT.md)。

## 目录

```text
.
├── README.md                 # 仓库状态、复核和 Git 上传方法
├── AGENTS.md                 # 人和 AI 共同遵守的仓库规则
├── CHANGELOG.md              # 版本变更与验证记录
├── TESTING.md                # 两套测试（Python / ArkTS）的运行与限制
├── .github/
│   └── workflows/build.yml   # CI：无需 SDK 的校验 + 自托管 Runner 的完整构建门禁
├── harmony/                  # 用户补充的原始 DevEco 工程
├── docs/
│   ├── ASSESSMENT.md         # 现有功能实测、问题复现和评价
│   ├── SOURCE_REVIEW.md      # 原始源码、编译验证及问题定位
│   ├── FIXES.md              # F01–F05 修复、构建与验证记录
│   ├── RUBRIC.md             # 团队标尺七维度评分卡（v1.1 → v1.2）
│   ├── review/               # 实测结果、SQL 检查结果和截图
│   ├── SOURCE_GATE.md        # 源码门禁：缺件清单与修复落点
│   └── SOURCE_RECOVERY.md    # 找回源码及接入工程的方法
├── tools/
│   ├── build_ascii.ps1       # 中文路径下的一键构建（复制到英文临时目录）
│   ├── test_ascii.ps1        # 中文路径下的 ArkTS 单测（复制到英文临时目录 + hvigor test）
│   ├── unpack_app.py         # 可重复拆包、SHA-256 清单、只读校验
│   ├── audit_existing_package.py # 原包 SQL 的合成数据复核
│   └── test_unpack_app.py    # 路径安全、覆盖保护和复核测试
└── recovered/
    ├── inventory.json        # 包指纹、文件指纹、路由和模块线索
    ├── app/                  # 原样提取的 pack.info、pac.json
    └── entry/                # 原样提取的配置、图标和协议等
```

原 `.app`、提取的 `.abc`、`__MACOSX/` 均保留在本机并由 `.gitignore` 排除。图标、`resources.index` 是提取资料，可以纳入 Git；`module.json` 是产物配置，不是源码侧 `module.json5`。

## 构建应用

Hvigor 不接受含中文字符的工程路径（`00306003`），因此提供一键脚本：把 `harmony/` 复制到 ASCII 临时目录、调用 DevEco 自带 `hvigorw` 构建，并把 HAP 复制到 `local-data/fixes/`（已忽略，不入库）。

```powershell
powershell -ExecutionPolicy Bypass -File tools\build_ascii.ps1
```

需要 DevEco Studio 自带 SDK 与 `hvigorw`；脚本默认查找 `E:\DevEco Studio`，可用 `-DevEcoHome` 指定。签名使用本机 `harmony/build-profile.json5`，仓库内只有模板。

## 运行测试

两套测试覆盖的边界不同，详见 `TESTING.md`。

**ArkTS 本地单测（需 DevEco Studio + HarmonyOS SDK）**：覆盖 F03/F04/F05 纯逻辑、金额/日期铁律、
服务层 DI 注入，共 26 例，已在本机经 `hvigorw test` 实际编译运行并全绿
（`test_result.txt` 显示 `Tests run: 26, Failure: 0, Error: 0`）：

```powershell
powershell -ExecutionPolicy Bypass -File tools\test_ascii.ps1
```

Hvigor 拒绝中文工程路径（`00306003`），该脚本会自动把 `harmony/` 复制到 ASCII 临时目录再构建。

**Python 工具单测（无需 SDK）**：

```powershell
python -m unittest discover -s tools -p "test_*.py"
```

CI（`.github/workflows/build.yml`）的 `validate` job 在 GitHub 托管 Runner 上跑绿上述 Python 校验
与结构检查；ArkTS 完整构建与单测为 `harmony-build` job，仅在自托管 Runner 且配置了
`DEVECO_SDK_HOME` 时触发（GitHub 托管 Runner 不预装 HarmonyOS SDK）。

## 复核拆包结果

要求 Python 3.10+，只用标准库，无需安装依赖。在仓库根目录执行：

```powershell
python tools/unpack_app.py
python tools/unpack_app.py --check
python -m unittest discover -s tools -p "test_*.py"
```

首次命令生成 `recovered/`；再次运行只接受内容相同的已有文件。发现差异会停止，避免覆盖人工修改。`--check` 不写文件，核对原包和提取结果的每个字节；它不是签名认证或应用功能测试。

克隆仓库后，单元测试可以独立运行；重新拆包及 `--check` 需要自行把原发布包放回根目录。字节码默认不上传，因此克隆结果不包含可运行应用。

现有功能测评另包含 13 项原始 SQL 检查，与拆包工具的 7 项单元测试分别计数，不冒充应用测试。使用 SDK 自带的 `ark_disasm` 生成反汇编文件后可复核：

```powershell
ark_disasm recovered/entry/ets/modules.abc local-data/review/modules.pa
python tools/audit_existing_package.py --disassembly local-data/review/modules.pa --output local-data/review/sql-results.json
```

将 SDK 的 toolchains 目录加入本机 PATH 后使用上述工具；这不是源码构建命令。界面实测步骤、环境、样本边界和结果在评估报告中单独记录。

## 上传 Git

本目录已初始化本地 Git 并绑定远程 `https://github.com/ch15-55/harmony-work.git`（已推送）。
提交前先阅读 [仓库规则](AGENTS.md)，按 `类型: 内容` 写提交信息，并确认本地单测与 Python 校验均通过：

```powershell
git status --short
git add -A
git diff --cached --stat
git commit -m "test: 新增 26 例 ArkTS 本地单测与 DI 接缝"
git push
```

不要使用 `git add -f` 上传被排除的发布包、字节码或签名文件（`harmony/build-profile.json5`
已被 `.gitignore` 排除，仅 `build-profile.example.json5` 入库）。Git 的忽略规则只影响未跟踪文件，
不能移除已经提交的文件，参见 [Git 官方说明](https://git-scm.com/docs/gitignore)。

当前没有指定开源许可证；原包中的作者署名、协议和权属声明按原样保留。
