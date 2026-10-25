# 工具分类索引

默认从项目根目录运行；Android 预览优先使用根目录 `android-preview.bat`，并先检查已有预览进程和实际设备序列号。

覆盖率摘要：`python tool/coverage_audit.py`，输入为 `coverage/lcov.info`。CI 覆盖率门禁仍由 `tool/check_coverage.dart` 执行。

## 设备、功能验收与执行器

- [agent_live_acceptance.dart](agent_live_acceptance.dart)
- [browser_dom_budget_checks.html](browser_dom_budget_checks.html)
- [emulator_contract_support.py](emulator_contract_support.py)
- [emulator_driver_support.py](emulator_driver_support.py)
- [launch_emulator_debug.py](launch_emulator_debug.py)
- [mobile_ui_probe.py](mobile_ui_probe.py)
- [mobile_vm_probe.py](mobile_vm_probe.py)
- [run-agent-live-acceptance.ps1](run-agent-live-acceptance.ps1)
- [verify_approval_scope_ui_emulator.py](verify_approval_scope_ui_emulator.py)
- [verify_artifact_actions_emulator.py](verify_artifact_actions_emulator.py)
- [verify_artifact_actions_ui_emulator.py](verify_artifact_actions_ui_emulator.py)
- [verify_artifact_emulator.py](verify_artifact_emulator.py)
- [verify_artifact_ui_emulator.py](verify_artifact_ui_emulator.py)
- [verify_assistant_context_ui_emulator.py](verify_assistant_context_ui_emulator.py)
- [verify_assistant_entry_ui_emulator.py](verify_assistant_entry_ui_emulator.py)
- [verify_assistant_role_ui_emulator.py](verify_assistant_role_ui_emulator.py)
- [verify_browser_native.py](verify_browser_native.py)
- [verify_conversation_results_emulator.py](verify_conversation_results_emulator.py)
- [verify_conversation_results_regressions.py](verify_conversation_results_regressions.py)
- [verify_conversation_results_ui_emulator.py](verify_conversation_results_ui_emulator.py)
- [verify_global_search_emulator.py](verify_global_search_emulator.py)
- [verify_global_search_ui_emulator.py](verify_global_search_ui_emulator.py)
- [verify_job_board_emulator.py](verify_job_board_emulator.py)
- [verify_job_board_ui_emulator.py](verify_job_board_ui_emulator.py)
- [verify_knowledge_scope_emulator.py](verify_knowledge_scope_emulator.py)
- [verify_knowledge_scope_ui_emulator.py](verify_knowledge_scope_ui_emulator.py)
- [verify_major_large_text_emulator.py](verify_major_large_text_emulator.py)
- [verify_memory_knowledge_emulator.py](verify_memory_knowledge_emulator.py)
- [verify_memory_knowledge_ui_emulator.py](verify_memory_knowledge_ui_emulator.py)
- [verify_memory_scope_emulator.py](verify_memory_scope_emulator.py)
- [verify_memory_scope_ui_emulator.py](verify_memory_scope_ui_emulator.py)
- [verify_mobile_handoff.dart](verify_mobile_handoff.dart)
- [verify_mobile_review.py](verify_mobile_review.py)
- [verify_mobile_review_contracts.py](verify_mobile_review_contracts.py)
- [verify_page_coverage_ui_emulator.py](verify_page_coverage_ui_emulator.py)
- [verify_personal_context_sql_emulator.py](verify_personal_context_sql_emulator.py)
- [verify_personal_context_sql_ui_emulator.py](verify_personal_context_sql_ui_emulator.py)
- [verify_plan_protocol_emulator.py](verify_plan_protocol_emulator.py)
- [verify_reminder_notifications_emulator.py](verify_reminder_notifications_emulator.py)
- [verify_result_action_approval_emulator.py](verify_result_action_approval_emulator.py)
- [verify_result_action_approval_regressions.py](verify_result_action_approval_regressions.py)
- [verify_result_action_approval_ui_emulator.py](verify_result_action_approval_ui_emulator.py)
- [verify_result_approval_plan_ui_regression.py](verify_result_approval_plan_ui_regression.py)
- [verify_sheets_dialogs_ui_emulator.py](verify_sheets_dialogs_ui_emulator.py)
- [verify_speech_capture_ui_emulator.py](verify_speech_capture_ui_emulator.py)
- [verify_static_web_delivery.py](verify_static_web_delivery.py)
- [verify_steering_guard_emulator.py](verify_steering_guard_emulator.py)
- [verify_system_connector_emulator.py](verify_system_connector_emulator.py)
- [verify_task_runtime_emulator.py](verify_task_runtime_emulator.py)
- [windows_remote_executor.py](windows_remote_executor.py)

## 构建与 Android 预览

- [android_preview.dart](android_preview.dart)
- [build-apk-tools.ps1](build-apk-tools.ps1)
- [build-windows-installer.ps1](build-windows-installer.ps1)
- [build-windows.ps1](build-windows.ps1)
- [run-android-preview.ps1](run-android-preview.ps1)

## 性能与基线

- [benchmark_streaming_markdown.dart](benchmark_streaming_markdown.dart)
- [frame_timing_window.dart](frame_timing_window.dart)
- [streaming_markdown_baseline_2026-09-22.json](streaming_markdown_baseline_2026-09-22.json)

## 质量门禁与工具测试

- [check_coverage.dart](check_coverage.dart)
- [count_silent_catches.dart](count_silent_catches.dart)
- [coverage_audit.py](coverage_audit.py)
- [release_evidence_gate.py](release_evidence_gate.py)
- [score_mobile_agent_eval.py](score_mobile_agent_eval.py)
- [test_build_apk.py](test_build_apk.py)
- [test_emulator_contract_support.py](test_emulator_contract_support.py)
- [test_release_evidence_gate.py](test_release_evidence_gate.py)
- [test_score_mobile_agent_eval.py](test_score_mobile_agent_eval.py)
- [test_source_tokens.py](test_source_tokens.py)
- [test_windows_remote_executor.py](test_windows_remote_executor.py)
- [verify_source_tokens.dart](verify_source_tokens.dart)

## Windows 验收与诊断

- [desktop_acceptance.dart](desktop_acceptance.dart)
- [desktop_blue_smoke.dart](desktop_blue_smoke.dart)
- [desktop_cpu_profile.dart](desktop_cpu_profile.dart)
- [desktop_frame_pump.dart](desktop_frame_pump.dart)
- [diagnostics/windows_slider_ax_repro.dart](diagnostics/windows_slider_ax_repro.dart)
- [run-desktop-acceptance.ps1](run-desktop-acceptance.ps1)
- [run-desktop-production-smoke.ps1](run-desktop-production-smoke.ps1)
- [verify-blue-workspace.ps1](verify-blue-workspace.ps1)

## 历史兼容工具

- [legacy/fix-pwsh.bat](legacy/fix-pwsh.bat)

`legacy/fix-pwsh.bat` 是保留的历史环境修复脚本，会向硬编码的系统 Flutter 路径复制可执行文件；不属于日常构建入口，本次未执行。
