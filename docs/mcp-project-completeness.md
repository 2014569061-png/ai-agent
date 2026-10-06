# NEXUS Agent 完善情况分析

> 结论、证据与下一步。基于 2026-09-22 对工作区 `main` 分支的**实际核查**，不是对既有文档的转述。
> 相关文档：`README.md`、`CHANGELOG.md`、`docs/ui-improvement-handoff.md`。

## 0. 一句话结论

功能面已经相当完整（40 个页面、303 个源码文件、1002 项测试全绿、analyze 零问题、覆盖率过门槛）。

**当前最大的"不完善"不在代码里，而在交付链上**：约四天的工作量（118 个改动文件 + 59 个新文件，新增约 1.4 万行）全部处于未提交状态——没有回滚点，也没被 CI 跑过；同时 `docs/ui-improvement-handoff.md` 已经明显滞后（仍称 C4 待做、测试 888 项、覆盖率 51.65%）。

## 1. 核查方法与证据

| 检查 | 命令 | 结果 |
|---|---|---|
| 静态分析 | `flutter analyze --no-pub` | No issues found（6.9s，exit 0） |
| 全量测试 | `flutter test --no-pub` | **1002 项全部通过**（32s，末行 `+1002: All tests passed!`） |
| 覆盖率 | `flutter test --coverage --no-pub` + `dart run tool/check_coverage.dart coverage/lcov.info 48.5` | 自研代码 **57.30%**（18321/31975）；含生成代码 52.10%（21882/42004）；门槛 48.5% 通过 |
| 代码规模 | `find lib -name '*.dart' \| wc -l` 等 | lib 303 文件 / 104,138 行；test 154 文件 / 25,180 行 |
| 分层 | 同上 | domain 13 / 2,432 行；application 81 / 19,153；infrastructure 70 / 35,724；presentation 138 / 46,529 |
| 遗留标记 | `grep -rn "TODO\|FIXME\|HACK" lib` | **0**；`// ignore:` 抑制 0 处 |
| Git 状态 | `git status --porcelain` | 118 个已跟踪文件被改（+9,259 / −2,560）、59 个未跟踪、1 个删除；最后一次提交 2026-09-18 16:06 `release: align v0.9 APK metadata` |
| 发布产物 | `ls build/app/outputs/flutter-apk` | `app-release.apk` 21,647,388 B，构建于 2026-09-22 00:10 |
| 版本元数据 | `pubspec.yaml` ↔ `android/app/build.gradle.kts` ↔ `README.md` | 0.9.0+94 ↔ versionName "0.9.0" ↔ 发布 tag `v0.9`，三者自洽 |
| CI | `.github/workflows/ci.yml`、`.github/workflows/release.yml` | analyze+test 挂 main / feature/** / PR；release 走 `v*` tag |

## 2. 阶段完成度核实（文档 vs 代码）

| 项 | 交接文档口径 | 代码核查结果 | 判定 |
|---|---|---|---|
| A1 三段式上下文条 | 已完成 | `reservedOutputTokens` 出现在 18 个文件；`lib/presentation/chat/widgets/context_budget_bar.dart` + `test/context_budget_bar_test.dart` | ✅ 属实 |
| A2 压缩视觉闭环 | 已完成 | `lib/presentation/chat/widgets/tool_activity_section.dart:268` 有"已压缩"徽标；恢复路径按 `compressedToolResultMark` 判定（`lib/application/chat_controller.dart:741/744/808`） | ✅ 属实 |
| A3 遥测可跳转 | 已完成 | `anchorMessageId` 已进 `lib/domain/context_insights.dart`、`lib/application/agent_executor.dart`、`lib/presentation/chat/widgets/session_metrics_sheet.dart`，并有对应测试 | ✅ 属实 |
| B1 共享预算条 | 已完成 | `context_budget_bar.dart` 已抽出，HUD 与指标面板共用 | ✅ 属实 |
| B2 拆分 chat_page | 3396 → 约 3235 行 | `chat_page.dart` 当前 **3468 行**：拆分确实做了，但随后又长回去了 | ⚠️ 部分回退 |
| B3 sheet 重定位 | 已完成 | `session_context_sheet.dart` 已删除、`session_configuration_sheet.dart` 新增（两者都未提交） | ✅ 属实 |
| C1 无障碍 | 已完成 | presentation 层 `Semantics(` 46 处；`a11y_compliance_test.dart`、`ui_refactor_regression_test.dart` 在守 | ✅ 属实（覆盖仍偏薄，见 §4） |
| C2 会话切换骨架屏 | 已完成 | `conversation_restore_skeleton.dart` + `test/conversation_restore_skeleton_test.dart` | ✅ 属实 |
| C3 HUD 快捷压缩 | 已完成 | `lib/presentation/chat/widgets/session_metrics_bar.dart` 带 `onCompress`；`test/session_metrics_hud_compress_test.dart` | ✅ 属实 |
| **C4 未配置 Provider 引导条** | **待做** | **实际已完成**：`lib/presentation/chat/widgets/provider_setup_hint.dart`（129 行）+ 接线 `lib/presentation/chat/chat_page.dart:3058`（条件 `!providerConfigured && !loading && !restoringConversation`）+ `test/provider_setup_hint_test.dart`（4 项，含 360x800 @ textScale 1.3 溢出守护） | ❌ **文档滞后** |

**结论**：交接文档写的"下一步 = C4"已经过期。四天 WIP 里不仅 C4 完成，还一并带入了 Skill 市场 facade、8 个内置开发 Skill、运行阶段与计时、Markdown 分档渲染、统一按压反馈等（见 `CHANGELOG.md` 的 `[Unreleased]` 六条）。

## 3. 功能面盘点

- **40 个页面**（`lib/presentation/**/*_page.dart`）：chat、dashboard、agents、projects（含 change set / git / remote execution）、workspace（编辑器 / 开发工作台）、terminal、mcp、knowledge、memory、vault、scheduled、audit、diagnostics、settings（16 个子页）等。
- **10 个内置 Skill**（`assets/skills/`）：android-build、mobile-dev-basics + 新增 8 个开发类 code-review / debugging / flutter-ui / api-integration / database-design / testing / git-workflow / technical-writing。
- 多 Provider（OpenAI 兼容 / Anthropic / Gemini / 代理托管）、MCP 客户端、终端（含 SSH 会话）、WorkManager 定时任务、TTS 朗读、Sentry 脱敏、锁屏/通知栏审批、桌面小组件。
- 上下文预算体系（`ContextBudget` / `ContextWindow` / 压缩 planner+applier / 请求级快照）与遥测面板已成体系。

## 4. 工程健康度

**做得好的**

- analyze 零问题；`TODO` / `FIXME` / `HACK` / `// ignore:` 全部为 0——没有靠抑制换取绿灯。
- 1002 项测试，且有 7 个**守护型**测试：`a11y_compliance_test`、`code_quality_guard_test`、`vault_coverage_guard_test`、`bugfix_regression_test`、`ui_refactor_regression_test`、`chat_visual_regression_test`、`nexus_guard_test`。
- 覆盖率门槛工具口径正确：分母排除 Drift 生成代码，`tool/check_coverage.dart` 的注释解释了旧口径为什么会失真。
- CI 同时覆盖 `main` 与 `feature/**` 以及所有 PR，避免"门禁形同虚设"。

