# 工作区文件盘点与清理建议

> 后续状态：2026-09-22 已执行“整理并清理旧 APK”。以下盘点表、根目录与 Git 清单是清理前快照；当前结果见 docs/mcp-workspace-cleanup-executed-2026-09-22.md，路径映射见 artifacts/cleanup/2026-09-22/moves.tsv。

盘点日期：2026-09-22。对象：ShunCode 当前工作区（Flutter mobile_agent / NEXUS Agent，pubspec 版本 0.9.0+94）。

## 范围与结论

本次未删除、移动文件，未修改源码或配置；仅新增本报告。根目录清单完整（20 个目录、163 个文件），不是全部递归文件清单。大小来自 du -k，属于工具报告的占用估计，不保证等同于 Windows 实际释放空间。未检查外部磁盘、全局 SDK/Pub/Gradle 缓存。

工作区总计约 3.27 GiB；构建产物是主要占用，根目录则主要被日志和截图污染。

Git 短状态显示 163 条修改、1 条删除、113 条未跟踪条目（部分条目是整个目录，不能当作文件总数）。未跟踪内容包含业务源码、测试与 pubspec.yaml 引用的 assets/skills 资源。禁止直接执行 git clean -fd/-fdx 或 git reset --hard。

## 一级目录分类

| 路径 | 约占用 | 处理建议 |
|---|---:|---|
| build/ | 2.04 GiB | 主要清理目标；先停止构建、备份需要的 APK，再按明确范围删除。重建会耗时，未在本次验证可重建性。 |
| .dart_tool/ | 512.6 MiB | 不整目录删除；内含 SQLite 原生库离线缓存。确认恢复能力后再清理局部编译缓存。 |
| dist/ | 427.5 MiB | 20 个 APK + 20 个校验文件；按发布/回滚用途筛选后清理。 |
| android/ | 97.9 MiB | 源码、Gradle 配置、缓存与签名材料混合；不能整目录删除。 |
| device-check/ | 62.5 MiB | 真机截图、XML、日志、脚本；先归档验收证据，保留可复用脚本。 |
| .skill-install/ | 58.0 MiB | 外部工具安装包与解压内容；确认不再使用且无独有内容后可删。 |
| .git/ | 48.4 MiB | 保留，不手动删除对象、lost-found 或索引。 |
| assets/ | 5.9 MiB | 保留；字体、技能、Linux rootfs 等被 pubspec.yaml 引用，不按扩展名清理压缩包。 |
| lib/ | 4.5 MiB | 全部保留，含业务代码及已跟踪的 app_database.g.dart。 |
| dsh-context-source/ | 4.2 MiB | 外部工具源码，已忽略；确认无本地独有修改后移出项目或归档，不仅凭忽略规则删除。 |
| test/ | 1.3 MiB | 全部保留，新增测试尚未提交。 |
| coverage/ | 0.7 MiB | 可重新生成；保留当前验收所需报告后清旧报告。 |
| docs/ | 0.27 MiB | 保留正式报告及下载页面，不值得为省空间删除。 |
| .playwright-cli/ | 0.26 MiB | 历史浏览器快照与日志，确认无验收用途后可清。 |
| .workbuddy/ | 0.08 MiB | 工具会话/记忆，按是否需要历史决定，不自动删除。 |
| tool/ | 0.03 MiB | 保留工具源码、性能基线；不要与一次性日志混为一谈。 |
| .github/ | 0.01 MiB | 保留 CI / 发布工作流。 |
| shaders/ | 约 4 KiB | 保留，pubspec.yaml 已引用。 |
| .zcode/ | 约 4 KiB | 本地计划记录，体积很小，建议保留。 |
| .workbuddy-ai/ | 约 4 KiB | 本地记忆，体积很小，建议保留。 |

## 分阶段清理方案

### 1. 先整理根目录，不动业务文件

