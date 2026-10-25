# Android 移动端验收清单与处置流程

本文用于把移动端最终验收交给另一个 agent 执行。验收目标是确认 Android 手机布局、常用交互和复杂状态可用，并留下可复核证据；不能把源码覆盖清单、Widget 测试或编译成功描述成逐页实机通过。

## 执行约束

- 工作区 `D:\AIIIIII\ai-agent\mobile_agent` 存在大量未提交改动。开始前运行 `git status --short`，只改本任务明确涉及的文件；不得 reset、checkout、清理其他 agent 的文件或覆盖无关改动。
- 阅读根目录 `AGENTS.md`。已有模拟器为 `Nexus_Preview_API_36`，调试包名 `com.nexusagent.app.debug`。先检查 `local/android-sdk/platform-tools/adb.exe devices`、AVD 名称以及现存 `tool/android_preview.dart` 进程。已有预览就复用，避免重复 Flutter 调试会话。
- 模拟器交互使用 `python tool/mobile_ui_probe.py --serial emulator-5554 ...`；必须以 `adb devices` 的实际序列号替换示例值。探针只允许此 AVD 和调试 App，配置前会备份状态。结束时执行 `restore` 并确认字体、旋转、夜间模式、density 已恢复。
- 保持预览进程运行，确认启动输出 `[preview] Ready`；热重载后确认 `[preview] Hot reload complete.`。编译失败需查看预览终端错误，模拟器上有窗口不等于预览正常。
- 所有新截图、记录、临时文件写入 `local/temp/mobile-acceptance-2026-10-17/`。`local/` 已忽略，不要提交 SDK、AVD、缓存或下载。
- 模拟器是 x86_64，不能验证项目仅支持 ARM64 的 Alpine/PRoot 运行时，也不等于实体手机、真实权限硬件和真实网络验收。

## 验收前基线

- [ ] 保存 `git status --short` 输出，记录验收开始时工作区的已有脏文件。
- [ ] 确认 Flutter 预览使用当前工作区，并记录 AVD、Android 版本、屏幕逻辑尺寸、density、当前应用版本/提交状态。
- [ ] 在测试前先运行以下核心回归，不要并发启动多个 Flutter test 命令，避免 Windows Flutter 编译缓存互相覆盖：

```powershell
flutter test test/a11y_compliance_test.dart test/input_tool_grid_sheet_test.dart
flutter test test/chat_mode_test.dart test/chat_visual_hierarchy_test.dart test/chat_visual_regression_test.dart
flutter test test/workspace_editor_mobile_test.dart test/development_loop_test.dart test/development_workbench_mobile_test.dart
flutter test test/nexus_theme_test.dart test/desktop_shell_test.dart test/nexus_all_pages_layout_test.dart
flutter test test/ui_edge_states_test.dart test/tool_approval_background_test.dart test/message_longpress_test.dart
flutter test test/reasoning_and_terminal_test.dart test/terminal_page_test.dart test/project_picker_test.dart test/project_change_set_page_test.dart
flutter analyze
```

测试超时或编译冲突时，先确认旧进程已退出，再单独运行失败文件；记录实际失败栈，不能把超时写成通过。

## 检查清单

### 1. 全局手机框架与基础可读性

- [ ] 在 360dp 左右窄屏检查聊天首页、抽屉导航、二级页面头部、底部导航/主要操作区；截图保存默认亮色和暗色各一张。
- [ ] 检查每个可见按钮都能触发正确动作、禁用态不响应、返回行为正确；主要触控区不小于 48dp；标题、按钮文案、状态和列表尾部无溢出或被系统栏遮挡。
- [ ] 系统字体比例 1.3 和 1.6 时检查抽屉、列表、对话框、底部 Sheet 和表单，确认能换行/滚动且关键操作仍可到达。
- [ ] 暗色模式下抽查聊天、抽屉、项目主页、设置、终端与弹窗，检查文字对比度、禁用态、分割线与焦点状态。
- [ ] 旋转到横屏，检查仍呈现合适的移动布局，无错误切换成桌面导航；再回到竖屏确认状态恢复。

