# ENGINEERING — 工程约束与门禁登记

> 本文件登记所有"机制性约束"（由谁保障、怎么验证），避免每位维护者重新发明或误踩。
> 完整评审背景见历史文档（27 条三维评审，2026-09-10）；本文只收长期有效的结论。

## 1. 质量门（CI 强制）

| 门禁 | 触发 | 命令 / 实现 | 位置 |
| --- | --- | --- | --- |
| 静态分析 | push feature/**、PR | `flutter analyze --no-pub` 必须零告警 | `.github/workflows/ci.yml` |
| 测试 | 同上 | `flutter test`（CI 上直跑；本机见 §2） | 同上 |
| 内联中文不上升 | 同上 | `bash tool/check_inline_zh.sh`（仅中文决策，见 §3） | 同上 |
| lint 规则 | analyze 内含 | `prefer_const_constructors` / `prefer_const_literals_to_create_immutables` / `unawaited_futures` / `avoid_print` / `use_key_in_widget_constructors` | `analysis_options.yaml` |
| 发布归档符号 | tag v* | release 产物附带 `build/symbols/**`（混淆堆栈可反解） | `.github/workflows/release.yml` |

## 2. 本机测试环境（Windows）

- **必须用 `bash tool/test.sh`，禁止直接 `flutter test`**：本机缺 `PROGRAMFILES(X86)` 会使 flutter_tester 起不来；`http_proxy=127.0.0.1:*` 会把 localhost WebSocket 发进代理（`Invalid WebSocket upgrade request`）。脚本已固化修正。`flutter analyze` 不受影响。
- 偶发失败先判断是否环境问题：终端类测试并发下偶发 `PathAccessException`/`TimeoutException`，`--concurrency=1` 复跑；这两个测试已自带删除重试与 2 分钟超时（`test/reasoning_and_terminal_test.dart`）。
- 单测里真连本机 socket：`TestWidgetsFlutterBinding.ensureInitialized()` 后 `HttpOverrides.global = null`，假上游必须 `charset: 'utf-8'`，且异常要收集断言为空。
- 想强制走 DemoProvider：baseUrl 必须非本地（如 `https://unused.invalid/v1`），`ProviderConfig.isConfigured` 对本地地址视为已配置。

## 3. 产品决策登记

| 决策 | 内容 | 落点 |
| --- | --- | --- |
| 仅中文，不做 i18n | 不做 ARB/gen-l10n；内联中文行数不得上升 | `tool/check_inline_zh.sh` + `tool/inline_zh_baseline.txt` + CI 门禁 |
| 字体 | 不声明 `fontFamily: 'Inter'`（未随包分发，声明只会导致字重合成不稳定）；Latin 交给系统字体。将来打包 Inter 须同时改 `app_theme.dart` 头注释处清单 + pubspec | `lib/presentation/theme/app_theme.dart` |
| 多设备云同步 | 已移除，仅保留本地加解密（保险箱/备份）。`sync.salt`/`sync.secret` 旧 Secure Storage 键名**不可改名**（老数据解密依赖） | `lib/infrastructure/files/local_crypto_service.dart` |
| `MANAGE_EXTERNAL_STORAGE` | **保留**：终端/Termux 桥（`/sdcard/pocketforge-bridge`）依赖，删除即功能失效 | `AndroidManifest.xml` |

## 4. 代码红线（改前必读）

### 4.1 两个「敏感」概念绝不可混用
- `UnifiedTool.sensitive`（`domain/models.dart`）→ **强制人工审批**（`ApprovalPolicy` 对它无条件弹窗）。
- `SensitiveToolPolicy`（`domain/sensitive_tool_policy.dart`）→ **持久化脱敏**（SQLite/导出/日志出口），不影响审批。
- **绝不要**为脱敏给 `read_file`/`terminal`/`write_file` 加 `sensitive: true`（会让每次读文件都弹审批）。`read_file` 的结果**保持不脱敏**（用户需回看）。守护测试：`test/sensitive_tool_policy_test.dart`。

### 4.2 键盘 inset
- **body 内读键盘高度一律用 `lib/presentation/utils/keyboard_insets.dart`**（`keyboardInset`/`isKeyboardVisible`），不要写 `MediaQuery.viewInsetsOf` —— builder 闭包参数的 context 在 Scaffold body 内取值恒为 0（`paddingOf` 行为不同，未被消费）。守护测试：`test/keyboard_insets_test.dart`。

### 4.3 色值
- 硬编码色值仅允许以下有意保留区（其余一律走 `AppPalette` Token）：`app_palette.dart`（Token 本体）、`code_block.dart`（语法高亮色板，**不要**换成业务 Token）、`tool_approval_sheet.dart`（终端 Catppuccin）、`terminal_sheet.dart` / `web_preview_dialog.dart` / `environment_sheet.dart`（深色终端表面）、`settings_components.dart`（iOS 色值识别常量）。基线 33 处，新增即评审。

### 4.4 数据库
- `schemaVersion` 当前 **16**；schema 变更必须升版本 + 写 `onUpgrade` 迁移 + 迁移测试。
- **绝不手改** `lib/infrastructure/database/app_database.g.dart`（build_runner 生成）。
- PRAGMA（WAL/foreign_keys/cache_size/synchronous）在 `database_executor_io.dart` 的 `setup:` 逐连接注入，别挪走。
- `foreign_keys=ON` 当前是空操作（全库无 FK 声明，23 张表裸 `text()` 存 id），级联清理靠手写（`pruneRunRecords`）。

### 4.5 输入区装配
- 输入区上方是一个 `Column`，顺序即优先级（附件行 → 指标条 → RunStatusCard → 压缩提示 → 技能槽 → 输入框）。三种技能提示**共用一个槽位**（`lib/presentation/chat/composer_skill_slot.dart`，优先级 `/` 补全 > 自动建议 > 已加载，running 时不出）。不要退回三条各自渲染，也不要再提"托盘折叠"（N≤2 不省空间，已评估否决）。

## 5. Git 提交纪律（本仓库有 ref 被外部进程删除的前科）

```sh
guard() { git rev-parse --verify -q HEAD >/dev/null || { echo "!! HEAD 无效，拒绝提交"; exit 9; }; }
guard && git commit -m "..."
# 提交后立即（从 reflog 取 SHA，不依赖 loose ref）：
NEW=$(awk 'END{print $2}' .git/logs/HEAD)
printf '%s %s\n' "$NEW" "refs/heads/feature/mature-agent" > .git/packed-refs
rm -f .git/refs/heads/feature/mature-agent
git pack-refs --all
git rev-parse HEAD   # 复验
```

- **绝不** `git rev-parse HEAD` 的结果去填 ref 文件 —— ref 被删时它返回字面量 `HEAD`。
- 丢 ref 不等于丢数据：从 `.git/logs/HEAD` 末行取真实 SHA 即可恢复。
- 网络注意：本机到 GitHub 443 直连常被封、本地代理可能无 TLS 转发；推送失败时重试或用 `git bundle` 做本地全量备份兜底。

## 6. 已否决方向（12 条，不要重做）

以下判断均经实测证伪（多数来自"读代码的直觉"而非运行验证）：

1. 给 `ChatState` 补 `==`/`hashCode` 治流式重建 → 无效，正解是 `select` 收窄订阅（已落地）。
2. "流式期间 Markdown 每帧重解析" → 已由现网 `lightweight` 分支 + flutter_markdown 缓存解决。
3. 统一 Dio 重试与 Agent 重试 → 两者不叠加是刻意设计（流式请求跳过 Dio 重试）。
4. 给 `run_events` 加保留策略 → `pruneRunRecords` 已每轮级联清理。
5. "项目没做混淆" → 已做（`--obfuscate` + R8），缺口只是符号归档（已修）。
6. 一刀切清理硬编码色值 → 仅少数真违规，语法/终端/iOS 色板是有意保留。
7. "command_tool 用黑名单防护弱" → 恰相反，18 条白名单 + 内联求值拦截，比文件沙箱更严。
8. `MediaQuery.viewInsetsOf` 让回底按钮避开键盘 → body 内恒 0，no-op（同 §4.2）。
9. `isScrollingNotifier` 判断用户拖拽 → 程序化滚动时也为 true，会让跟手永久停止。
10. 开 `foreign_keys=ON` 修级联 → 无 FK 声明，空操作。
11. 删除 `MANAGE_EXTERNAL_STORAGE` → 会废掉终端与自定义工作区。
12. 用 `Scaffold` body 内的 context 读 `viewInsets` → 恒 0；判据是"context 从哪来"（§4.2）。

**共性教训**：涉及第三方组件内部语义（Scaffold inset 消费、flutter_markdown 缓存、isScrollingNotifier 状态）必须探针实测，不要靠读源码推断。报 P0 前必须走完"从入口到热点"的完整调用链。

## 7. 架构现状备忘（2026-09-12）

- `ChatController` 拆分：第 1 步 `RunCoordinator` + `chat_run_execution.dart` 已完成（2825 → 2063 行），断点恢复/预算续跑已有护栏测试（`test/chat_resume_test.dart`）。**第 2/4 步（ConversationStore/ToolRegistryFactory）明确不再做**：剩余可摘块仅 250–350 行的小方法集合，protected `state` 限制下性价比为负；第 3 步 `PlanStateMachine` 视情况独立实施。
- `Notifier.state` 是 protected 成员：搬方法出 `Notifier` 子类会撞 40+ 条 `invalid_use_of_protected_member`。可行路子是 part 文件 + 库内转发访问器（参考 `_currentState`）。
- 跨层反向依赖（`infrastructure → application`）应清零；新增依赖前先看 `lib/domain/ports/` 有没有缝可用。
