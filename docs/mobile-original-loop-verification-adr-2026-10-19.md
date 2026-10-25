# ADR：验证与有限修复复用原运行循环

> 2026-10-19 恢复实施已修正 resumeTask 的“已应用旧断点”分支。现在只凭新鲜快照、同run/version终态head及终态回执原子收敛；不再无run身份清断点后无条件写completed。缺证明时提示核实，不重放。此增量不代表其他兼容入口已审计完成，最新证据见 `mobile-next-major-resume-2026-10-19.md`。

日期：2026-10-19。决策采用；迁移与验收仍进行中，不代表 F21/A27 或整版完成。

## 问题
旧 chat/resume 先结束并封闭原 AgentExecutor，再运行 DevelopmentLoopFinalizer；修复通过同 task 新 Headless 发起。新 run 可能转移计划 head，导致旧 finalizer/ACK 被原有正确所有权屏障拒绝。不得通过降低屏障、替换当前 head 或复制命令/审批引擎掩盖问题。

## 决策
1. caller 生成的 executionRunId 贯穿租约、Gateway、Headless、原 executor、计划、日志、结果与 ACK。普通新运行缺省只生成一次。
2. 原 AgentExecutor 的异步 beforeFinish 在完成/seal 前调用，前后同步/核对原决策 revision；纠正先赢则旧草稿失效，原消息循环继续。真正发生的工具事实仍保留。
3. DevelopmentRunCompletion 只组合原 finalizer/verification/RunPlanStore。校验 head 后捕获 token；原会话建立、每条命令都先持久 claim，之后按原 effect settle。DB 写失败、重复/stale claim 不得执行；unknown 不盲重放。
4. 有限修复返回 TurnContinuation，不新建同 task 执行器，不新建租约，不增加原 maxSteps/Token/取消预算。继续检查使用原服务重跑全部原检查，不能只重跑失败项伪造通过。
5. 修复允许读/列目录/搜索/仓库映射/写/编辑/补丁；请求 manifest 和实际派发双层限制。模型返回未列工具时以 none 错误结算，绝不触发审批或工具动作。用户有效纠正进入新决策后回到普通工具策略，而不是沿用旧自动修复策略。
6. 自动验证和修复保留现有偏好、文件/终端能力、模型配置与普通审批。日志、差异、引用均是数据，不授权额外工具；“已请求修复”记录 deferred 而不是成功。失败、取消、无实际必需检查均不得标记 verified。
7. 取消不能只靠关闭 session：现有 closeSession 只释放会话记录。原同步终端在其自身串行槽按 canContinue 以100ms周期停止运行时；组合层还必须 join 验证清理 Future 后才释放其工作区租约。两调用方现已 join；必需验证失败抛错阻止成功 seal。join/本地撤销合同已通过，实际 Linux 命令中止尚未验收。

## 证据与边界
已完成同一 x64 debug APK 234/234 + 审批 UI 隔离链，分析零问题24.1s/构建23.6s；包含91协议及原九套143检查，不合并不同APK结果。90例中间APK因默认环境签名不匹配未安装、不计通过，后续固定local构建环境并确认签名一致后保留数据更新成功。新检查覆盖双层 allowlist、真实空工作区 finalizer 在原循环 seal 前运行、foreign/pending control 零 terminal factory；它们仍不是 Linux 命令、外部模型自动修复、独立进程崩溃或通知插件端到端证据。三次真实模型授权已耗尽；不用宿主测试套件、不操作真机。

## 兼容与后续
beforeFinish、verification guard、显式 runId 都是原 API 的可选扩展；未绑定旧调用保持既有行为。此兼容不授权新的异步回调无版本写入。继续审计其他 caller、跨 restore 的旧回调、恢复错误分支、通知插件和长期压力；原 W00–W21/F01–F22、A01–A28/S01–S12 未完成门禁不得由本 ADR 抵消。