### 2. 聊天与输入主流程

- [ ] 新会话、已有会话、空消息、长消息、流式响应/停止/继续、消息操作菜单和会话切换。
- [ ] 输入区：附件入口、发送按钮空/非空状态、键盘弹出时输入框与发送区可见；Enter/换行行为符合平台约定。
- [ ] 模式切换器可辨识当前 Chat/Agent/Plan 模式，切换后状态正确；输入卡内不出现重复模式入口；审批入口有可访问语义名并能打开策略选择。
- [ ] 模型/服务商选择和未配置/加载/错误状态可读，长名称不挤压操作按钮。
- [ ] 用系统返回键、页面返回按钮关闭键盘/Sheet/子页时，顺序和预期一致；未发送输入或未保存内容不意外丢失。

### 3. 项目、文件与工作台

- [ ] 项目列表的创建、导入、选择、空态、错误态；模板卡片和名称校验在窄屏可完整操作。
- [ ] 项目主页检查概览、文件、终端、任务、产物等标签/入口；路径可复制，长路径不撑破布局。
- [ ] 文件树空目录、深层目录、权限/加载错误、返回导航；编辑文件顶部对齐、多行编辑、跳转行号、未保存离开确认、保存成功/失败反馈。
- [ ] 开发工作台完整执行一条可重复的静态网页/本地验证流程；核对步骤状态、运行日志滚动/复制、完成/失败结果、产物路径与重新执行操作。
- [ ] 长任务进行时切换页面、回到前台、等待完成；检查加载/暂停/失败/完成状态不会互相误报。除非有专用可靠测试项目，不得触发破坏性写入或真实外部部署。

### 4. 终端与键盘

- [ ] 项目命令/作业入口、远程交互终端入口能区分；输入命令、提交、清空/关闭、日志滚动和复制路径正常。
- [ ] 软键盘弹出后终端输入框、快捷操作和运行按钮均可见且可点；键盘收起后页面没有多余空白或遮挡。
- [ ] 用只读/无副作用命令验证成功反馈；危险命令、工作区外路径和需要审批的操作确认策略符合现有产品规则，不执行会删除或覆盖用户数据的命令。

### 5. 设置、权限和系统交互

- [ ] 设置主目录及模型、服务商、工具、外观、语言、数据管理等常用子页可滚动、返回正确，当前值和修改反馈明确。
- [ ] Android 权限页面逐项检查真实权限申请、拒绝、永久拒绝后的解释/回到设置流程；只有模拟器实际提供的硬件权限才标为验证，其余标记“未覆盖”。
- [ ] 系统返回、软键盘、夜间模式、屏幕旋转和进后台/恢复前台组合检查，避免弹窗重复、状态丢失或应用崩溃。
- [ ] 本轮如未配置真实服务凭据，只验未配置、错误/超时的受控状态和重试体验；不能声称真实 API 成功。不得输出密钥或令牌到截图、日志或报告。

### 6. 长列表、复杂状态和数据恢复

- [ ] 对任务、会话、项目文件、历史/日志等长列表检查首屏加载、连续滚动到底、刷新、筛选无结果、加载失败后保留旧数据并可重试。
- [ ] 空、加载、部分失败、全失败、断网/超时、无权限、长标题/长路径、大字号均至少覆盖代表性页面；截图与对应步骤/状态关联。
- [ ] 备份恢复只使用专用测试数据：先做可恢复副本，验证备份成功、文件可识别、恢复确认、恢复完成后的内容与设置；不要在含用户真实数据的环境执行覆盖恢复。
- [ ] 需要大数据库、长时间后台任务、ARM64 运行时、真实设备列表等环境才可验证的项目单独列出阻塞和所需环境，不能用模拟数据代替并标为通过。

