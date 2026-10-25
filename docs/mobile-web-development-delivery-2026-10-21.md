# 手机网页开发：首批实施与验收

日期：2026-10-21。依据用户对后续开发的全权授权，接续 ETA 对照规划，首先推进 D01 的静态网页开发链路。保留通用助手、现有 Agent/审批体系及其他未提交改动；没有新增依赖、提交或推送。

## 已实现

- 从模板创建项目后打开项目主页，用户可继续开发、编辑文件或预览交付。工作区作为手机底部标签时，选择项目或点击“继续开发”会切到助手，不再尝试弹出工作区根页面。原弹出式项目选择器保留返回值行为。
- 新增「网页预览与交付」页面，接入静态网页项目主页。
- Dart 内置 HTTP 服务直接预览网页，无需 Python、Node、Termux 或 Alpine。静态网页主页不再为了此流程探测 Shell/工具链；已有自定义预览命令保留为单独入口。
- 浏览器读取当前文件；用户在文件列表中进入现有编辑器保存，再刷新浏览器查看修改。离开交付页会关闭本页拥有的预览服务。
- 导出前列出实际网页资源，记录大小与 SHA-256。核对后发生修改或删除的文件会阻止保存，刷新核对后可恢复。新出现的文件不会混入已核对的导出。
- 保存 ZIP 时复用 ArtifactService，将独立副本和结果卡写入现有成果系统；继续修改源码不会覆盖该副本。导出前再次校验副本完整性，然后打开系统分享界面。
- 新静态模板 README 使用上述流程，不再要求安装 Python。保留原有命令式预览服务及 Node/Python 等其他模板。

## 范围与实现边界

本批提供本机静态预览、手动编辑、文件核对和 ZIP 交付。仍复用既有聊天/项目绑定处理模型开发请求；本批未调用真实模型，不能据此宣称已验收模型自主完成整条开发任务。

预览仅监听手机自身回环地址，使用随机会话路径；拒绝无会话路径、非预期 Host、写请求、隐藏路径和项目外资源，不提供目录列表或原生 JS 桥。支持模板所用的相对资源路径，不承诺根绝对资源路径或服务端 API。

资源范围是 HTML/CSS/JavaScript、JSON、图片、字体及部分媒体/wasm 等网页资源。隐藏文件、依赖/缓存目录、符号链接及其他文件类型不进入核对清单。清单供用户核对，不自动证明资源内没有隐私信息，也不证明网页功能正确。

当前上限：1000 个资源、单文件 8 MiB、总计 32 MiB；目录扫描有条目与深度上限，超限明确失败。用户源码不被打包操作改写，只有本次独占临时目录会清理。

## 验收结果

| 检查 | 结果与边界 |
| --- | --- |
| 全项目 `flutter analyze --no-pub` | 已通过；后续小改会在交付前再次核对，以最终日志为准 |
| 功能与分层回归 | 8 个文件、82 项通过：新服务、新交付页、项目选择、项目服务、手机导航、预览服务、项目主页及分层 |
| 新交付页四态 | 360dp/1.6x、360dp/2.0x、360dp 深色/1.6x、640×360 深色/1.6x；模拟器 UI 检查通过 |
| 模拟器真实成果保存 | 隔离数据库与成果目录中保存 1 个可校验 ZIP，实际包含 index.html 和 styles.css；未写入用户数据库 |
| 实际浏览器 | Android Chrome 显示中文 HTML 与 CSS 样式，点击按钮后显示“交互通过”；系统提示无互联网时，本机预览仍可使用 |
| 现有原生浏览器回归 | 当前构建上的固定 WebView 测试 23/23 通过，不调用模型；不等于复杂网站和完整 A4 字段排除矩阵全部验收 |
| 预览状态 | 已构建 Android debug，终端确认 Ready；后续 Dart 修改确认 Hot reload complete，预览保持运行 |
| 差异空白检查 | 本批已跟踪修改通过；新文件单独检查格式 |

功能回归最初暴露了过期夹具：项目服务测试仍断言 schema 27，当前数据库源码为 32；模板选择测试初始化了真实 ChatController 并遗留计时器。已更新版本断言并改用隔离控制器。新增页面流程测试还补齐了编辑保存完成、导航和提示消息定时器的正确等待；没有降低功能断言。

另行扩大检查时，`code_quality_guard_test.dart` 的既有 Duration 扫描门禁仍失败：41 处，上限 35。核对本批既有页面的修改前快照与修改后源码，新增 Duration 匹配均为 0，新交付页也为 0。没有提高门槛、改写该门禁或为了消除计数修改其他页面。因此不能把本次结果写成整个 CI 全绿。

## 证据与复验

证据目录：`local/temp/mobile-dev-20261021/`（Git 忽略）。

- `baseline.json` 与 `before/`：动手前所选文件指纹/快照，保留原有未提交工作。
- `functional-regression-final.log`：82 项通过。
- `analyze-final.log`：最终静态分析输出。
- `emulator-web-delivery.json`：模拟器四态、成果 ZIP 验证及当时完整 lib 源码指纹。`sourcesUnchanged` 只覆盖该次运行，不是签名 APK 对所有源码的发布证明。
- `web-delivery-*.png`：实际模拟器截图。
- `browser-acceptance.json`、浏览器截图与 UI 层级：实际本机浏览器渲染/交互结果。
- `browser-native-contract.json`：原生 WebView 固定测试结果。
- `regression-final.log`、`style-gate-comparison.json`：扩大门禁失败及本批未增加 Duration 计数的对照。

复验命令：

```powershell
# 先检查实际设备与预览，不重复启动。需要使用现有 Nexus_Preview_API_36。
./local/android-sdk/platform-tools/adb.exe devices
python tool/verify_static_web_delivery.py

# 使用工作区缓存与临时目录后，运行指定回归，不运行全量测试。
$env:PUB_CACHE = "$PWD/local/pub-cache"
$env:TEMP = "$PWD/local/temp"
$env:TMP = $env:TEMP
flutter test --no-pub test/static_web_delivery_page_test.dart test/static_web_project_service_test.dart test/project_picker_test.dart test/project_service_test.dart test/mobile_shell_test.dart test/preview_service_test.dart test/project_home_mobile_compact_test.dart test/layering_test.dart
```

本次设备为 emulator-5554 / Nexus_Preview_API_36，未操作真机、发送模型请求或改动签名密钥。x86_64 模拟器不能验证 ARM64 PRoot、本地原生工具链、长期后台存活或发布性能。

## 规划状态与后续

- B01：已保存本批基线与证据，整版质量/发布门禁仍未全部关闭。
- B02：当前原生固定回归已复验；A4 完整字段矩阵及复杂站点仍待完成。
- B03/D01：静态网页手动开发与交付链路已落地，真实模型端到端验收仍未完成；Node/Python 的完整交付流程继续推进。
- D02：本地交互 PTY 与 Agent 运行环境统一尚未实施，ARM64 验收需相应设备证据。
- D03：Git 认证、分支与远端交付尚未实施。
- A01–A04、R01–R02：仍按原双主线规划推进，不能因本批交付而标记完成。
