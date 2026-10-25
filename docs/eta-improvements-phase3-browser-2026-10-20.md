# Eta 参考改进：第三阶段，Android 浏览器（2026-10-20）

已接通 Android 内置浏览器的基础操作流程：独立临时会话、导航、正文与 DOM 观察、审批后的点击/输入/滚动、用户接管和关闭清理。复用现有 ChatController、工具审批管线、运行预算、取消与持久化脱敏机制，没有增加第二套 Agent Runtime。

## 使用

1. 在助手页点击左上角会话列表，选择「会话与工具」，再打开「内置浏览器」。运行中的任务须先结束。
2. 输入 HTTP(S) 地址后打开网页，可以直接手动浏览。HTTP 是否可用仍受 Android 网络安全配置限制。
3. 点击「允许助手操作」，在页面底部输入任务。发送时使用当前会话与模型，进入 Agent 模式；正常使用会产生所选模型的请求费用。
4. 点击、输入、滚动与导航均逐次确认，包括完全访问模式。审批展示网页、目标标签与输入内容。
5. 触碰网页即可收回控制权；也可点击顶部手掌按钮或「接管并停止」。关闭页面会结束本次浏览器会话，后续打开需重新登录。

浏览器使用根导航页面，覆盖手机标签栏，避免标签切换后把浏览器留在不可见的缓存页面。切到后台会撤销控制权，回到前台不会自动恢复。关闭、接管、异步结果和会话切换均有所属会话校验。

## 实现边界

- `browser_session.dart` 定义平台端口和 URL 校验；`AndroidBrowserTransport` 只负责平台通信。
- `BrowserSessionService` 管理当前页面会话与观察缓存。`BrowserAgentTool` 固定绑定构造时的会话 ID 和会话所有者；同一聊天重新打开浏览器，也不能被旧运行实例借用。
- 平台事件使用共享广播流，一个服务取消订阅不会切断其他服务；关闭会话释放订阅，重新打开重新连接。地址栏跟随实际导航，手动编辑地址会收回助手控制权。
- 原生 `BrowserBridge` 使用 AndroidX WebKit 的独立 profile，隔离 cookie 和站点存储；不支持多 profile 的 WebView 明确返回不可用，不退回共享默认 profile。
- 关闭时销毁 WebView 并请求删除该 profile；系统可能异步清理磁盘数据。删除暂时受引擎限制时记录类型，下次打开继续回收本模块的废弃 profile；不会清除应用默认 profile 或复用旧 profile。不能把“关闭会话”解释为即时安全擦除所有磁盘字节。
- 只接受 HTTP(S)，拒绝带用户名/密码的 URL、文件、content、intent、data、javascript 等导航；不开放网页到 Android 的 JavaScript 原生接口。
- 观察按预算遍历顶层文档与开放 Shadow DOM：元素、文本、注释及开放根共用 8000 次节点访问，原始文本扫描最多 24000 个 UTF-16 单元，深度最多 64；最多返回 120 个可见操作节点和 12000 个 UTF-16 单元的正文。正文可包含屏幕外的已渲染内容，隐藏、脚本及编辑字段的子树跳过，不保证还原完整的 composed tree 排版；输入框 value 不返回，密码和文件字段排除。跨域/同源 iframe 与封闭 Shadow DOM 不遍历。网页主动展示的正文仍可读取，网页内容显式标为不可信数据。
- 模型收到的完整浏览器成功结果信封按 `ToolResult.encode()` 的 UTF-8 编码限制为 32 KiB（不是平台通道内存或 WebView 提取成本上限）。超限时先裁减尾部节点，再按 Unicode 边界缩短正文；`payloadTruncated`、`nodesTruncated`、`textTruncated` 分别说明载荷、节点和正文截断，原有 `truncated` 保留页面观察本身的截断含义。被截掉的节点不进入审批缓存。必要元数据仍超限时返回 `BROWSER_PAYLOAD_TOO_LARGE`，不悄悄改写 URL 或快照身份；已派发动作仍保留副作用状态。没有分页或续读接口，截断时 `continuationAvailable=false`，可滚动后重新观察；重新观察不保证读取到之前被省略的全部内容。
- 开放 Shadow DOM 中的节点沿用相同快照、逐次审批和一次性授权；每个已发现的开放根单独监听 DOM 变化，目标失效时安全拒绝。Shadow DOM 内表单关联的 `<label>` 也作为目标名称来源。
- 点击和输入绑定观察快照及节点，滚动绑定快照，导航绑定目标 URL；所有写操作还绑定控制代次与两分钟有效期，使用审批管线签发的、绑定参数的一次性授权。页面导航、DOM 变化、接管及执行完成后，旧引用失效。已派发却无法确认的动作返回 `ToolEffect.unknown`，要求先观察，不能盲目重放。
- 参数与结果加入持久化脱敏名单。运行中的模型仍能读取网页完成任务；这不意味着模型生成的最终回复也会自动隐藏用户所请求的信息。