- `.mcp-*.log`、`tmp-mcp-*.txt`：筛选最后一次有效验证日志，其余过期日志可删除，或移动到 `artifacts/logs/2026-09-22/`。
- `smoke_*.png`、`fixed_*.png`、`final_agent_*.png`：先保留最终结果、关键失败截图，归到 `artifacts/screenshots/`，其余确认后删除。
- `natgeo_landscape_*.jpg`、`preset-*`、`windows-2a47ad.dshpreset`：外部设计素材，放到项目外的设计归档；确认不再使用再删。
- `.mcp-performance-baseline.json`、`.mcp-device-fix-quality.json`、`.mcp-final-source-hashes.txt`、`.mcp-device-fix-apk-sha256.txt`：基线/验收记录，不当普通日志批量删除，可归入 `artifacts/baselines/`。移动前检查报告或脚本中的路径引用。
- `.mcp-optimization-probe_test.dart`：先读内容，判断转为正式 test/ 测试还是一次性探针，不按 `.mcp-*` 一刀切。
- `settings.txt`、`NUL`：用途未验证，先看内容与引用再处理；Windows 保留设备名 NUL 不建议用普通命令盲删。
- `pwsh.cmd`：现有 .gitignore 注释说明它是本机 Flutter 的 PowerShell 兼容脚本，保留。
- `.gitignore`、`.metadata`、`pubspec.yaml`、`pubspec.lock`、`analysis_options.yaml`、`build-apk.bat`、README/CHANGELOG/THIRD_PARTY_NOTICES：保留。

仅移动到同一磁盘不会释放空间；这是目录整理而非磁盘清理。

### 2. 清理旧发行包，收益约 363 MiB（条件估算）

dist/ 内 19 个带时间戳 APK 和 1 个 latest APK。每个配套一个 .sha256。
建议保留 latest、最近一个带时间戳包、一个已确认可回滚包，合计约 64 MiB，其余约 363 MiB 可释放；如旧版本承担已发布版本归档用途，应先外部备份。
latest 与最后一个时间戳包大小和修改时间一致，但本次没有计算内容哈希，不能据此断言内容完全相同。不能仅保留 latest 而失去明确版本的回滚依据。

### 3. 按需清理 build/，收益约 2.04 GiB

执行前停止 flutter run、测试、构建及 Gradle 任务；先确认 build/app/outputs 下是否存在 dist/ 尚未保存的新包，必要时复制 APK 与校验信息到归档。
build/ 中可见重复路径的 app-debug.apk（各约 120 MiB）、大型 libflutter.so 和测试 dill 缓存。属于构建产物，但本次未重建验证。
只清理该明确目录，不扩展到源码、签名材料或全局依赖缓存。

### 4. 暂缓整目录清除 .dart_tool/ 与 Gradle 缓存

pubspec.yaml 记录了 SQLite 原生依赖下载网络受限；build-apk.bat 的离线检查明确依赖 `.dart_tool/hooks_runner/shared/sqlite3/build/` 中的缓存。构建脚本默认保留增量产物。
因此当前不推荐直接 `flutter clean`、`build-apk.bat --clean` 或删除整个 `.dart_tool/`。即使缓存理论可生成，也不等于本机现在能成功重建。
如需深度清理：先备份并验证原生库缓存、确认下载源可用，再考虑 `.dart_tool/flutter_build/`、build runner 缓存和 android 项目级缓存。不要动全局 Pub/Gradle 缓存。

## 不能误删与备份要求

- android/key.properties、实际使用的签名 keystore（例如 android/app/upload-keystore.jks）：属于签名配置/密钥，安全备份，不打印密钥内容、不提交到 Git。
- android/local.properties：本地 SDK 路径配置，保留。
- android/gradle/wrapper/ 与 gradlew/gradlew.bat：构建工具链，不是普通缓存。
- .gitignore 的“忽略”仅表示不提交，不表示可以删除。docs/ 大多数工程报告也被忽略，Git 不会替你备份它们。
- 清理前保存修改的源码和未跟踪新增源码，按明确文件范围做本地提交或备份；不要盲目 git add .，避免误收日志、设备隐私与密钥。
- 清理后检查 git status，对照本报告记录确认业务文件无新增删除；恢复开发时使用现有构建脚本并验证分析/测试。此次仅盘点，没有运行构建或测试。

## 后续目录约定（建议，尚未执行）

