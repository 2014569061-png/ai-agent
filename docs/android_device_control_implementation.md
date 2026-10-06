# Android 手机应用与文件操作技术路线

## 功能边界

在 Android Agent 对话中理解“打开微信”“找一下授权目录里的合同 PDF”等自然语言请求。应用启动和文件打开属于对前台界面的实际操作，每次都通过现有工具审批机制确认。文件访问仅限用户在 Android 系统文件夹选择器中明确授权的目录，不扫描整个设备。

## 架构与落地步骤

1. Flutter 侧新增 `AndroidDeviceTool`，使用结构化 action 表达列出应用、启动应用、授权目录、搜索文件、打开文件。
2. `ChatController` 只在 Android 前台 Agent/计划执行注册工具；普通聊天按明确设备操作指令自动切换到 Agent。工具受现有 `settings.tool.workspace_files` 开关控制。
3. Android `MainActivity` 通过 `nexus/device_control` MethodChannel 提供对应原生操作。
4. 应用发现查询 `ACTION_MAIN + CATEGORY_LAUNCHER`，Manifest 只声明同一 launcher intent 的 `<queries>` 可见性，不申请 `QUERY_ALL_PACKAGES`。启动只接受查询结果中的 package name。
5. 首次文件搜索打开 `ACTION_OPEN_DOCUMENT_TREE`。系统返回 tree URI 后调用 `takePersistableUriPermission`，保存授权 URI。递归搜索在单独 worker 线程中使用 `DocumentsContract`，最大深度 12、最多检查 10,000 个条目、返回最多 100 项；Flutter 30 秒超时会取消请求。
6. 文件以 `content://` URI 表示。`open_file` 校验 scheme 后用 `ACTION_VIEW` 交给系统处理器打开，不向 Dart 暴露文件系统绝对路径。
7. 后台 headless executor 不注册该工具，避免无人值守任务启动应用或访问用户文件。
8. 用户可列出并移除授权目录；移除时同步释放 Android 持久 URI 读取授权。
9. 设备能力工具增加 Root 状态、设备信息、存储空间、网络连接、运行进程、前台应用、Logcat 和应用信息查询；这些查询只读，不自动执行 Root 命令。应用按名称启动使用单次匹配，精确匹配失败时返回候选项，不盲目选择。
10. Root 控制目前只开放固定动作：停止应用（`am force-stop`）、清理应用数据/缓存（`pm clear`）、读取/列举/写入/删除/移动受限文件，以及网络连通性探测。文件操作只允许 `/sdcard`、`/storage/emulated/0`、`/data/local/tmp`，读取最多返回 64 KiB、目录列举最多返回 32 KiB、写入最多 64 KiB，并由原生侧拼接固定命令执行，不开放任意 Shell 文本。

## 验收

- Flutter 工具测试覆盖参数校验、应用列表、启动、首次目录授权提示、文件搜索和打开 URI。
- `flutter analyze` 与 Android debug APK 构建通过。
- 真机验证：自然语言打开可见应用；首次搜索出现目录选择器；选择目录后可搜到其中匹配文件；用户确认后系统打开文件。
- Android 系统或文件提供器不可见/不允许访问的目录应返回受限结果，不扩大权限绕过。
- 大目录搜索达到预算时返回 `truncated`，超时取消后不继续占用界面线程。
- 停止应用或清理应用数据前必须经过现有工具确认；清理应用数据可能导致登录状态、设置和本地数据丢失，不能承诺撤销。
- Root 文件读取前必须经过现有工具确认；路径不允许跳出白名单目录，结果超过 64 KiB 时返回截断标记。
- Root 目录列举前必须经过现有工具确认；只列出当前目录一层，输出超过 32 KiB 时返回截断标记。
- Root 文件写入、删除、移动和网络探测前必须经过现有工具确认；写入覆盖、删除和移动均不可保证撤销。

## 后续 Root 能力边界

应用已有加密备份/恢复页面和定时任务基础设施；设备级系统分区备份受 Android 版本和厂商限制，不作为通用工具开放。备份动作可接入 Agent 计划，但后台任务不得静默执行 Root 设备操作，仍需前台确认。Root 命令不应直接由模型拼接执行，而应由带参数校验、目标范围和撤销策略的白名单工具承接；每个高风险工具都要记录审计日志并显示实际影响范围。