**仍不足**

- 覆盖率 57.30% 对 46.5k 行的 presentation 层偏低；`chat_page.dart`（3468 行）、`task_details_page.dart`（1482 行）、`run_analysis_page.dart`（962 行）等大文件是主要盲区。
- 无障碍：40 个页面只有 46 处 `Semantics(`、12 处 `Tooltip(`，`semanticsLabel` 0 处。
- 国际化：`lib/presentation/l10n/app_strings.dart` 有 334 行文案表，但只有 23 个文件引用它；其余仍是硬编码中文（当前为中文单语产品）。
- presentation 层 138 个文件散在 29 个子目录，`chat_page.dart` 仍在回长，结构治理（B2）只完成了一半。

## 5. 风险清单（按优先级）

**P0 — 交付链**

1. 118 个改动文件 + 59 个新增文件（新增 Dart 约 5,072 行）全部未提交；工作区是唯一副本，没有回滚点，无法 review、无法 bisect。
2. 这批成果**从未经过 CI**：ci.yml 只在 push / PR 触发，而所有改动都还在本地。
3. 本地与 origin 都有 `feature/mature-agent` 分支，但工作停留在 `main` 的未提交状态——需要明确这批改动最终落到哪个分支、如何分批提交。

**P1 — 验证缺口**