```text
artifacts/
  logs/YYYY-MM-DD/
  screenshots/YYYY-MM-DD/
  device-check/YYYY-MM-DD/
  baselines/
docs/                   # 正式文档与评审报告
lib/ test/ assets/      # 产品源码、测试与资源
dist/                  # 保留近期包与回滚包，其余外部归档
```

建议确认后为 `/artifacts/` 添加精确忽略规则。设备证据若仍放在 device-check/，可单独忽略 `/device-check/`，但应先把可复用脚本提取到 tool/ 并更新引用。不要加 `*.txt`、`*.json`、`*.dart` 等宽泛忽略。

## 根目录完整清单（盘点时）

```text
[DIR] .dart_tool
[DIR] .git
[DIR] .github
[DIR] .playwright-cli
[DIR] .skill-install
[DIR] .workbuddy
[DIR] .workbuddy-ai
[DIR] .zcode
[DIR] android
[DIR] assets
[DIR] build
[DIR] coverage
[DIR] device-check
[DIR] dist
[DIR] docs
[DIR] dsh-context-source
[DIR] lib
[DIR] shaders
[DIR] test
[DIR] tool
[FILE] .flutter_tool_state
[FILE] .flutter-plugins-dependencies
[FILE] .gitignore
[FILE] .mcp-all-analyze.log
[FILE] .mcp-all-catches.log
[FILE] .mcp-all-data-probes.log
[FILE] .mcp-all-environment.log
[FILE] .mcp-all-new-tests.log
[FILE] .mcp-all-tests-summary.log
[FILE] .mcp-all-tests.log
[FILE] .mcp-all-vault-tests.log
[FILE] .mcp-app-links-source.log
[FILE] .mcp-device-fix-all-tests-final.log
[FILE] .mcp-device-fix-all-tests.log
[FILE] .mcp-device-fix-analyze-final.log
[FILE] .mcp-device-fix-analyze-verified.log
[FILE] .mcp-device-fix-analyze.log
[FILE] .mcp-device-fix-apk-sha256.txt
[FILE] .mcp-device-fix-before-install-2.log
[FILE] .mcp-device-fix-before-install-ready.log
[FILE] .mcp-device-fix-before-install.log
[FILE] .mcp-device-fix-build.log
[FILE] .mcp-device-fix-codegen.log
[FILE] .mcp-device-fix-device-state.log
[FILE] .mcp-device-fix-diff-check.log
[FILE] .mcp-device-fix-format-extra.log
[FILE] .mcp-device-fix-format-final.log
[FILE] .mcp-device-fix-format-migration.log
[FILE] .mcp-device-fix-format.log
[FILE] .mcp-device-fix-install.log
[FILE] .mcp-device-fix-manifest-format.log
[FILE] .mcp-device-fix-manifest-test.log
[FILE] .mcp-device-fix-prelaunch.log
[FILE] .mcp-device-fix-quality.json
[FILE] .mcp-device-fix-retry.log
[FILE] .mcp-device-fix-tests.log
[FILE] .mcp-device-install.log
[FILE] .mcp-device-installed.log
[FILE] .mcp-device-preflight.log
[FILE] .mcp-device-state.log
[FILE] .mcp-final-analyze.log
[FILE] .mcp-final-artifacts.log
[FILE] .mcp-final-build.log
[FILE] .mcp-final-catches.log
[FILE] .mcp-final-coverage.log
[FILE] .mcp-final-diff.log
[FILE] .mcp-final-doc-status.log
[FILE] .mcp-final-format.log
[FILE] .mcp-final-source-hashes.txt
[FILE] .mcp-final-summary.log
[FILE] .mcp-final-tests.log
[FILE] .mcp-finish-all-tests.log
[FILE] .mcp-finish-analyze.log
[FILE] .mcp-finish-build.log
[FILE] .mcp-finish-catches.log
[FILE] .mcp-finish-checkpoint.log
[FILE] .mcp-finish-coverage.log
[FILE] .mcp-finish-diff.log
[FILE] .mcp-finish-format.log
[FILE] .mcp-finish-regression.log
[FILE] .mcp-last-format.log
[FILE] .mcp-last-vault.log
[FILE] .mcp-optimization-catches.log
[FILE] .mcp-optimization-inventory.log
[FILE] .mcp-optimization-probe_test.dart
[FILE] .mcp-optimization-probes.log
[FILE] .mcp-optimization-scope.txt
[FILE] .mcp-performance-baseline.json
[FILE] .mcp-performance-error.log
[FILE] .mcp-regression-summary.log
[FILE] .mcp-repair-analyze-final.log
[FILE] .mcp-repair-analyze.log
[FILE] .mcp-repair-diffcheck.log
[FILE] .mcp-repair-env.log
[FILE] .mcp-repair-format-final.log
[FILE] .mcp-repair-format.log
[FILE] .mcp-repair-related.log
[FILE] .mcp-repair-tests-final.log
[FILE] .mcp-repair-tests-fixed.log
[FILE] .mcp-repair-tests-fixed2.log
[FILE] .mcp-repair-tests.log
[FILE] .mcp-resume-meta.log
[FILE] .mcp-resume-status.log
[FILE] .mcp-stylesheet.log
[FILE] .metadata
[FILE] analysis_options.yaml
[FILE] build-apk.bat
[FILE] CHANGELOG.md
[FILE] final_agent_cancelled.png
[FILE] final_agent_result.png
[FILE] fixed_agent_layout.png
[FILE] fixed_restart.png
[FILE] natgeo_landscape_clouds.jpg
[FILE] natgeo_landscape_golden_hour.jpg
[FILE] natgeo_landscape_mist_tyndall.jpg
[FILE] NUL
[FILE] preset-detail-windows-2a47ad.json
[FILE] preset-square-SKILL.md
[FILE] preset-windows-2a47ad.html
[FILE] pubspec.lock
[FILE] pubspec.yaml
[FILE] pwsh.cmd
[FILE] README.md
[FILE] settings.txt
[FILE] smoke_account.png
[FILE] smoke_account2.png
[FILE] smoke_agent_mode.png
[FILE] smoke_agent_project_done.png
[FILE] smoke_agent_project_sending.png
[FILE] smoke_agent_project_task.png
[FILE] smoke_agent_read_sending.png
[FILE] smoke_agent_session_b.png
[FILE] smoke_appearance.png
[FILE] smoke_chat_after_wait.png
[FILE] smoke_chat_committed.png
[FILE] smoke_chat_ready.png
[FILE] smoke_chat_regenerating.png
[FILE] smoke_chat_second_done.png
[FILE] smoke_chat_second_sending.png
[FILE] smoke_chat_sending.png
[FILE] smoke_chat_stopped.png
[FILE] smoke_dark.png
[FILE] smoke_drawer.png
[FILE] smoke_edit_dialog.png
[FILE] smoke_edit_resend.png
[FILE] smoke_launch.png
[FILE] smoke_light.png
[FILE] smoke_metrics_after_new_run.png
[FILE] smoke_metrics_first.png
[FILE] smoke_metrics_first2.png
[FILE] smoke_metrics_history_selected.png
[FILE] smoke_metrics_history.png
[FILE] smoke_mode_picker.png
[FILE] smoke_mode_picker2.png
[FILE] smoke_multiline_filled.png
[FILE] smoke_multiline_keyboard.png
[FILE] smoke_provider_after_restart.png
[FILE] smoke_provider_edit.png
[FILE] smoke_provider_saved.png
[FILE] smoke_resume.png
[FILE] smoke_session_b.png
[FILE] smoke_session_list_ab.png
[FILE] smoke_session_switch_a.png
[FILE] smoke_settings.png
[FILE] smoke_switch_b_after_restart.png
[FILE] smoke_switch_c_back.png
[FILE] smoke_user_actions.png
[FILE] smoke_user_actions2.png
[FILE] smoke_user_tap.png
[FILE] THIRD_PARTY_NOTICES.md
[FILE] tmp-mcp-build.txt
[FILE] tmp-mcp-db.txt
[FILE] tmp-mcp-last.txt
[FILE] tmp-mcp-last2.txt
[FILE] tmp-mcp-last3.txt
[FILE] tmp-mcp-sec.txt
[FILE] tmp-mcp-sec2.txt
[FILE] tmp-mcp-sec3.txt
[FILE] tmp-mcp-sec4.txt
[FILE] tmp-mcp-ssh-tests4.txt
[FILE] tmp-mcp-ssh.txt
[FILE] tmp-mcp-ssh2.txt
[FILE] windows-2a47ad.dshpreset
```