AndroidX 新增依赖固定为 `androidx.webkit:webkit:1.12.1`，缓存下载位于工作区 `local/gradle-cache/`。没有新增 Flutter 依赖。实现依据 Android 官方的 [profile 隔离接口](https://developer.android.com/reference/androidx/webkit/WebViewCompat#setProfile(android.webkit.WebView,java.lang.String))、[profile 删除约束](https://developer.android.com/reference/androidx/webkit/ProfileStore#deleteProfile(java.lang.String))及 [WebView 原生桥安全说明](https://developer.android.com/privacy-and-security/risks/insecure-webview-native-bridges)。

## 验证

| 检查 | 结果 |
| --- | --- |
| 全项目 `flutter analyze --no-pub` | 无问题 |
| 浏览器页面/会话/传输、注册表、摘要、审批管线、分层、聊天、恢复、运行完成、脱敏十一项测试文件 | 分批共 108 项通过，重复复核不重复累计 |
| 最终事件/页面/会话回归 | 26 项通过，包含双倍字号的窄屏与横屏、地址栏同步、共享订阅及后台接管恢复；计入上面的文件，不重复累计 |
| 共享模拟器传输脚本回归 | 7 项通过 |
| `python tool/verify_browser_native.py` | 真实 Android WebView 固定页面 23/23 通过；包含开放 Shadow DOM 读取、输入、点击、结果读回及旧目标失效；未请求真实模型 |
| 模拟器后台/恢复 UI 验收 | 任务获助手控制后按 Home，再返回 App；浏览器保留，自动回到手动控制，没有自动续权或 Flutter 错误 |
| 空 catch 门禁 | 未说明意图 0，原有带说明的 117 处保留 |
| 页面依赖门禁 | infrastructure 导入 78、数据库导入 21，原门槛未提高 |
| Android 调试构建与预览 | 构建安装成功，预览终端 Ready；后续编辑成功热重载 |

原生检查在 `Nexus_Preview_API_36` / `emulator-5554` 中执行，覆盖真实 DOM 提取、排除密码字段、输入后点击及结果读回、文档与 Shadow DOM 目标变化后的原生拒绝、导航读回、接管后拒绝、关闭后拒绝，以及新 profile 不继承前一个会话的站点存储。使用打包的固定页面与专用 `.invalid` 域名，由原生拦截响应；调试入口只在 debuggable 包开放，不接受任意 URL、脚本或测试参数，不触碰已有浏览器会话。

还从真实手机 UI 打开 `https://example.com`，确认 WebView 渲染、手动/助手模式切换及触碰接管；未发送模型任务。截图和结构化结果保存在 `local/temp/eta-browser-20261020/`。

未运行全量测试、ARM64 真机或真实付费模型端到端验收；上述结果不能替代正式发布门禁。

## A1＋A2 载荷契约复核（2026-10-20）

- 修正模型工具描述：支持可见开放 Shadow DOM，不支持封闭根和 iframe。
- 新增 `BrowserPayloadBudget`，限制模型出口完整 JSON 信封为 32 KiB；截断后的节点集合同时替换审批缓存。不增加运行依赖或平台权限。
- 恢复 MCP 连接后重新执行五个测试文件：`browser_payload_budget_test.dart`、`browser_session_test.dart`、`browser_transport_test.dart`、`browser_page_test.dart`、`android_accessibility_observe_tool_test.dart`，共 **44 项通过**，进程退出码 0。
- 四个本批 Dart 文件格式检查通过，0 个文件需要格式化。静态检查初次发现两条提示（花括号与多余转义），修正后以 `dart analyze --fatal-infos` 复核四个本批 Dart 文件，结果为 `No issues found`；修正后重新运行同一组测试，仍为 44 项通过，不重复累计。
- 本次仅验证 Dart 层预算、工具契约及回归；未运行新的原生 WebView、ARM64 真机或真实模型验收，也未运行全量测试。该出口限制不约束 WebView 内部正文提取和平台通道内存，该记录为 A1＋A2 快照，后续遍历预算见下面 A3。

## A3 共享遍历预算（2026-10-20）

- `browser_dom.js` 将正文、开放根与标签文本统一到一次惰性 sibling-cursor 遍历，不再读取整段 `body.innerText`、独立 Shadow TreeWalker 或先复制完整子节点集合。文本规范化前先截取有限前缀，正文和标签不使用聚合 `innerText` / `textContent`。标签只复用同一遍历中读到的文本，至多关联 4 个 label。
- 返回 `observationBudget` 的已访问节点数、已扫描 UTF-16 单元数与各上限；`truncationReasons` 区分 `node_budget`、`text_scan_budget`、`text_output_budget`、`depth_budget`、`control_budget`、`label_budget`。A2 的最终信封字节限制及其独立截断标记继续生效。
- 达到 120 个操作节点后继续在其余预算内提取正文，不因操作列表填满就丢失后面的正文。省略的节点不能用模型未见过的 ID 获得审批。MutationObserver、快照 ID、控制代次和一次性票据规则保留；文本变化通过观察器拒绝旧快照，而不生成无界文本指纹。
- 新增 `tool/browser_dom_budget_checks.html`：在项目根目录启动仅本机 HTTP 服务（例如 `python -m http.server 8765 --bind 127.0.0.1`），打开 `/tool/browser_dom_budget_checks.html`。页面加载同一份生产脚本，运行固定 iframe 用例；可通过 `window.budgetChecksDone` 获取结构化结果。只运行可信本地测试页面，不加载任意外部网站，不调用模型。
- 使用生产脚本与测试页的相同内容在独立工作区的桌面 Chromium 中实测 **14/14** 通过，覆盖大 sibling 列表、稀疏注释、多开放根、深度、超长文本、空白、跨文本节点预算、emoji、控件上限、字段排除、屏幕外正文、标签、动作及 Shadow 变更失效。耗时仅为测试环境观测，不作为手机性能承诺。
- NEXUS 上五个 Dart 测试文件重新执行，**44/44** 通过，退出码 0；这是同一组回归，不与前阶段累计。
- 未重新构建 APK、更新现有模拟器或运行新的 Android 原生固定页检查；`BrowserBridge` 在初始化时加载脚本，现有 App 进程不会自动采用源码改动。Android WebView / ARM64 真机验证仍需后续重建并验收，旧原生报告不能作为本次源码证据。
- 预算约束的是脚本节点访问及原始文本扫描，不是硬性墙钟超时；浏览器布局、样式计算、DOM 属性访问及页面自身 JavaScript 的耗时不在该保证内。未遍历的节点、封闭根、iframe 或复杂 slot 排版仍可能缺失。A4 的完整输入值排除矩阵仍待补充，本批字段哨兵用例不能替代它。

## 仍待完善

当前是 Android 基础版本。尚不支持跨域/同源 iframe、封闭 Shadow DOM、文件上传、密码自动输入、截图视觉定位、多标签、跨会话保留登录状态或 Windows 浏览器自动化；现有 Windows 网页预览仍是另一项功能。页面遍历受 8000 个元素与 120 个目标上限约束；复杂或高频更新的站点可能需要用户滚动、重新观察后再继续操作。

应用进入后台时原生与 Flutter 两侧都会收回助手控制；恢复前台不会自动重新授权。页面级生命周期回归验证了这一恢复规则。独立的 Android 无障碍只读观察第一阶段已另记于 [Phase 4](eta-improvements-phase4-accessibility-2026-10-20.md)：目前只读 NEXUS 自身当前窗口，不包含跨应用观察或任何无障碍动作。ARM64 真机上的 WebView profile、生命周期及 ROM 行为仍待验证；跨应用 GUI、ROM 私有数据适配和其他设备上的真实模型成功率，仍是与 Eta 对比时未完成的部分。