4. 真机验证未执行：当前 `adb devices -l` 为空（无设备连接），交接文档第 9 节清单（压缩标记持久性、大字溢出、深色模式可读性、杀进程恢复、长列表掉帧等）全部待验。
5. 本机缺 MSVC / `link.exe`，`super_native_extensions` 的 Rust 构建会失败，靠 Gradle 复用预编译 `.so` 绕过；换机器或 `flutter clean` 后可能真的构建不出来，正式 Release 前应装 Visual Studio Build Tools（C++ 工作负载）。
6. 发布产物缺少可追溯性：`app-release.apk`（2026-09-22 00:10）没有对应的 SHA-256 sidecar 与 commit 记录；`dist/` 里最新还停在 `0.8.9_93`（2026-09-16）。

**P2 — 体验与维护**

7. 输入区上方最多可能叠加 5 条横条（ProviderSetupHint → SessionMetricsHud → ContextBudgetHint → Skill 提示槽 → 输入胶囊）；代码里已有"避免三条 44dp 同类横条在 360dp 屏上叠加"的注释，小屏真机仍值得实测。
8. 文档漂移：交接文档的测试数（888）、覆盖率（51.65%）、`chat_page.dart` 行数、C4 状态、"下一步"结论、`session_context_sheet` 引用均已过期；`pubspec.yaml` 注释引用的 `NEXUS_开发期技术方案_P1-P3.md` 在仓库中不存在。
9. 根目录杂物：`smoke_*.png` / `fixed_*.png` / `final_agent_*.png`（真机证据，已 gitignore，属有意保留）、`NUL`（异常文件）、`preset-*.{md,html,json}`、`windows-2a47ad.dshpreset`、`natgeo_landscape_*.jpg`、`dsh-context-source/`（16 项的外来子项目）。

## 6. 建议的下一步（按性价比排序）

1. **先落盘**：把 WIP 按主题拆成可 review 的提交，例如——上下文预算重构 / 压缩闭环 / Skill 市场与内置技能 / 运行阶段与计时 / Markdown 分档渲染 / UI polish 与测试；推到 `feature/mature-agent` 或新分支后让 CI 跑一遍。
2. **更新状态文档**：修正交接文档里所有过期数字与 C4 状态（本文件可作为新基线）。
3. **补真机验证**：接入设备后执行交接文档第 9 节清单，重点是压缩标记在重启后的持久性与大字溢出。
4. **补大文件测试**：优先 `chat_page.dart`、`task_details_page.dart` 的关键路径，把覆盖率从 57.3% 推向 60%+。
5. **发布规范化**：为 release APK 生成 SHA-256 sidecar，并记录对应的 commit / 工作区状态。
6. 次要：清理根目录杂物；`AppStrings` 迁移到 ARB + intl，或把"仅中文"明确为产品决策写进 README。

## 7. 复现命令

```powershell
flutter analyze --no-pub
flutter test --no-pub
flutter test --coverage --no-pub
dart run tool/check_coverage.dart coverage/lcov.info 48.5
git status --porcelain | wc -l
```
