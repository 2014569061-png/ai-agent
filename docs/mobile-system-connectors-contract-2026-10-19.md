# 首批系统连接器契约（2026-10-19）

用户已确认首批为日历、联系人、地图、文件、媒体；日历/联系人优先系统编辑器交接，直接读写仍保留在后续范围。已新增“我的 → 系统编辑器连接”手动入口与真实 Android 公开接口，地图/文件/媒体尚未接线，五个连接器仍未完整交付。

| connectorId | operation | 首批输入 | 实际完成判据 |
| --- | --- | --- | --- |
| calendar | prepare_event | title、start、end，可选 location/description | ACTION_INSERT 只准备系统编辑器；不以“编辑器已打开”宣称事件已保存。最终保存由用户确认；未取得资源证据时不得标记业务完成 |
| contacts | prepare_contact | name，可选 phone/email | 只准备系统联系人编辑器，不批量读取/写入通讯录；系统确认不等于拿到保存证据 |
| maps | search_place | query | 用户批准后把编码后的搜索词交给明确选择的地图接收方；不申请定位，不自动开始导航，不宣称到达 |
| files | pick_document | 可选 mimeTypes（默认 */*，最多 8 类） | SAF 单文件选择；取消必须如实返回取消；不扩大目录权限，不把 URI 伪装为路径，不自动上传 |
| media | pick_media | kind=image/video | 系统选择器单项授权；不默认读取整个媒体库，不启动相机，不自动发给模型 |

## 已实现

`lib/domain/system_connector_request.dart` 提供无副作用的严格输入解析。连接器与操作必须匹配，字段白名单，拒绝任意 Intent/URI/command 和伪造 approved 字段。日期必须包含秒与明确 UTC 偏移，可带至多 6 位小数秒，校验实际日历日期与结束时间，规范化到 UTC。MIME 列表规范化、排序、去重；构造后的参数不能被调用者修改。错误消息不回显输入中的联系人/地点内容。

## 后续实现，不得以契约代码替代

全仓静态分析最近复测通过（23.4 秒），日志 `local/temp/major-system-editors-analyze-20261019.log`。Android x64 debug 构建通过并保留数据覆盖安装到 emulator-5554；初次因 ANDROID_USER_HOME 不一致导致调试签名不匹配，已恢复原预览的本地环境重建解决，未卸载/清数据。

模拟器固定契约检查 12/12 通过，报告 `local/temp/major-connectors-emulator-contract-20261019.json`。逻辑在已安装 Android 应用的 Dart isolate 内运行，宿主脚本仅作本机传输；不是宿主 flutter test，也不冒充框架单元测试文件已执行。检查不调用模型、不读写用户数据库、不发起系统交接。入口仅 debug/assert 启用，无任意表达式或参数执行能力；release/profile 不注册。最初动态表达式方案因没有前端表达式编译器返回 RPC 113，已放弃并改为预编译固定检查，未计为通过。

原生适配：`SystemEditorConnectors.kt`；工具适配：`android_system_editor_actions.dart`；页面：`system_editors_page.dart`。动作注册到原 AndroidDeviceTool，使用原 DeviceActionRunner/账本/一次性票据/确认面板/审计，不另建引擎。接收方绑定包名、组件与版本，原生交接前重查；过期、缺失、权限不足等明确拒绝，不自动换接收方或重试。不新增权限、不直接写 Provider、不把 Intent 接受当成业务完成。尚未加入独立签名摘要绑定/实际业务资源版本或持久人工交接事件，不能据此宣称身份、资源和恢复专项全通过。

模拟器 UI：日历确认面板显示接收方组件/版本与规范化 UTC 时间；交接触发 Google Calendar 的账号准备界面，已返回，未登录/点击保存。只验证请求交接，编辑器/保存链路因环境准备保持未通过。联系人已观察到系统 Add to contacts 编辑器，合成名称正确预填；未点击 Save/Add to existing，返回后另一次预览点击放弃，正确显示“已取消，未交接”。没有读取联系人数据库，因此不宣称资源已保存或外部零副作用。证据：`local/temp/major-system-editors-calendar-{approval,handoff,return}-20261019.png`、`major-system-editors-contacts-handoff-20261019.png`、`major-system-editors-contacts-approval-check-20261019.png`、`major-system-editors-contacts-rejected-20261019.png`。

原托管预览已停止，当前通过 `tool/launch_emulator_debug.py` 仅启动已有指定模拟器中的已安装应用，不扫描真机、不启停 ADB 服务。`tool/verify_system_connector_emulator.py` 调用固定 debug 检查。VM 调试认证地址仅保存在 `local/android-preview/vm-service.json`，不得打印/导出；不作为手机账号、配对或远程服务令牌使用。后续代码变化需更新已安装包，不能误以为旧热重载预览还在运行。

1. 继续补 Agent 可发现的能力目录、同应用多组件的可区分标签、地图/文件/媒体适配与完整读写能力，不把两个编辑器交接当作五个完整连接器。
2. Android 公开接口适配、无处理应用/权限撤销/取消/进程回收处理、SAF 和媒体 URI 生命周期、读取限额和敏感信息传播约束。
3. 接收方变化、参数变化、过期或旧计划回调均使旧批准失效；不得从应用启动结果推断保存成功；复用 ToolResult 的 effect，而不另造不兼容结果引擎。
4. 继续在模拟器验证实际完整/拒绝/取消/缺失应用/版本变化/过期等状态。12 项固定输入检查已通过，`test/system_connector_request_test.dart` 的传统框架用例仍未执行；二者分别登记，不合并冒充覆盖。
5. 需要原生改动时重新构建并仅部署到 emulator-5554；不重启/断开全局 ADB，不操作真机。
6. 真机专项最后先说明影响并单独询问用户；未获许可不得执行，不以模拟器冒充厂商兼容或 ARM64 通过。
