# 项目完善：第一批交付

日期：2026-10-14。本轮优先处理文件恢复、跨平台更新、桌面历史入口和自动化验证。

## 已实现

- **文件回退**：快照名称改用完整规范化路径的 SHA-256，避免 `a/b.txt` 与 `a_b.txt` 共用备份。写回前验证备份内容与 `beforeHash` 一致；新快照可独立恢复，旧的串档或损坏快照会返回冲突并保留工作区现状。已被覆盖的旧备份不会因此自动找回。
- **Windows 更新**：检查更新只选择 `nexus-agent-*-windows-x64.zip`；Android 继续选择 `app-release.apk`。校验文件必须匹配所选包的完整名称，缺失当前平台包时明确报错。APK 安装入口拒绝 Windows。
- **Windows 下载**：使用独立暂存目录，校验 SHA-256 与 ZIP 文件头后保存完整包，失败时清理暂存下载。界面提供下载进度、失败重试、打开下载位置和手动升级说明。关闭程序后将 ZIP 完整解压到新目录运行，保留 DLL 与 `data/`；不会替换正在运行的程序。窄窗口、两倍字号和长更新说明支持滚动。
- **桌面历史**：会话与任务首次展示 30 条，有更多记录时提供“加载更早”。任务排序加入 ID，确保相同更新时间下顺序稳定；切换项目或会话重置历史窗口。项目菜单明确标识“最近项目”，完整项目列表仍通过“打开或管理项目…”访问。
- **CI 与发布配置**：补充 `refactor/**`、`codex/**` 推送触发；Windows 构建前运行回退、更新和工作区关键回归。Tag 发布工作流在 Android 发布成功后构建并上传 Windows ZIP 与匹配的 `.sha256`。覆盖率工具的默认门槛与 CI 统一为 55%。
- **文档**：README 补充 Windows 手动升级、历史加载入口与 CI 发布行为。

## 验证

- 最终 `flutter analyze --no-pub`：无问题。
- 最终 `flutter test --coverage --no-pub --reporter expanded`：**1,879 项全部通过**。
- 作者代码覆盖率 **65.66%**（30,154 / 45,921），通过 55% 门槛；包含生成代码为 60.31%。
- 新增回归覆盖路径碰撞、损坏与旧版备份、平台选包、匹配校验文件、ZIP 下载与清理、Windows 更新界面、会话/任务超过 30 条后的可达性。
- 未记录意图的空 catch 为 0；`git diff --check` 通过；两份工作流 YAML 语法解析通过。
- 最终源码 Windows Release 构建成功（94.9 秒），产物为 `build/windows/x64/runner/Release/mobile_agent.exe`。构建日志含已有 WebView 插件的 CMake 开发警告，未影响编译通过；未进行该产物的原生启动或真实账号验收。

本地日志：

- `artifacts/project-review/analyze-final.log`
- `artifacts/project-review/regression-final.log`
- `artifacts/project-review/windows-build-final.log`
- `coverage/lcov.info`

## 尚需外部条件或后续处理

- ADB 设备列表为空，Android 真机投屏、设备断连、后台运行与杀进程恢复仍待连接已授权设备验收。
- 用户已确认“元衡”配置在手机端。本机 Windows 应用首选项中尚无服务商档案、接口地址或模型配置；再次检查 ADB 仍无设备。待手机通过 USB 连接、开启 USB 调试并授权后，使用手机应用的现有配置继续真实模型与设备验收；没有读取或输出 API Key，也没有发起真实模型请求。
- 工作流仅完成本地修改与校验，尚未推送或在 GitHub 执行，正式 Release 尚未发布。
- 工作区原有大量未提交改动，本轮保留其状态，没有混合提交或推送。
- ChatController 与 Android 设备工具的大范围职责拆分、长会话性能专项验证仍是后续工作。语言页当前明确标识英文未完整翻译且暂无完善计划，本轮保持这一已有产品决定。