## 手动模拟器操作与留证

探针命令示例（先检查实际序列号和现有预览）：

```powershell
python tool/mobile_ui_probe.py --serial emulator-5554 snapshot --name chat-home-light
python tool/mobile_ui_probe.py --serial emulator-5554 tap "抽屉" --contains
python tool/mobile_ui_probe.py --serial emulator-5554 snapshot --name navigation-drawer
python tool/mobile_ui_probe.py --serial emulator-5554 configure --font 1.3
python tool/mobile_ui_probe.py --serial emulator-5554 snapshot --name drawer-large-text
python tool/mobile_ui_probe.py --serial emulator-5554 restore
```

若控件不在 Android 无障碍树中，使用模拟器窗口人工操作并记录步骤、实际观察结果和截图路径；不要向探针传入未经截图确认的重复标签 tap。每项证据至少包含：场景、设备配置、操作步骤、预期、实际、结果（通过/失败/未覆盖）、截图或日志路径。

## 通过标准

- 所有核心自动化测试和静态分析完成且通过；失败测试必须有修复及重跑结果，不能仅记录“已知问题”。
- 本清单第 1 至 5 节的核心路径都已在 Android 模拟器逐项操作；高优先级项目不允许留“未覆盖”。第 6 节按可用数据/环境执行，缺少条件须标记阻塞并说明条件。
- 无崩溃、红屏、溢出、无法返回、关键操作被遮挡/不可触达、数据丢失或错误成功提示。截图与运行日志足以让另一个人复核。
- 修改后重新运行受影响的测试和全套核心回归；最终 `flutter analyze`、`dart format --output=none --set-exit-if-changed <本任务修改文件>`、`git diff --check` 均通过。
- 最终报告按“通过 / 失败已修复并复验 / 阻塞未覆盖”分类，不得用总百分比掩盖关键缺陷；注明工作区既有改动未被覆盖或清理。

## 问题处置闭环

1. **记录**：发现问题立即记录页面、设备配置、前置数据、复现步骤、期望与实际、截图/日志、严重度；避免只写“UI 不好看”。
2. **分级**：P0 为崩溃、数据损坏/丢失、越权执行或安全边界失效；P1 为主要流程不可完成、主要操作遮挡/不可触达或错误状态导致误操作；P2 为局部溢出、错误文案、状态不清或辅助操作异常；P3 为不影响操作的视觉一致性问题。P0/P1 必须修复后才能通过验收。
3. **定位并修改**：先确认问题发生在 Android 实际构建分支；阅读相关页面/组件和已有改动，只做最小范围修复，不覆盖其他 agent 文件。业务行为问题补逻辑测试；布局、语义或触控问题补对应 Widget 测试。
4. **复验**：保存后确认预览热重载成功；按完全相同步骤复现一次，再走相邻流程和暗色/大字号/键盘等相关场景；跑受影响测试以及核心回归。修复失败则保留失败证据并继续迭代，不得把未验证修复标记为完成。
5. **环境阻塞**：真实服务、权限硬件、ARM64、备份大数据或后台时长不足时，不造数据伪证。报告所缺设备/账号/数据、替代覆盖、剩余风险及解除阻塞后可执行的步骤。
6. **收尾**：恢复模拟器原设置；停止本轮新增且不再需要的进程，但保留项目约定需常驻的预览进程；再次检查 `git status --short`，确保只保留本任务改动，不清理基线中原有文件。

## 最终交付报告格式

```text
验收范围与设备：
通过：场景 / 测试命令 / 证据路径
失败并修复复验：问题、根因、改动文件、复验结果、证据路径
阻塞或未覆盖：缺少条件、影响、临时替代覆盖、解除步骤
自动化：测试命令与通过/失败结果；静态分析、格式、diff 检查
模拟器状态：原设置已恢复；预览进程状态；工作区改动摘要
结论：通过 / 有条件通过 / 不通过（列明未关闭的 P0/P1）
```
