# 工作区整理执行记录

日期：2026-09-22。授权范围：分类整理根目录材料，并清理旧 APK；不清理 build/ 和 .dart_tool/。

## 执行结果

- 归档 142 个文件，其中日志 87 个、截图 49 个、基线/临时记录 6 个（包含本次新增的环境检查记录 1 个）。移动后逐个 SHA-256 校验，无内容变化。
- 删除 17 个旧 APK 和对应的 17 个 .sha256 文件，合计 380,832,117 字节，约 363.19 MiB。此为文件内容字节数，实际磁盘释放量可能不同。
- 保留 3 个 APK 和对应校验文件；清理前所有 20 个 APK 均已核对其配套 SHA-256，清理后保留包再次核验。
- 搬移与删除完成后，584 个受保护文件（Git 已跟踪文件及当前业务源码、测试、资源和工具文件）与操作前哈希一致。随后仅按预期更新 .gitignore 和本文所列工程报告。
- 没有修改业务源码，没有提交 Git；没有停止进程、运行构建、测试或安装 APK。
- 最终核验通过：142 个归档文件哈希一致，17 组旧 APK 已删除，3 组保留包完整；25 处文档归档路径存在，Git 状态没有非预期新增条目。核验记录：artifacts/cleanup/2026-09-22/verification.json。

## 当前归档结构

```text
artifacts/
  logs/2026-09-22/
  screenshots/2026-09-22/
  baselines/2026-09-22/
  cleanup/2026-09-22/
    cleanup.py       # 一次性核对与操作脚本，不要重复执行
    plan.json        # 操作前计划、保护哈希、Git 状态
    journal.json     # 已执行移动和删除记录
    moves.tsv        # 原路径 → 新路径
    result.json      # 执行结果及操作后 Git 状态
```

.gitignore 新增精确规则 `/artifacts/`，避免本地证据和设备截图误入库；这不是备份。重要证据如需长期保存，请备份 artifacts/。

## 保留 APK

| 用途 | 仓库路径 |
|---|---|
| 稳定入口 | dist/nexus-agent-latest.apk |
| 最近时间戳包 | dist/nexus-agent-0.9.0_94-20260921-013156.apk |
| 旧版本回滚候选 | dist/nexus-agent-0.8.9_93-20260918-071233.apk |

latest 与最近时间戳包 SHA-256 一致：`21dbd8ed604d74097b395738c831f32228693213dc45e852f2fec5b9b942e1e3`。
旧版本包 SHA-256：`fa73438ac0ff49131cc260e4ee5a615b9f4aa0ae0b9ee4d441ab0a0df1479955`。
回滚候选仅验证文件完整性，未验证运行稳定性、签名兼容性、降级安装或数据兼容性，不能承诺可直接覆盖安装。

## 已更新引用的报告

- docs/mcp-device-fixes-2026-09-22.md
- docs/mcp-mobile-agent-review.md
- docs/mcp-optimization-implementation-2026-09-22.md
- docs/mcp-optimization-review-2026-09-22.md
- docs/mcp-workspace-cleanup-2026-09-22.md（标注为清理前快照，保留历史清单）

引用排查覆盖 docs/、tool/、lib/、test/、android/、.github/ 中常见文本文件及根目录文档/构建脚本；不保证外部工具或其他目录没有引用。

## 有意保留不动

- build/、.dart_tool/、Android 缓存与签名材料。
- lib/、test/、assets/、tool/、shaders/ 及既有源码修改与新增文件。
- device-check/：包含脚本及验收证据，未改动。
- .skill-install/、dsh-context-source/、工具会话目录：没有扩大到外部工具清理。
- .mcp-optimization-probe_test.dart：被工程文档引用的探针，未擅自迁移。
- settings.txt、NUL、pwsh.cmd 与设计素材：用途不明或属于本地工具兼容材料，未删除。

## 恢复说明

移动的文件可依据 artifacts/cleanup/2026-09-22/moves.tsv 移回原路径；必须先检查原路径未被新文件占用，且同步恢复文档引用。不要直接重复运行 cleanup.py execute。
已删除的 17 组 APK 未保留额外备份，不能通过移动清单恢复，只能从已有外部备份取得或重新构建；没有声称它们可撤回。