## dist/ APK 清单

所有下列 APK 均有配套 `.sha256` 文件。

| 路径 | MiB |
|---|---:|
| dist/nexus-agent-0.8.9_93-20260916-125521.apk | 21.33 |
| dist/nexus-agent-0.8.9_93-20260916-151310.apk | 21.34 |
| dist/nexus-agent-0.8.9_93-20260916-155536.apk | 21.34 |
| dist/nexus-agent-0.8.9_93-20260916-161102.apk | 21.34 |
| dist/nexus-agent-0.8.9_93-20260916-165404.apk | 21.33 |
| dist/nexus-agent-0.8.9_93-20260917-010716.apk | 21.33 |
| dist/nexus-agent-0.8.9_93-20260917-015034.apk | 21.33 |
| dist/nexus-agent-0.8.9_93-20260917-030254.apk | 21.33 |
| dist/nexus-agent-0.8.9_93-20260917-042832.apk | 21.35 |
| dist/nexus-agent-0.8.9_93-20260917-093448.apk | 21.35 |
| dist/nexus-agent-0.8.9_93-20260918-051238.apk | 21.37 |
| dist/nexus-agent-0.8.9_93-20260918-071233.apk | 21.37 |
| dist/nexus-agent-0.9.0_94-20260918-080431.apk | 21.37 |
| dist/nexus-agent-0.9.0_94-20260918-105316.apk | 21.39 |
| dist/nexus-agent-0.9.0_94-20260918-120842.apk | 21.41 |
| dist/nexus-agent-0.9.0_94-20260918-150327.apk | 21.42 |
| dist/nexus-agent-0.9.0_94-20260919-004024.apk | 21.42 |
| dist/nexus-agent-0.9.0_94-20260919-075752.apk | 21.43 |
| dist/nexus-agent-0.9.0_94-20260921-013156.apk | 21.45 |
| dist/nexus-agent-latest.apk | 21.45 |

