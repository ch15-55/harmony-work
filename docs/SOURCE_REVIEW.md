# 原始源码核验

日期：2026-10-18。用户补充的工程位于 [`harmony/`](../harmony/)。本轮只检查源码、验证编译并更新说明，没有修改应用源码、签名配置、功能或权限。

核验期间，原目录出现外部更新，已包含多项修复代码。下面以最后一次完整同步的工程副本为准；编译期间校验源码与资源指纹未再变化。之前的发布包测试不能当作这些新代码的回归结果。

## 核验结果

- 存在真实的 ArkTS/ArkUI 页面、组件、业务服务与完整的 Hvigor 工程入口。
- 共 105 个 `.ets` 模块，覆盖原发布包识别出的全部 103 条模块路径，另有 `ImageService` 与 `PermissionGuard`。
- 24 条页面路由与原发布包一致；相对源码导入未发现缺失文件。
- 源码和原包均声明版本 `1.0.0`、包名 `com.lifeledger.app`；源码模块没有声明请求权限。
- 包内隐私政策与用户提供的源码文本存在内容差异，不能只凭版本号或目录一致就断言这是生成原包的精确提交。
- 没有在本轮的文件检索中发现测试入口；本轮没有执行新增源码构建产物的设备回归。

## 编译验证

已使用本机 Hvigor `6.26.4`，在独立英文路径副本运行：

```powershell
hvigorw --mode module -p product=default -p module=entry@default -p buildMode=debug --sync default@CompileArkTS --no-daemon
```

最终结果：退出码 0；日志确认 `:entry:default@CompileArkTS` 完成，并生成 `modules.abc`。本次仅确认 ArkTS 编译，没有完成签名打包、重新安装或修复后的界面验收。

最终编译日志有 503 条 `ArkTS:WARN` 记录，包括 API 弃用、潜在异常处理及导出 `@Entry` 组件提示。警告条数不能等同于运行缺陷数。脱敏日志保存在本机被 Git 忽略的 `local-data/review/source-compile-latest-full.log`。

当前原目录包含中文，Hvigor 报 `00306003 Invalid project path`。英文副本可以通过编译，因此这里首先是构建路径约束。原始工程没有移动，也未通过改源码规避该错误。

首次工具初始化还遇到 npm 缓存错误，使用本任务独立缓存后解决；没有删除用户原缓存。

## 之前问题的源码定位

| 问题 | 源码证据 | 判断与修复方向 |
| --- | --- | --- |
| 新增账户页顶部遮挡 | 旧代码使用固定顶部 padding；最新 [AccountEditPage.ets](../harmony/entry/src/main/ets/pages/AccountEditPage.ets#L161) 已改用处理安全区的 `NavTitleBar` | 已看到针对性修复，需重新验证保存与返回是否可点击 |
| 预算键盘遮挡 | 最新 [BudgetSettingPage.ets](../harmony/entry/src/main/ets/pages/BudgetSettingPage.ets#L171) 已将保存按钮移至滚动表单之外的操作区 | 已看到针对性布局调整，键盘弹出后的可达性仍需实测 |
| 预算比例失真 | 最新 [BudgetProgressCard.ets](../harmony/entry/src/main/ets/components/home/BudgetProgressCard.ets#L66) 使用 `usedPercentText`，低于 1% 显示“<1%” | 旧的向上取整口径已被替换，仍需验证边界与超支显示 |
| 最近记录币种未同步 | 最新 [TxListItem.ets](../harmony/entry/src/main/ets/components/list/TxListItem.ets#L24) 订阅显示币种与汇率，金额改经 `MoneyUtil.displayIn` | 已看到针对性状态修复，仍需验证首页、明细与汇率变化的一致性 |
| PIN 无错误等待 | [PRD.md](../harmony/docs/PRD.md#L519) 原本明确不做锁定惩罚；最新 [AppLockService.ets](../harmony/entry/src/main/ets/service/AppLockService.ets#L63) 已增加失败计数与等待检查 | 原行为属于设计选择，新增的是加固。当前常量为 5 次、30 秒，需验证重启持久化并同步原需求说明 |
| 诊断 message 全为空 | 最新 [LogUtil.ets](../harmony/entry/src/main/ets/utils/LogUtil.ets#L147) 已调用 `diagMessage` 过滤导出内容，并增加结构化失败日志 | 已看到诊断改进，需用英文备注、账户名和凭据样本回归，不能仅凭过滤函数认定隐私安全 |

上述新代码由核验期间的外部修改带入，不是本轮由本助手实施。编译通过不等于上述问题已经完成运行验收。

## 上传 Git 前要处理的配置

[`harmony/build-profile.json5`](../harmony/build-profile.json5) 包含两组签名配置，其中 `keyPassword`、`storePassword` 为非空值，还依赖本机签名材料路径。本轮没有输出这些值，也没有修改配置。

提交前应将本机签名材料与密码配置移出共享版本，只保留可提交的构建模板和本机配置说明。忽略 `.p12` 等文件并不能阻止配置文件中的密码值一起被提交。目前尚未替用户提交或推送这些文件。

后续可以直接在真实源码上修复现有问题，不再需要从发布包尝试还原源码。优先顺序仍是账户保存、预算输入和比例、币种刷新；应用锁加固独立于原需求缺陷处理。