## 文件移动清单

| 原路径 | 现路径 |
|---|---|
| `.mcp-all-analyze.log` | `artifacts/logs/2026-09-22/.mcp-all-analyze.log` |
| `.mcp-all-catches.log` | `artifacts/logs/2026-09-22/.mcp-all-catches.log` |
| `.mcp-all-data-probes.log` | `artifacts/logs/2026-09-22/.mcp-all-data-probes.log` |
| `.mcp-all-environment.log` | `artifacts/logs/2026-09-22/.mcp-all-environment.log` |
| `.mcp-all-new-tests.log` | `artifacts/logs/2026-09-22/.mcp-all-new-tests.log` |
| `.mcp-all-tests-summary.log` | `artifacts/logs/2026-09-22/.mcp-all-tests-summary.log` |
| `.mcp-all-tests.log` | `artifacts/logs/2026-09-22/.mcp-all-tests.log` |
| `.mcp-all-vault-tests.log` | `artifacts/logs/2026-09-22/.mcp-all-vault-tests.log` |
| `.mcp-app-links-source.log` | `artifacts/logs/2026-09-22/.mcp-app-links-source.log` |
| `.mcp-cleanup-preflight.json` | `artifacts/baselines/2026-09-22/.mcp-cleanup-preflight.json` |
| `.mcp-device-fix-all-tests-final.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-all-tests-final.log` |
| `.mcp-device-fix-all-tests.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-all-tests.log` |
| `.mcp-device-fix-analyze-final.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-analyze-final.log` |
| `.mcp-device-fix-analyze-verified.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-analyze-verified.log` |
| `.mcp-device-fix-analyze.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-analyze.log` |
| `.mcp-device-fix-apk-sha256.txt` | `artifacts/baselines/2026-09-22/.mcp-device-fix-apk-sha256.txt` |
| `.mcp-device-fix-before-install-2.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-before-install-2.log` |
| `.mcp-device-fix-before-install-ready.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-before-install-ready.log` |
| `.mcp-device-fix-before-install.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-before-install.log` |
| `.mcp-device-fix-build.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-build.log` |
| `.mcp-device-fix-codegen.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-codegen.log` |
| `.mcp-device-fix-device-state.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-device-state.log` |
| `.mcp-device-fix-diff-check.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-diff-check.log` |
| `.mcp-device-fix-format-extra.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-format-extra.log` |
| `.mcp-device-fix-format-final.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-format-final.log` |
| `.mcp-device-fix-format-migration.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-format-migration.log` |
| `.mcp-device-fix-format.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-format.log` |
| `.mcp-device-fix-install.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-install.log` |
| `.mcp-device-fix-manifest-format.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-manifest-format.log` |
| `.mcp-device-fix-manifest-test.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-manifest-test.log` |
| `.mcp-device-fix-prelaunch.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-prelaunch.log` |
| `.mcp-device-fix-quality.json` | `artifacts/baselines/2026-09-22/.mcp-device-fix-quality.json` |
| `.mcp-device-fix-retry.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-retry.log` |
| `.mcp-device-fix-tests.log` | `artifacts/logs/2026-09-22/.mcp-device-fix-tests.log` |
| `.mcp-device-install.log` | `artifacts/logs/2026-09-22/.mcp-device-install.log` |
| `.mcp-device-installed.log` | `artifacts/logs/2026-09-22/.mcp-device-installed.log` |
| `.mcp-device-preflight.log` | `artifacts/logs/2026-09-22/.mcp-device-preflight.log` |
| `.mcp-device-state.log` | `artifacts/logs/2026-09-22/.mcp-device-state.log` |
| `.mcp-final-analyze.log` | `artifacts/logs/2026-09-22/.mcp-final-analyze.log` |
| `.mcp-final-artifacts.log` | `artifacts/logs/2026-09-22/.mcp-final-artifacts.log` |
| `.mcp-final-build.log` | `artifacts/logs/2026-09-22/.mcp-final-build.log` |
| `.mcp-final-catches.log` | `artifacts/logs/2026-09-22/.mcp-final-catches.log` |
| `.mcp-final-coverage.log` | `artifacts/logs/2026-09-22/.mcp-final-coverage.log` |
| `.mcp-final-diff.log` | `artifacts/logs/2026-09-22/.mcp-final-diff.log` |
| `.mcp-final-doc-status.log` | `artifacts/logs/2026-09-22/.mcp-final-doc-status.log` |
| `.mcp-final-format.log` | `artifacts/logs/2026-09-22/.mcp-final-format.log` |
| `.mcp-final-source-hashes.txt` | `artifacts/baselines/2026-09-22/.mcp-final-source-hashes.txt` |
| `.mcp-final-summary.log` | `artifacts/logs/2026-09-22/.mcp-final-summary.log` |
| `.mcp-final-tests.log` | `artifacts/logs/2026-09-22/.mcp-final-tests.log` |
| `.mcp-finish-all-tests.log` | `artifacts/logs/2026-09-22/.mcp-finish-all-tests.log` |
| `.mcp-finish-analyze.log` | `artifacts/logs/2026-09-22/.mcp-finish-analyze.log` |
| `.mcp-finish-build.log` | `artifacts/logs/2026-09-22/.mcp-finish-build.log` |
| `.mcp-finish-catches.log` | `artifacts/logs/2026-09-22/.mcp-finish-catches.log` |
| `.mcp-finish-checkpoint.log` | `artifacts/logs/2026-09-22/.mcp-finish-checkpoint.log` |
| `.mcp-finish-coverage.log` | `artifacts/logs/2026-09-22/.mcp-finish-coverage.log` |
| `.mcp-finish-diff.log` | `artifacts/logs/2026-09-22/.mcp-finish-diff.log` |
| `.mcp-finish-format.log` | `artifacts/logs/2026-09-22/.mcp-finish-format.log` |
| `.mcp-finish-regression.log` | `artifacts/logs/2026-09-22/.mcp-finish-regression.log` |
| `.mcp-last-format.log` | `artifacts/logs/2026-09-22/.mcp-last-format.log` |
| `.mcp-last-vault.log` | `artifacts/logs/2026-09-22/.mcp-last-vault.log` |
| `.mcp-optimization-catches.log` | `artifacts/logs/2026-09-22/.mcp-optimization-catches.log` |
| `.mcp-optimization-inventory.log` | `artifacts/logs/2026-09-22/.mcp-optimization-inventory.log` |
| `.mcp-optimization-probes.log` | `artifacts/logs/2026-09-22/.mcp-optimization-probes.log` |
| `.mcp-optimization-scope.txt` | `artifacts/baselines/2026-09-22/.mcp-optimization-scope.txt` |
| `.mcp-performance-baseline.json` | `artifacts/baselines/2026-09-22/.mcp-performance-baseline.json` |
| `.mcp-performance-error.log` | `artifacts/logs/2026-09-22/.mcp-performance-error.log` |
| `.mcp-regression-summary.log` | `artifacts/logs/2026-09-22/.mcp-regression-summary.log` |
| `.mcp-repair-analyze-final.log` | `artifacts/logs/2026-09-22/.mcp-repair-analyze-final.log` |
| `.mcp-repair-analyze.log` | `artifacts/logs/2026-09-22/.mcp-repair-analyze.log` |
| `.mcp-repair-diffcheck.log` | `artifacts/logs/2026-09-22/.mcp-repair-diffcheck.log` |
| `.mcp-repair-env.log` | `artifacts/logs/2026-09-22/.mcp-repair-env.log` |
| `.mcp-repair-format-final.log` | `artifacts/logs/2026-09-22/.mcp-repair-format-final.log` |
| `.mcp-repair-format.log` | `artifacts/logs/2026-09-22/.mcp-repair-format.log` |
| `.mcp-repair-related.log` | `artifacts/logs/2026-09-22/.mcp-repair-related.log` |
| `.mcp-repair-tests-final.log` | `artifacts/logs/2026-09-22/.mcp-repair-tests-final.log` |
| `.mcp-repair-tests-fixed.log` | `artifacts/logs/2026-09-22/.mcp-repair-tests-fixed.log` |
| `.mcp-repair-tests-fixed2.log` | `artifacts/logs/2026-09-22/.mcp-repair-tests-fixed2.log` |
| `.mcp-repair-tests.log` | `artifacts/logs/2026-09-22/.mcp-repair-tests.log` |
| `.mcp-resume-meta.log` | `artifacts/logs/2026-09-22/.mcp-resume-meta.log` |
| `.mcp-resume-status.log` | `artifacts/logs/2026-09-22/.mcp-resume-status.log` |
| `.mcp-stylesheet.log` | `artifacts/logs/2026-09-22/.mcp-stylesheet.log` |
| `final_agent_cancelled.png` | `artifacts/screenshots/2026-09-22/final_agent_cancelled.png` |
| `final_agent_result.png` | `artifacts/screenshots/2026-09-22/final_agent_result.png` |
| `fixed_agent_layout.png` | `artifacts/screenshots/2026-09-22/fixed_agent_layout.png` |
| `fixed_restart.png` | `artifacts/screenshots/2026-09-22/fixed_restart.png` |
| `smoke_account.png` | `artifacts/screenshots/2026-09-22/smoke_account.png` |
| `smoke_account2.png` | `artifacts/screenshots/2026-09-22/smoke_account2.png` |
| `smoke_agent_mode.png` | `artifacts/screenshots/2026-09-22/smoke_agent_mode.png` |
| `smoke_agent_project_done.png` | `artifacts/screenshots/2026-09-22/smoke_agent_project_done.png` |
| `smoke_agent_project_sending.png` | `artifacts/screenshots/2026-09-22/smoke_agent_project_sending.png` |
| `smoke_agent_project_task.png` | `artifacts/screenshots/2026-09-22/smoke_agent_project_task.png` |
| `smoke_agent_read_sending.png` | `artifacts/screenshots/2026-09-22/smoke_agent_read_sending.png` |
| `smoke_agent_session_b.png` | `artifacts/screenshots/2026-09-22/smoke_agent_session_b.png` |
| `smoke_appearance.png` | `artifacts/screenshots/2026-09-22/smoke_appearance.png` |
| `smoke_chat_after_wait.png` | `artifacts/screenshots/2026-09-22/smoke_chat_after_wait.png` |
| `smoke_chat_committed.png` | `artifacts/screenshots/2026-09-22/smoke_chat_committed.png` |
| `smoke_chat_ready.png` | `artifacts/screenshots/2026-09-22/smoke_chat_ready.png` |
| `smoke_chat_regenerating.png` | `artifacts/screenshots/2026-09-22/smoke_chat_regenerating.png` |
| `smoke_chat_second_done.png` | `artifacts/screenshots/2026-09-22/smoke_chat_second_done.png` |
| `smoke_chat_second_sending.png` | `artifacts/screenshots/2026-09-22/smoke_chat_second_sending.png` |
| `smoke_chat_sending.png` | `artifacts/screenshots/2026-09-22/smoke_chat_sending.png` |
| `smoke_chat_stopped.png` | `artifacts/screenshots/2026-09-22/smoke_chat_stopped.png` |
| `smoke_dark.png` | `artifacts/screenshots/2026-09-22/smoke_dark.png` |
| `smoke_drawer.png` | `artifacts/screenshots/2026-09-22/smoke_drawer.png` |
| `smoke_edit_dialog.png` | `artifacts/screenshots/2026-09-22/smoke_edit_dialog.png` |
| `smoke_edit_resend.png` | `artifacts/screenshots/2026-09-22/smoke_edit_resend.png` |
| `smoke_launch.png` | `artifacts/screenshots/2026-09-22/smoke_launch.png` |
| `smoke_light.png` | `artifacts/screenshots/2026-09-22/smoke_light.png` |
| `smoke_metrics_after_new_run.png` | `artifacts/screenshots/2026-09-22/smoke_metrics_after_new_run.png` |
| `smoke_metrics_first.png` | `artifacts/screenshots/2026-09-22/smoke_metrics_first.png` |
| `smoke_metrics_first2.png` | `artifacts/screenshots/2026-09-22/smoke_metrics_first2.png` |
| `smoke_metrics_history.png` | `artifacts/screenshots/2026-09-22/smoke_metrics_history.png` |
| `smoke_metrics_history_selected.png` | `artifacts/screenshots/2026-09-22/smoke_metrics_history_selected.png` |
| `smoke_mode_picker.png` | `artifacts/screenshots/2026-09-22/smoke_mode_picker.png` |
| `smoke_mode_picker2.png` | `artifacts/screenshots/2026-09-22/smoke_mode_picker2.png` |
| `smoke_multiline_filled.png` | `artifacts/screenshots/2026-09-22/smoke_multiline_filled.png` |
| `smoke_multiline_keyboard.png` | `artifacts/screenshots/2026-09-22/smoke_multiline_keyboard.png` |
| `smoke_provider_after_restart.png` | `artifacts/screenshots/2026-09-22/smoke_provider_after_restart.png` |
| `smoke_provider_edit.png` | `artifacts/screenshots/2026-09-22/smoke_provider_edit.png` |
| `smoke_provider_saved.png` | `artifacts/screenshots/2026-09-22/smoke_provider_saved.png` |
| `smoke_resume.png` | `artifacts/screenshots/2026-09-22/smoke_resume.png` |
| `smoke_session_b.png` | `artifacts/screenshots/2026-09-22/smoke_session_b.png` |
| `smoke_session_list_ab.png` | `artifacts/screenshots/2026-09-22/smoke_session_list_ab.png` |
| `smoke_session_switch_a.png` | `artifacts/screenshots/2026-09-22/smoke_session_switch_a.png` |
| `smoke_settings.png` | `artifacts/screenshots/2026-09-22/smoke_settings.png` |
| `smoke_switch_b_after_restart.png` | `artifacts/screenshots/2026-09-22/smoke_switch_b_after_restart.png` |
| `smoke_switch_c_back.png` | `artifacts/screenshots/2026-09-22/smoke_switch_c_back.png` |
| `smoke_user_actions.png` | `artifacts/screenshots/2026-09-22/smoke_user_actions.png` |
| `smoke_user_actions2.png` | `artifacts/screenshots/2026-09-22/smoke_user_actions2.png` |
| `smoke_user_tap.png` | `artifacts/screenshots/2026-09-22/smoke_user_tap.png` |
| `tmp-mcp-build.txt` | `artifacts/logs/2026-09-22/tmp-mcp-build.txt` |
| `tmp-mcp-db.txt` | `artifacts/logs/2026-09-22/tmp-mcp-db.txt` |
| `tmp-mcp-last.txt` | `artifacts/logs/2026-09-22/tmp-mcp-last.txt` |
| `tmp-mcp-last2.txt` | `artifacts/logs/2026-09-22/tmp-mcp-last2.txt` |
| `tmp-mcp-last3.txt` | `artifacts/logs/2026-09-22/tmp-mcp-last3.txt` |
| `tmp-mcp-sec.txt` | `artifacts/logs/2026-09-22/tmp-mcp-sec.txt` |
| `tmp-mcp-sec2.txt` | `artifacts/logs/2026-09-22/tmp-mcp-sec2.txt` |
| `tmp-mcp-sec3.txt` | `artifacts/logs/2026-09-22/tmp-mcp-sec3.txt` |
| `tmp-mcp-sec4.txt` | `artifacts/logs/2026-09-22/tmp-mcp-sec4.txt` |
| `tmp-mcp-ssh-tests4.txt` | `artifacts/logs/2026-09-22/tmp-mcp-ssh-tests4.txt` |
| `tmp-mcp-ssh.txt` | `artifacts/logs/2026-09-22/tmp-mcp-ssh.txt` |
| `tmp-mcp-ssh2.txt` | `artifacts/logs/2026-09-22/tmp-mcp-ssh2.txt` |