## Git 工作区变更条目（清理前）

目录条目未递归展开；仅用于防止误删，不能替代代码备份。

```text
M .github/workflows/ci.yml
 M .github/workflows/release.yml
 M .gitignore
 M CHANGELOG.md
 M android/app/src/main/AndroidManifest.xml
 M android/app/src/main/kotlin/com/nexusagent/app/MainActivity.kt
 M android/app/src/main/res/xml/file_paths.xml
 M android/build.gradle.kts
 M android/gradle/wrapper/gradle-wrapper.properties
 M android/settings.gradle.kts
 M lib/application/agent_draft_service.dart
 M lib/application/agent_executor.dart
 M lib/application/agent_tool_catalog.dart
 M lib/application/app_lock_service.dart
 M lib/application/artifact_service.dart
 M lib/application/audit_service.dart
 M lib/application/background_execution_gateway.dart
 M lib/application/chat_controller.dart
 M lib/application/chat_run_execution.dart
 M lib/application/context_window.dart
 M lib/application/conversation_fork_service.dart
 M lib/application/dashboard_service.dart
 M lib/application/development_tool_installer.dart
 M lib/application/environment_service.dart
 M lib/application/execution_lease_service.dart
 M lib/application/headless_executor.dart
 M lib/application/nexus_guard.dart
 M lib/application/preview_service.dart
 M lib/application/project_context_service.dart
 M lib/application/project_kind_detector.dart
 M lib/application/project_service.dart
 M lib/application/project_settings.dart
 M lib/application/prompt_budget.dart
 M lib/application/run_controller.dart
 M lib/application/scheduled_task_runner.dart
 M lib/application/skill_intent_matcher.dart
 M lib/application/workspace_service.dart
 M lib/domain/models.dart
 M lib/domain/network_access_policy.dart
 M lib/infrastructure/background/foreground_service.dart
 M lib/infrastructure/database/app_database.dart
 M lib/infrastructure/database/app_database.g.dart
 M lib/infrastructure/files/vault_exporter_io.dart
 M lib/infrastructure/files/vault_exporter_web.dart
 M lib/infrastructure/mcp/mcp_server_config.dart
 M lib/infrastructure/mcp/mcp_tool_provider.dart
 M lib/infrastructure/notifications/notification_service.dart
 M lib/infrastructure/observability/sentry_service.dart
 M lib/infrastructure/plugins/plugin_store.dart
 M lib/infrastructure/providers/anthropic_provider.dart
 M lib/infrastructure/providers/gemini_provider.dart
 M lib/infrastructure/providers/openai_compatible_provider.dart
 M lib/infrastructure/providers/tool_trust_store.dart
 M lib/infrastructure/share/deep_link_service.dart
 M lib/infrastructure/share/sharing_image_reader.dart
 M lib/infrastructure/share/sharing_image_reader_io.dart
 M lib/infrastructure/share/sharing_image_reader_stub.dart
 M lib/infrastructure/share/sharing_service.dart
 M lib/infrastructure/skills/builtin_skills.dart
 M lib/infrastructure/skills/skill_installer.dart
 M lib/infrastructure/skills/skill_parser.dart
 M lib/infrastructure/skills/skill_store.dart
 M lib/infrastructure/terminal/adaptive_linux_runtime_adapter.dart
 M lib/infrastructure/terminal/android_shell_runtime_adapter.dart
 M lib/infrastructure/terminal/host_process_runtime_adapter.dart
 M lib/infrastructure/terminal/ssh_terminal_session.dart
 M lib/infrastructure/terminal/termux_runtime_adapter.dart
 M lib/infrastructure/tools/command_tool.dart
 M lib/infrastructure/tools/core_tools.dart
 M lib/infrastructure/tools/skill_tools.dart
 M lib/infrastructure/tools/workspace_tools.dart
 M lib/infrastructure/update/update_service.dart
 M lib/main.dart
 M lib/presentation/chat/chat_page.dart
 M lib/presentation/chat/widgets/attachment_drawer_panel.dart
 M lib/presentation/chat/widgets/capsule_top_bar.dart
 M lib/presentation/chat/widgets/chat_catalog_drawer.dart
 M lib/presentation/chat/widgets/chat_empty_state.dart
 M lib/presentation/chat/widgets/chat_execution_stage.dart
 M lib/presentation/chat/widgets/chat_message_list.dart
 M lib/presentation/chat/widgets/environment_sheet.dart
 M lib/presentation/chat/widgets/floating_capsule_input.dart
 M lib/presentation/chat/widgets/message_bubble.dart
 M lib/presentation/chat/widgets/nexus_back_to_latest_button.dart
 M lib/presentation/chat/widgets/plan_panel.dart
 M lib/presentation/chat/widgets/reasoning_block.dart
 D lib/presentation/chat/widgets/session_context_sheet.dart
 M lib/presentation/chat/widgets/session_metrics_bar.dart
 M lib/presentation/chat/widgets/session_metrics_sheet.dart
 M lib/presentation/chat/widgets/tool_activity_section.dart
 M lib/presentation/chat/widgets/tool_approval_sheet.dart
 M lib/presentation/dashboard/widgets/kpi_card_grid.dart
 M lib/presentation/dashboard/widgets/token_usage_hero.dart
 M lib/presentation/knowledge/knowledge_page.dart
 M lib/presentation/markdown/code_block.dart
 M lib/presentation/markdown/markdown_render_policy.dart
 M lib/presentation/markdown/math_block.dart
 M lib/presentation/motion/motion_preferences.dart
 M lib/presentation/motion/nexus_motion.dart
 M lib/presentation/motion/nexus_page_route_factory.dart
 M lib/presentation/plugins/plugins_page.dart
 M lib/presentation/plugins/skill_market_page.dart
 M lib/presentation/projects/project_picker_page.dart
 M lib/presentation/settings/appearance_theme_page.dart
 M lib/presentation/settings/data_backup_page.dart
 M lib/presentation/settings/data_management_page.dart
 M lib/presentation/settings/extensions_page.dart
 M lib/presentation/settings/language_page.dart
 M lib/presentation/settings/linux_environment_page.dart
 M lib/presentation/settings/tool_list_page.dart
 M lib/presentation/settings/workspace_files_page.dart
 M lib/presentation/terminal/terminal_page.dart
 M lib/presentation/theme/app_appearance_controller.dart
 M lib/presentation/theme/app_palette.dart
 M lib/presentation/theme/app_tokens.dart
 M lib/presentation/vault/vault_page.dart
 M lib/presentation/widgets/floating_toast.dart
 M lib/presentation/widgets/glass_surface.dart
 M lib/presentation/widgets/liquid_glass.dart
 M lib/presentation/widgets/liquid_segmented_control.dart
 M lib/presentation/widgets/nexus_disclosure.dart
 M lib/presentation/widgets/nexus_execution_status.dart
 M lib/presentation/widgets/nexus_loading_skeleton.dart
 M lib/presentation/widgets/nexus_sheet.dart
 M lib/presentation/widgets/tool_approval_helper.dart
 M lib/presentation/workspace/development_workbench_page.dart
 M pubspec.lock
 M pubspec.yaml
 M test/a11y_compliance_test.dart
 M test/agent_executor_test.dart
 M test/attachment_drawer_panel_test.dart
 M test/audit_service_test.dart
 M test/automatic_backup_test.dart
 M test/background_execution_gateway_test.dart
 M test/bugfix_regression_test.dart
 M test/chat_activity_dock_test.dart
 M test/chat_controller_test.dart
 M test/chat_empty_state_test.dart
 M test/chat_mode_test.dart
 M test/chat_rebuild_scope_test.dart
 M test/chat_visual_regression_test.dart
 M test/composer_skill_slot_test.dart
 M test/context_window_test.dart
 M test/dashboard_presentation_test.dart
 M test/db_migration_v17_test.dart
 M test/deep_link_and_shortcuts_test.dart
 M test/http_request_ssrf_test.dart
 M test/keyboard_insets_test.dart
 M test/markdown_render_policy_test.dart
 M test/mcp_network_policy_test.dart
 M test/nexus_components_test.dart
 M test/nexus_guard_test.dart
 M test/nexus_motion_and_widgets_test.dart
 M test/project_picker_test.dart
 M test/project_service_test.dart
 M test/reasoning_block_test.dart
 M test/run_controller_test.dart
 M test/runtime_adapters_test.dart
 M test/settings_page_test.dart
 M test/termux_setup_guide_test.dart
 M test/tool_activity_timeline_test.dart
 M test/ui_refactor_regression_test.dart
 M test/update_service_test.dart
 M tool/check_coverage.dart
?? .mcp-device-fix-apk-sha256.txt
?? .mcp-device-fix-quality.json
?? .mcp-final-source-hashes.txt
?? .mcp-optimization-probe_test.dart
?? .mcp-optimization-scope.txt
?? .mcp-performance-baseline.json
?? android/app/src/main/res/xml/backup_rules.xml
?? android/app/src/main/res/xml/data_extraction_rules.xml
?? assets/skills/api-integration/
?? assets/skills/code-review/
?? assets/skills/database-design/
?? assets/skills/debugging/
?? assets/skills/flutter-ui/
?? assets/skills/git-workflow/
?? assets/skills/technical-writing/
?? assets/skills/testing/
?? device-check/
?? lib/application/attachment_policy.dart
?? lib/application/chat_state.dart
?? lib/application/context_compression_applier.dart
?? lib/application/context_compression_planner.dart
?? lib/application/context_insights_history.dart
?? lib/application/context_snapshot_builder.dart
?? lib/application/conversation_history_pager.dart
?? lib/application/skill_catalog.dart
?? lib/domain/attachment_file.dart
?? lib/domain/context_insights.dart
?? lib/domain/history_load_result.dart
?? lib/domain/message_display_metadata.dart
?? lib/infrastructure/background/foreground_run_lease.dart
?? lib/infrastructure/database/database_tables.dart
?? lib/infrastructure/database/message_history_store.dart
?? lib/infrastructure/files/bounded_text_reader.dart
?? lib/infrastructure/files/vault_manifest.dart
?? lib/infrastructure/files/vault_skill_staging.dart
?? lib/infrastructure/files/vault_snapshot_reader.dart
?? lib/infrastructure/notifications/notification_intent.dart
?? lib/infrastructure/skills/skill_change_notifier.dart
?? lib/infrastructure/terminal/ssh_host_key_store.dart
?? lib/infrastructure/terminal/terminal_job_log_store.dart
?? lib/infrastructure/tools/pinned_host_connector.dart
?? lib/presentation/chat/chat_message_actions.dart
?? lib/presentation/chat/chat_scroll_coordinator.dart
?? lib/presentation/chat/skill_suggestion_rules.dart
?? lib/presentation/chat/slash_skill_query.dart
?? lib/presentation/chat/widgets/composer_skill_slot.dart
?? lib/presentation/chat/widgets/context_budget_bar.dart
?? lib/presentation/chat/widgets/context_budget_hint.dart
?? lib/presentation/chat/widgets/conversation_restore_skeleton.dart
?? lib/presentation/chat/widgets/provider_setup_hint.dart
?? lib/presentation/chat/widgets/session_configuration_sheet.dart
?? lib/presentation/chat/widgets/session_metrics_summary.dart
?? lib/presentation/chat/widgets/streaming_markdown.dart
?? lib/presentation/motion/motion_lifecycle.dart
?? lib/presentation/theme/app_presentation_preferences.dart
?? lib/presentation/widgets/nexus_pressable.dart
?? settings.txt
?? test/adaptive_runtime_regression_test.dart
?? test/android_deep_link_config_test.dart
?? test/app_lock_service_test.dart
?? test/attachment_policy_test.dart
?? test/chat_execution_stage_test.dart
?? test/chat_page_attachments_test.dart
?? test/chat_page_deep_link_regression_test.dart
?? test/chat_scroll_coordinator_test.dart
?? test/chat_state_matrix_test.dart
?? test/chat_visual_hierarchy_test.dart
?? test/context_budget_bar_test.dart
?? test/context_compression_applier_test.dart
?? test/context_compression_planner_test.dart
?? test/context_insights_history_test.dart
?? test/context_insights_test.dart
?? test/context_snapshot_builder_test.dart
?? test/conversation_restore_skeleton_test.dart
?? test/count_silent_catches_test.dart
?? test/declarative_tool_http_test.dart
?? test/foreground_run_lease_test.dart
?? test/message_display_metadata_test.dart
?? test/motion_ui_regression_test.dart
?? test/notification_intent_test.dart
?? test/optimization_regression_test.dart
?? test/provider_setup_hint_test.dart
?? test/provider_stream_integrity_test.dart
?? test/sentry_redaction_test.dart
?? test/session_metrics_hud_compress_test.dart
?? test/session_metrics_sheet_test.dart
?? test/session_metrics_summary_budget_test.dart
?? test/skill_suggestion_rules_test.dart
?? test/slash_skill_query_test.dart
?? test/ssh_host_key_store_test.dart
?? test/streaming_markdown_incremental_test.dart
?? test/terminal_job_log_store_test.dart
?? test/terminal_lifecycle_regression_test.dart
?? test/tool_approval_background_test.dart
?? test/tool_trust_store_test.dart
?? test/ui_followup_regression_test.dart
?? test/vault_safety_test.dart
?? test/workspace_safety_regression_test.dart
?? tmp-mcp-build.txt
?? tmp-mcp-db.txt
?? tmp-mcp-last.txt
?? tmp-mcp-last2.txt
?? tmp-mcp-last3.txt
?? tmp-mcp-sec.txt
?? tmp-mcp-sec2.txt
?? tmp-mcp-sec3.txt
?? tmp-mcp-sec4.txt
?? tmp-mcp-ssh-tests4.txt
?? tmp-mcp-ssh.txt
?? tmp-mcp-ssh2.txt
?? tool/benchmark_streaming_markdown.dart
?? tool/count_silent_catches.dart
?? tool/streaming_markdown_baseline_2026-09-22.json
```
