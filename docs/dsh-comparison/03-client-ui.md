# 03 · DSH 客户端 UI 交互契约

> 调研对象：DeepSeek Harness 桌面版运行时源码，位于 D:\\DeepSeek\\ds\\resources\\app.asar\\dsh（Electron app.asar 解包目录，只读）。
> 本文所有「文件路径」均相对于 dsh/。行号对应 0.2.0-rc.2 版本的已构建产物（lib/*.js 由 tsdown 从 src/ 打包而成，因此行号指向打包产物），README 则属于该包源码树的一部分。
> 本文只记录事实与契约，不含对 NEXUS 的建议。
>
> **取证限制（请先读）**：本会话的 read / glob / grep 工具在 app.asar 路径上全部失败（报错形如 rg: IO error ... 系统找不到指定的路径，os error 3），pwsh 也不可用（spawn UNKNOWN）。因此本次调研在 run_code 内用 Node 的 fs 读取文件、用 Node 正则自行计数行号；**所有行号均为程序化精确计数**，且在写入本文前对每条引用的行号做过一次回读校验。源码树 src/*.tsx 不在发布产物中（包内只有 lib/index.js、lib/client.js、lib/types/**/*.d.ts，见各包 package.json 的 files 字段），所以凡涉及 .tsx 源文件的行号一律标注「未核实」。

---

## 0. 客户端插件的整体形态（背景事实）

- 每个客户端插件包都有两半：Node 半边（lib/index.js）与浏览器半边（lib/client.js）。以 Jobs 为例，Node 半边是空实现：「Node half of the background-job list plugin. The browser half in src/client/ owns every contribution; this entry exists so the package appears as an ordinary Loader row.」—— node_modules/@deepseek-ai/dsh-client-ui-jobs/lib/index.js:2-8，其 apply() 函数体为空（同文件 :9，注释「Loader-visible no-op body; the browser half carries the feature.」）。
- 浏览器半边通过包声明接入宿主，声明字段是 dsh.client。ui-chat 的声明在 package.json 中起于 :30（字段 dsh），其 client.platform 为 web，client.inject 覆盖 11 个包：dsh-api-session-controller、dsh-api-workspace-controller、dsh-client-locale、dsh-client-ui-conversation、dsh-client-ui-input-trigger、dsh-client-ui-layout、dsh-client-ui-renderer、dsh-client-ui-session、dsh-client-ui-settings、dsh-client-ui-sidebar-right、dsh-client-ui-workspace —— node_modules/@deepseek-ai/dsh-client-ui-chat/package.json:30-52。该包的 exports 只暴露「.」与「./client」两个入口，main 为 lib/index.js —— 同文件 :14-25。
- 构建产物必须提前存在：「The host serves built client bundles, so pnpm run build must have produced each lib/client.js before launch; a missing bundle fails activation loudly with one build instruction and a package/path list.」—— node_modules/@deepseek-ai/dsh-client-modules/README.md:50。
- **未核实**：本机不存在 DSH 的可写源码检出（D:\\DeepSeek\\dsh 为空目录，D:\\DeepSeek\\ds\\resources\\app.asar.unpacked\\dsh 下只有原生依赖与少数包）。因此无法核对 src/ 的真实文件结构与 .tsx 行号，也无法做「源码 vs 产物」一致性校验。

---

## 1. 会话内右侧资源面板（right Sidebar）

包：@deepseek-ai/dsh-client-ui-sidebar-right。它对外暴露两个服务：导航控制器 ctx.sidebarRight 与 tab 类型注册表 ctx.sidebarRightTabs。

### 1.1 页面（tab 类型）如何注册

- 两个服务通过一个 effect 内的 ctx.reflect.provide 提供，并随该 effect 一起拆除：「The two services (sidebarRight, sidebarRightTabs) are provided through ctx.reflect.provide inside one effect and torn down with it」—— node_modules/@deepseek-ai/dsh-client-ui-sidebar-right/README.md:159。源码对应两行：disposeRegistry = ctx.reflect.provide("sidebarRightTabs", tabs) 与 disposeService = ctx.reflect.provide("sidebarRight", controller) —— 同包 lib/client.js:9073-9074。
- 注册分两阶段，且两阶段都要求放在插件自己的 ctx.effect 内；README 说明「A tab type registers in two stages, and the shipped guide type goes through exactly the same public path a type from another package does (ui-sidebar-documentpreview is the live proof). Both stages sit inside the type's own ctx.effect, so the registration lives exactly as long as the plugin that made it.」—— README.md:81。
  1. **类型声明**：ctx.sidebarRightTabs.register({ id, kind, patterns?, priority?, canOpen?, title, guide?, keepMounted? })，是静态声明、无运行时 hook，返回一个 disposer；id 是该实现于 tab 系统中的身份、跨所有注册唯一，同一个 id 注册第二次会抛错；kind 至多一个 builtin 与一个 extension（extension 生效，builtin 在其离开后恢复），其它同 kind 冲突也抛错 —— README.md:83。
  2. **页面主体**：ctx.slots.register({ name: 'sidebar.right.pane.tab', key: definition.id }, Body)，主体通过框架注入的 useTabInfo() 读取 { sidebar, panel, tab } —— README.md:84。
- patterns 是 dsh-resource:// 地址上的 glob：含冒号的匹配整个地址（如 dsh-resource://file/**）；不含冒号的匹配 URI 路径任意深度、忽略大小写（如 *.md）；非 URI 地址不匹配任何此类 pattern。page 类型（guide、文件树）不声明 patterns，按 kind 打开 —— README.md:83。
- 类型选择遵循 editor-resolver 约定：先按 priority band（extension 最高、且未指名时即为默认；然后 builtin；最后 fallback），再按匹配 pattern 的长度，再按注册顺序；canOpen 用于剔除候选。band 是字符串字面量，因此别的包里的类型无需从这里做运行时 import —— README.md:86。
- 内置 guide 自身的注册位置：ctx.slots.inject("sidebar.right.pane.tab", ...) 于 lib/client.js:9200，register 于 :9201；标题座位同理在 :9217-9218（sidebar.right.pane.tab.title）。
- 另有两个扩展座位：sidebar.right.tab.guide（chain，替换 guide tab 的主体而不替换 tab）与 sidebar.right.tab.menu.item（list，在 kit 自身布局动作之后追加内容级菜单项）—— README.md:88。菜单座位的源码证据：renderTabMenuItems: (tab, dismiss) => renderSlot("sidebar.right.tab.menu.item", {...}) —— lib/client.js:5699。
- guide 入口座位：renderSlot("sidebar.right.tab.guide.entry", {...}) —— lib/client.js:517；README.md:115 说明 guide 按 provider 的 definition id 渲染该座位。

### 1.2 布局如何持久化

- 每个 Session 一份 SurfaceState（布局、其记录下来的操作序列、以及已铸造的 id 计数），保存在注册时声明的 store 中。每个动作形态固定为：铸造意图所需 id → 问 kit planner 哪些操作能实现它 → 记录这些操作 → 把整个 surface 回写该 session。没有任何动作原地修改布局，这是让 kit 的纯函数成为唯一计算布局者的关键 —— README.md:66。
- 存储键与载荷：「The store saves each Session's layout, tab identities, selection, split ratios, floating rectangles, presentation and identity counter as JSON under dsh.sidebar-right.v1.<sessionId> in localStorage.」—— README.md:74。源码证据：常量 const sidebarPersistence = "dsh.sidebar-right.v1"; —— lib/client.js:4914；读 raw = localStorage.getItem(...) 于 :5001；写 localStorage.setItem(...) 于 :5033；删 localStorage.removeItem(...) 于 :5045；启动发现遍历以 dsh.sidebar-right.v1. 开头的 key 于 :6198；store 由 defineStore 创建于 :5241（注释「Create the Sidebar store handle with per-Session JSON persistence in localStorage.」在 :5232）。
- 恢复时机与作用域：「Reload restores that layout before tab bodies render; switching Sessions keeps their layouts independent.」—— README.md:74。
- 校验与失效粒度：「Saved field types, node membership, selection, identity counters and the one-pane or two-horizontal-pane dock layout are validated before adoption or startup discovery; invalid data clears only its Session key. Storage failures leave the current layout usable in memory.」—— README.md:74。
- 多窗口：「Windows at the same origin share the last saved layout per Session; each active window keeps its own current layout until reload.」—— README.md:74。
- undo/redo 不进持久化：「Undo history stays in memory and resets on reload.」—— README.md:74；且未向用户暴露，只有 @internal 的 _undo() / _redo() —— README.md:145（Known Limitations 段起于 :137）。
- 启动发现只读布局键、不挂载休眠内容：「Startup discovery reads the layout keys without mounting dormant content, pinning files or activating Agents.」—— README.md:76。
- 跨设备不同步（已知限制）：「Browser-local layout. Layout does not synchronize between devices; provider-specific state requires its provider's recovery support.」—— README.md:141。

### 1.3 会话切换时保留什么

- 每个 Session 一份独立 SurfaceState，键为 session id —— README.md:66；切换 Session 时各自布局互不影响 —— README.md:74。
- 每个 (Session, tab id) 上有一个 Tab domain 记录：带品牌的 occurrence id、navigation、一个 abort signal 与绑定好的 actions。它由一个私有 assembly 回调接收每个 Session 的 store、立即对已恢复记录做 reconcile 并跟随其提交；重建 Session store 会替换其 adoption，释放旧的订阅与清理引用 —— README.md:104。
- **中断边界**：「Only record removal or plugin unload aborts the signal; closing the sidebar and switching Sessions retain records, while undo restores a new occurrence.」—— README.md:104。即关闭侧栏、切换会话都保留 tab 记录；只有记录被移除或插件卸载才 abort。
- **关闭处理器不被这些动作调用**：「Collapse, presentation changes and plugin disposal do not invoke close handlers; the tab abort signal identifies occurrence disposal, not an explicit close.」—— README.md:108。
- **内容恢复靠 provider 自己**：「Providers restore their own content from the retained tab identity and resource address, including terminal reconnection.」—— README.md:74。
- **不属于布局状态**（因此不会被恢复）：「Navigation parameters, resource contents and live connections are not layout state.」—— README.md:74。
- 后台会话的保留机制：「The root-scoped rightbar entry renders the selected Session and background Sessions with initialized keepMounted bodies through separate rightbar.session subtrees. Each View owns its Session reference. Only the foreground subtree reports a frame track; other subtrees stay hidden without deleting tab state.」—— README.md:61。
  源码证据：children: renderSlot("rightbar.session", {...}) —— lib/client.js:5858；右栏根座位注册于 ctx.slots.inject("rightbar", ...) + ctx.slots.register({ name: "rightbar", ... }) —— lib/client.js:9138-9140；子座位 register({ name: "rightbar.session", ... }) —— lib/client.js:9150-9151。
- 无会话则无面板：「Without a session there is no button and no panel.」—— README.md:57；对应已知限制「No surface without a session. State is keyed by session id, so the hero screen shows nothing on the right.」—— README.md:142。
- 会话切换后回到面板的入口是会话头部角落座位 conversation.session.header.corner；该按钮与面板共用同一个 store：「It shares the panel's store (the slot runtime allows one handle across two same-scope seats); while the panel is shown it renders nothing, and the corner seat collapses with it.」—— README.md:57。源码：ctx.slots.inject("conversation.session.header.corner", ...) 与 register({ name: "conversation.session.header.corner", ... }) 于 lib/client.js:9187-9188。
- keepMounted 的保留范围：「A type's keepMounted: true retains visited bodies across tab and Session changes, collapse, and docking. Unvisited bodies are not mounted eagerly.」—— README.md:106；判定源码：const retained = seat === "sidebar.right.pane.tab" && definition?.keepMounted === true; —— lib/client.js:5522，以及 keepMounted: (tab) => types.find((type) => type.kind === tab.kind)?.keepMounted === true —— lib/client.js:5698。

### 1.4 打开资源 / 打开页面的导航契约

- openResource(address, options?) 与 openTab(kind, options?) 是导航控制器，「every way into the column calls one of them」—— README.md:93。
- 去重规则：「a resource tab already showing the same (kind, contentId) is focused wherever it sits unless revealIfOpened: false; ordinary page tabs always deduplicate within the target pane, regardless of that option」—— README.md:93。
- 落点顺序：options.replaceTab 所在 pane 与 slot（并关闭该 tab）→ options.paneId → 当前活动 docked pane；随后「the panel expands, because content the user cannot see is not opened」—— README.md:93。
- 导航参数由 Tab domain 记录并推进 revision：params 以 navigation.params 抵达主体，这发生在布局历史之外 —— README.md:93。
- 错误契约：「An address outside dsh-resource://, one no type claims, or a kind nothing registered throws: that is a wiring mistake, not a user error.」—— README.md:93。
- 面板展示模式由座位上报：「The seat reports presentation through ctx.layout.openRightbar(track, fullscreen) / closeRightbar(); the frame does not inject this package.」—— README.md:48。两种展示模式定义见 README.md:37-51；push 为默认（面板占宽、会话让位并在同一曲线上滑动）—— README.md:43。
- 窄屏自动全屏：「Opening below 768px uses fullscreen automatically; leaving fullscreen on a narrow viewport closes the panel, and widening does not reopen a closed panel.」—— README.md:39。
- 分栏预算：「The product allows two horizontal panes, initially equal, with divider ratios limited to 20%–80%. Insufficient width blocks a new split…」—— README.md:121。
- 打开同文件时的复用与 revision：「Opening the same file without revealIfOpened: false focuses its existing tab and delivers a new revision.」—— node_modules/@deepseek-ai/dsh-client-ui-sidebar-documentpreview/README.md:124。

---

## 2. Jobs 控件

包：@deepseek-ai/dsh-client-ui-jobs。浏览器半边 lib/client.js 共 630 行（程序计数）。README 段落位置：Use this package 起于 :26，One row per job 为 :30，The expanded panel 为 :36，Understand the implementation 为 :43，Further Exploration 为 :61，Model Experience 为 :70，Known Limitations 为 :78，Dev Note 为 :87。

### 2.1 状态聚合模型

- 单一花名册（roster）：job.list 流由 ctx.jobs 镜像；每一行 JobView 携带生命周期、时长、实时 progress 行或终态 detail、以及保留字节数；「a live job, or a settled one with retained output, is what makes a row expandable. There is no second roster to join.」—— README.md:32。
- 静态行 vs 可展开行：「Live jobs and settled jobs with retained output offer expandable output panels; collapsing stops the stream. Live rows lead with a ticking duration, followed by kind and status. Settled rows fold under a section heading; those without retained output, including subagents whose answers went to the model, stay static.」—— README.md:12（Summary）。
- 可观测判定源码：function isLive(job) { return job.status === "running" || job.status === "stopping"; } —— lib/client.js:67-69；function isObservable(job) { return isLive(job) || job.output.total > 0; } —— lib/client.js:74-76。
- 观测层由 api-job-controller 安装：「Expanding an observable row opens that job's output observation stream from ctx.jobs (installed by dsh-api-job-controller) into an embedded terminal panel.」—— README.md:38。
- 组件不持有传输状态：「All data arrives through ctx.jobs — the component holds no transport state.」—— README.md:48。
- 状态点语义（源码）：function dotState(status) 将 running 映射为 ongoing、stopping 与 killed 映射为 warning、completed 映射为 done、failed 映射为 error —— lib/client.js:90-100；statusLabel 把五个状态映射到 status.* 文案 —— lib/client.js:101-110；常量 NO_JOBS = [] 与 VIEWPORT_MARGIN = 12 见 :60-62。

### 2.2 组件状态与派生态（含精确行号，均在 lib/client.js）

| 位置 | 内容 |
|---|---|
| :311 | function JobListAction({ sessionId, useJobs, watchRows, observe, killJob, t }) |
| :312 | const jobs = useJobs((state) => state.rows[sessionId]) ?? NO_JOBS; |
| :313 | const observedViews = useJobs((state) => state.observed); |
| :314-319 | open / expandedKey / now / settledOpen / clearedKeys / killPhase 六个 useState |
| :320-323 | rootRef / triggerRef / menuRef 三个 ref 与 menuShift |
| :324 | const rows = useMemo(() => ordered(jobs), [jobs]); |
| :325-326 | 派生态 liveRows（isLive）与 settledRows（非 live 且未被 clearedKeys 清除） |
| :327 | const settledExpanded = settledOpen ?? liveRows.length === 0; ← 折叠默认策略 |
| :328 | const visibleCount = liveRows.length + settledRows.length; |
| :410 | if (visibleCount === 0) return null; ← 无任务时整个控件不渲染 |
| :411 | 触发器文案在「运行中计数」与「空闲计数」两组 key 间切换 |

排序辅助 function ordered(jobs) 见 lib/client.js:160。

### 2.3 折叠策略（三处）

1. **已结束分区**：默认折叠到计数标题之后，条件是「还有存活任务」：settledExpanded = settledOpen ?? liveRows.length === 0 —— lib/client.js:327；即 liveRows 非空且用户未显式点开时，settledExpanded 为 false。这与 README.md:34 的「The settled section folds behind its count while live work exists and can be cleared client-side.」一致。分区标题按钮见 lib/client.js:482-494：aria-expanded 绑定 settledExpanded，点击执行 setSettledOpen(!settledExpanded)，文案为 t("section.settledCount", { count }) 。
2. **单行输出面板**：expandedKey 记录唯一展开行（lib/client.js:315、:429、:431-433），即同时最多展开一个任务。选中行与观测目标：expandedRow 于 :362，activeJob 于 :363。
3. **客户端清空**：clearSettled 把当前 settledRows 的 id 全部塞进 clearedKeys 并清掉相关 expandedKey —— lib/client.js:412-419；clearedKeys 是纯客户端状态，不触碰 roster（:318、:326）。清空按钮渲染于 :495-500，文案 t("section.clear")（zh 为「清空」）。

其它收敛逻辑：弹层关闭时 expandedRow 为 undefined（:362），因此展开行只在弹层打开时有效；可见行变 0 时自动关闭弹层（:372-374）；展开行从 roster 消失时自动清除 expandedKey（:375-377）；已结束分区展开时若该行被清空则收起 expandedKey（:418）。

### 2.4 何时订阅输出（两条独立时机）

- **花名册跟随挂载**：useEffect(() => watchRows(sessionId), [sessionId, watchRows]); —— lib/client.js:330。即组件整个挂载期都保持该 session 的 job.list 流打开。
- **输出观测跟随可见性**：先算出 activeJob（仅当展开行可观测时，:363），再用 useEffect(() => { if (activeJob === undefined) return; return observe(sessionId, activeJob); }, [sessionId, activeJob, observe]); —— lib/client.js:364-371。其清理函数在折叠、卸载或弹层关闭时调用，从而关闭观测流。README.md:48 复述同一契约：「The roster follows the mount: one useEffect keeps the session's job.list stream open while the control lives. Observation follows visibility: another useEffect opens the stream for the expanded row's job and closes it on collapse, unmount, or popover close.」
- **秒级重绘计时器**只在弹层打开且存在存活行时启动，setInterval 每 1000ms 刷新 now，卸载或条件不满足时 clearInterval —— lib/client.js:331-340；now 供存活行时长显示使用（:430）。
- 弹层视口自适应：useLayoutEffect 测量锚点与菜单宽度并设置 menuShift（Math.max(VIEWPORT_MARGIN - anchorLeft, Math.min(0, window.innerWidth - VIEWPORT_MARGIN - width - anchorLeft))），随窗口 resize 重算 —— lib/client.js:341-361，其中 VIEWPORT_MARGIN 定义于 :62。
- 弹层内的键盘退出：onKeyDown 在 Escape 且弹层打开时 preventDefault、setOpen(false) 并把焦点还给 triggerRef —— lib/client.js:420-425。

### 2.5 停止任务如何通知模型（两段式 + 通知账本）

- **两段式 UI**：第一次按下只是武装，三秒内再次按下才真正调用 ctx.jobs.kill；常量 KILL_ARM_MS = 3e3（3000ms，注释「How long an armed kill waits for its confirming press before disarming.」）—— lib/client.js:63-64；失败态保留 KILL_FAILED_MS = 4e3（4000ms，注释「How long a failed kill keeps its hint before the button resets.」）—— :65-66。状态机 pressKill 见 :390-409：未武装则置 { key, state: "armed" }（:392-397）；已武装则置 pending 并调用 killJob(sessionId, key)，返回 false 时置 state: "failed"（:399-408）。
- **超时回落**：killPhase 非 pending 时用 setTimeout 在 armed 3 秒 / failed 4 秒后重置为 undefined —— lib/client.js:378-386。
- **行收敛**：若 roster 中该 job 不再处于 running，立即清除 killPhase —— lib/client.js:387-389。README.md:34 描述该行为「the row converges through the roster stream (stopping, then the settled section, whose detail carries cancelled by the user)」。
- **按钮交互**：data-kill-state 输出状态；disabled 绑定 kill.state === "pending"；armed 与 failed 各自换文案与样式 —— lib/client.js:264-274；停止按钮只对 job.status === "running" 的行下发（:434）。
- **模型通知契约（最关键语义）**：「The kill claims nothing in the model's notice ledger, so the owning agent still receives the standard completion notice — the model is told the user stopped its task rather than left to infer it.」—— README.md:34。即人类停止不吞掉通知：模型仍会收到标准的完成通知，从而得知是用户停的，而不是被留下自己去推断。
- **模型可见性边界**：本包「renders host-observed state and live output for a human and touches no prompt, message, schema, stream, or tool result. The model's own view of the same work stays with dsh-tool-jobs.」—— README.md:72（Model Experience 段起于 :70）。KV Cache 影响为 None：「None; the package never assembles or sends provider requests.」—— README.md:76。
- 已知限制：「Channel labels are not rendered — stdout and stderr chunks concatenate into one stream; per-channel tinting is a presentation follow-up.」—— README.md:84（Known Limitations 段起于 :78）。
- 运行时不变式：「No companion is published. This package is a read-only projection of the ctx.jobs rosters and views onto one header slot entry. It emits no Cordis events, owns no cross-plugin mutable state, and its single slot registration proves disposal through the HMR-safety spec.」—— README.md:96。

### 2.6 slot 注册与依赖注入

- 依赖声明：const inject = ["jobs", "slots", "locale"]; —— lib/client.js:596-600（注释「Required services: the jobs rosters, observations, and kill, the slot registry, and dictionaries.」）。
- 注册体：apply(ctx) 先 ctx.effect(() => ctx.locale.register("job", { zh, en }), "ui-jobs: dictionaries")（:606-609），再 ctx.slots.inject("conversation.session.header.actions", () => ctx.slots.register({ name: "conversation.session.header.actions", id: "job-list", order: 20, locale: "job", inject: () => ({ hooks: { jobs: ctx.jobs.state }, watchRows, observe, killJob }) }, JobListAction)) —— lib/client.js:610-621。killJob 包装为 async (sessionId, jobId) => (await ctx.jobs.kill(sessionId, jobId)).ok —— :619。
- 同一 slot 的其它占用者（全仓静态扫描）：ui-agent-preset、ui-subagent、experimental-client-ui-agent-team。
- 中文文案（zh 为 key 集合的事实源，注释「Simplified Chinese dictionary (the key-set source of truth).」）—— lib/client.js:509-550，其中 count.live.other 为「{count} 个后台任务运行中」、section.live 为「进行中」、section.settledCount 为「已结束 {count}」、section.clear 为「清空」、kill.confirm 为「再次点击确认停止」、kill.confirmAction 为「确认停止」、kill.failed 为「停止失败」、status.killed 为「已取消」、terminal.expand 为「展开其余 {n} 行」。英文同构（注释「English dictionary, key-identical to the Chinese source of truth.」）—— :551-592。

---

## 3. 聊天渲染（Chat）

包：@deepseek-ai/dsh-client-ui-chat（lib/client.js 约 56.5 万字节）。以下条目若无特别说明，行号均指 node_modules/@deepseek-ai/dsh-client-ui-chat/lib/client.js。README 段落位置：Summary 为 :11，Reference previews 为 :34，Hidden Chat rows 为 :43，Command and failure rows 为 :50，Turn token usage 为 :57，Completed-turn footer 为 :68，Turn Process Folding 为 :77，Grouped rendering 为 :88，Scroll ownership 为 :113，Model Experience 为 :152。

### 3.1 过程折叠 / 详细度分级

- **四个详细度档位**是持久化枚举：const TRANSCRIPT_VIEW_MODES = ["compact", "standard", "detailed", "verbose"]; —— :11915-11920。
- 设置命名空间与字段：const CHAT_SETTINGS_NAMESPACE = "ui-chat";（:11911）、const TRANSCRIPT_VIEW_FIELD = "transcriptView";（:11913）。
- 两个历史值被读作 detailed 但不再提供、不再回写：LEGACY_TRANSCRIPT_VIEW_MODE = "normal"（:11925，注释「Saved value from the two-mode generation of this setting. Read as detailed; never offered as a choice and never written back.」）、LEGACY_EXPANDED_TRANSCRIPT_VIEW_MODE = "expanded"（:11927），二者并入 TRANSCRIPT_VIEW_SETTING_VALUES（:11929-11933）；读取映射见 :12089 的 saved === "normal" || saved === "expanded" ? "detailed" : saved ?? this.defaultMode。
- 非桌面 Web 默认档位：const DEFAULT_TRANSCRIPT_VIEW_MODE = "detailed"; —— :11934-11935（注释「Default work details for non-Desktop Web clients.」）。桌面端默认取 standard，见装配处 const transcriptView = new TranscriptViewPolicy(chatSettings, "dshDesktop" in globalThis ? "standard" : DEFAULT_TRANSCRIPT_VIEW_MODE); —— :12357。
- **档位到行为的映射表**（渲染器从不比较枚举本身）：POLICIES —— :12100-12129：
  - compact：foldCompletedTurns 为 true，stepGrouping 为 collapsed，liveProcessDetail 为 false，settledReasoningPreview 为 false
  - standard：foldCompletedTurns 为 true，stepGrouping 为 collapsed，liveProcessDetail 为 true，settledReasoningPreview 为 true
  - detailed：foldCompletedTurns 为 true，stepGrouping 为 history，liveProcessDetail 为 true，settledReasoningPreview 为 true
  - verbose：foldCompletedTurns 为 false，stepGrouping 为 none，liveProcessDetail 为 false，settledReasoningPreview 为 true
- 派生方式：derivePresentationPolicy(mode) 返回只做查表、并把订阅直接委托给 mode 的 observable —— :12136-12141；理由注释：「Renderers and seats select single fields of this policy; none of them compares the mode enum, so adding a mode changes only the table below.」—— :12095-12099。
- **设置行 UI**：TranscriptViewRow 用 PreferenceRow 渲染四档选择器 —— :12032-12047；标签映射 const LABELS 见 :12021-12026；PreferenceRow 在发布新选择前先把焦点还原到触发器（selectorRef.current?.focus({ preventScroll: true })）—— :11980-11983，与 README.md:65 的「Preference menus restore focus to their trigger without scrolling before publishing a new selection.」一致。
- **README 层面的折叠语义**：「Work-details modes control process-group display and reasoning previews. Compact, Standard, and Detailed fold eligible completed Turns without hiding the final answer; Verbose retains the duration/status header without a collapse action and shows historical process rows directly.」—— README.md:83。Summary 补充「Work-details modes control reasoning previews and process visibility without hiding final answers; Verbose keeps completed-turn process rows visible.」—— README.md:13。
- 每个分组持有自己的本地 useDisclosure 状态，模式切换时保留（组件保持挂载）：「Each group owns local useDisclosure state that survives mode changes while its component stays mounted.」—— README.md:104；当外层 Turn 确实隐藏了某个过程成员时，座位会重置这些 disclosure，但不替换组件 key、不更换 Hook 引用 —— README.md:106。
- 过程行在所有 work-details 模式下共用一套文字与图标颜色：静止为 tertiary、hover 为 secondary，错误与警告保留语义色 —— README.md:108。
- **另一条独立的详细度轴**：性能与用量。const PERFORMANCE_USAGE_MODES = ["compact", "detailed"];（:11937）、const DEFAULT_PERFORMANCE_USAGE = "detailed";（:11938，注释「Preserve detailed accounting for users without an explicit preference.」）、设置项 performanceUsage（:11943，Schema.union(...).default(DEFAULT_PERFORMANCE_USAGE)）、行组件 PerformanceUsageRow（:12183-12199）。README.md:61 说明该偏好存为 ui-chat.performanceUsage，compact 只在输入框下显示可用输出速度与缓存命中率、不提供交互式统计对话框与逐 Turn 用量。

### 3.2 文件引用与预览（行号导航、重复地址复用、随源刷新）

**Chat 侧委托（把点击变成地址与参数）**

- Chat 在节点列表外包一层 MarkdownDelegateProvider，统一供给文件与 HTTP(S) 导航：MarkdownDelegateProvider 收到 openExternalLink、openFile（即 requestOpenFile）、fileImages，其 children 是 ChatNodeList —— lib/client.js:5280-5303。README.md:36 对应句：「Chat supplies file and HTTP(S) navigation through one MarkdownDelegateProvider around its node list.」
- 会话作用域注入体里的 openFile：取 ctx.sessions.list 中该 sessionId 的 cwd，用 fileAddressFor(sessionId, cwd, path) 构造 url；options?.line === undefined 时调用 ctx.sidebarRight.openResource(url)，否则调用 ctx.sidebarRight.openResource(url, { params: { line: options.line } }) —— lib/client.js:12423-12429。即**行号通过 params.line 传递**。
- 外部链接：当 linkOpening 快照为 "sidebar" 且 ctx.get("sidebarRightTabs")?.get("browser") 存在时调用 ctx.sidebarRight.openTab("browser", { params: { url } })，否则 window.open(url, "_blank", "noopener,noreferrer") —— lib/client.js:12435-12438。默认值来自设置 linkOpening，即 Schema.union(["sidebar", "new-tab"]).default("sidebar") —— lib/client.js:11942。
- 技能引用：openSkill 走 ctx.get("inputTriggers")?.sessionOf(scope).openReference("skill", { ref: "/" + name }) —— lib/client.js:12430-12434。

**地址语法（重复地址复用与去重的根）**

- 前缀常量：const FILE_ADDRESS_PREFIX = "dsh-resource://file/"; —— lib/client.js:43（注释「The scheme and type every file address opens with.」）。
- encodeSegment 保留冒号字面量（盘符）：encodeURIComponent(segment).replace(/%3A/gi, ":") —— lib/client.js:45-47；encodePath 按段编码 —— :49-51。
- sessionFileAddress(sessionId, path) 产出 dsh-resource://file/session/ + sessionId + / + path；反斜杠归一为正斜杠，去除前导 ./ 前缀 —— lib/client.js:58-61。
- fileAddressFor(sessionId, cwd, path)：相对路径、或落在会话工作区内（含相等）的绝对路径 → session 作用域地址；工作区外的绝对路径，或工作区根未知 → 保留绝对路径的本会话地址 —— lib/client.js:100-107（文档注释 :90-99）。

**预览侧消费（包 @deepseek-ai/dsh-client-ui-sidebar-documentpreview）**

- 注册的类型：id 为 @deepseek-ai/dsh-client-ui-sidebar-documentpreview，kind 为 text，pattern 为 dsh-resource://file/**，band 为 fallback；canOpen 只接受 Session 地址（其路径可相对可绝对），裸 absolute 地址不被认领；**整个地址就是内容身份**，所以不同目录同名文件、或同一路径在两个 session 下等于两个 tab —— README.md:31。
- 行号导航契约：「ctx.sidebarRight.openResource(address, { params: { line } }) carries a 1-based source line through the file parameters. In text-pages mode, the owner loads sequential pages until that line or EOF. Plain-text and code renderers expose source-line anchors; Markdown does not. A navigation remains pending while its selected renderer has no anchor and runs if the user switches to plain text or code. Code navigation scrolls the inner source viewport directly. Byte-mode renderers do not consume source-line navigation. Each completed navigation revision is answered once. Opening the same file without revealIfOpened: false focuses its existing tab and delivers a new revision.」—— README.md:124。
- **重复地址复用（两个层次）**：Sidebar 层「a resource tab already showing the same (kind, contentId) is focused wherever it sits unless revealIfOpened: false」—— sidebar-right/README.md:93；Chat README 复述用户可见效果「#L24 and #L24-L30 navigate to the first specified line and reuse an existing file tab.」—— ui-chat/README.md:36。
- 地址不进布局状态：sidebar-right/README.md:74（「Navigation parameters, resource contents and live connections are not layout state.」）与 :93（navigation 记录在布局历史之外）。
- **随源刷新**：预览主体持有 session 作用域、按 tab id 分桶的共享加载与视图状态，包含累计页或完整字节、已读与已观测版本、待处理的 Resource 变更、自动刷新状态、加载与失败状态、渲染器选择、滚动偏移、换行、以及已应答的导航 revision —— README.md:33。「Automatic refresh defaults to enabled; its separate toggle is hidden, with state, labels, styles, and toggle logic retained.」—— README.md:32。「Automatic refresh uses the same callbacks after a ResourceGroup member changes. Each member's first metadata establishes a baseline without triggering reload or first-read version reconciliation; later changes received during a read remain pending for another refresh. Reads neither refresh shared metadata nor clear another tab's notice.」—— README.md:58。「Reloads and loading-mode changes retire older requests; the tab's abort signal forgets its state.」—— README.md:33。
- 同一地址的元数据在所有 UI 间共享：「Metadata for the same complete address is shared by every UI, including Global components.」—— README.md:42。
- 文档预览支持的行号座位范围：纯文本与代码渲染器暴露源码行锚点，Markdown 不暴露 —— README.md:124（同上）。
- 发送的文件引用与技能也打开在右栏；文件路径使用被查看 Session，技能名经其当前 input-trigger 源解析；会话、目录与命令标签保持不可导航 —— ui-chat/README.md:40。

**滚动位置（会话切换的保留项）**

- 滚动位置由 Chat 自己用模块级 Map 存：const chatScrollPositions = new Map(); —— lib/client.js:12327；注入体给出 chatScroll.save（position 为 null 时 chatScrollPositions.delete(sessionId)，否则 set）与 chatScroll.read（返回该 session 或 null）—— :12444-12450。
- 语义锚点恢复：「Chat restores semantic anchors across history prepend and renderer remounts, with browser scroll anchoring disabled on its scrollport only while following the tail.」—— ui-chat/README.md:115。
- 外层 transcript 跟随与每个打开分组的跟随互相独立，四种组合的行为表见 README.md:123-128。
- 轨道显示阈值按可用宽度而非视口宽度：「The rail hides when the transcript's available width, excluding its horizontal padding, is at most 900px; the browser viewport width is not the criterion.」—— README.md:117。
- 阅读状态的实现拆分（README 折叠段内）：useScrollFollow 提供共享底部阈值、跟随意图与原生滚动三个独立控制器；useProcessScroll 负责分组观测、初始放置与边缘渐隐；useChatViewport 负责 turn-aware 的 DOM 读取、受限写入、原生事件与一个保留中的分页锚点；useChatReading 负责跟随策略、采样读者输入与语义记忆；useChatNavigation 负责 turn 跳转与向 viewport 请求位置保留；useChatScroll 协调它们已提交的输入 —— README.md:139-143。

### 3.3 两条容易混淆的边界

- 会话内右侧面板（ui-sidebar-right）与左侧会话列表（ui-sidebar）是两个包、两套 slot；左侧列表的注册 slot 是 sidebar 与 shell.leading（见 §4.3 扫描结果），会话行插槽是 sidebar.session.row.leading、sidebar.session.row.hover、sidebar.workspaces.session.row.action。
- Chat 视角节点通过 keyed slot conversation.chat.node 注入；Chat 声明处为 lib/client.js:12391-12407：name 为 conversation.view，id 为 chat，order 为 0，children 为 conversation.chat.node（kind keyed、scope session、inject CHAT_NODE_INJECT）与 conversation.message.images（kind single、scope session），store 为 chatStore。README.md:90 说明其分组渲染走 uiConversation.groups，React 通过稳定的 Group 与 Node 座位渲染混合的 node/group 根序列。

---

## 4. 客户端插件 slot 机制

### 4.1 slot 的语义

包 @deepseek-ai/dsh-client-ui-slots 没有浏览器半边（目录下只有 lib/index.js，无 lib/client.js）。

- 定位：「Slot registry pure core for the dsh web client: ordinary extension slots, reusable Component Factories, derived props types, store seats, and the renderer install contract.」—— node_modules/@deepseek-ai/dsh-client-ui-slots/README.md:2。
- 两种 API 覆盖组合场景：普通 Slot 提供父级拥有的扩展位，Component Factory 提供由调用方选择局部 Component 的可复用装配 —— README.md:12；四种 kind 覆盖组合形态，其中 single 表示唯一占用者 —— README.md:28。
- **普通 Slot 的核心断言**：「The ordinary Slot design is one table: declaration = render authorization = runtime spec. SlotMap is declared empty here and merged by consumers via declare module augmentation, exactly like SlotFactoryMap and the standard-kit interface」—— README.md:56。
- **声明即授权**：「Declaring a slot is claiming it: the registering entry becomes the only entry allowed to render that key, and registering into an undeclared slot, declaring an already-declared child, mounting one shared handle under two scopes, or register…」—— README.md:46。
- chain 选择器按 priority 升序执行（同优先级按注册顺序），第一个非 null 返回者当选 —— README.md:60。
- store seat：register 调用可通过 store: defineStore(...) 声明一个 store seat，init 推断 state schema，actions 是完整的 draft-transform 写集，组件经 selector hook 读、经烘焙好的回调写 —— README.md:40-42。
- 渲染契约：「renderer.ts carries the installation contract (SlotRenderer, SlotRendererHost) plus StaleAuthorizationError/SlotOwnershipError; ui-renderer owns both the implementation and its plugin-lifecycle installation.」—— README.md:64。
- 每个注册组件收到的 props 由五份框架 share 组合而成：runtime share（父级渲染调用点的 owner，加 session 标准套件与 global seat）、child-render share（renderSlot 静态纳）等 —— README.md:38。
- Component Factory：「Use a Component Factory when one package defines an assembly that unrelated parents render independently. Declare its complete type in SlotFactoryMap, install the definition with ctx.slots.registerFactory(), render occurrences through t…」—— README.md:32；「Factory children remain ordinary global Slots and must match SlotMap, while local slots select one Component per occurrence. An occurrence inherits its render-position scope; renderFactorySlot() does not accept a Session identity.」—— README.md:34。
- SlotCore 在构造时种下先验的 root slot 并在加载期做校验 —— README.md:60。
- 依赖关系：本包是零依赖纯注册核心，渲染器与事件桥在 ui-renderer —— README.md:64、:75、:111。
- **未核实**：四 kind 与 SlotMap / SlotFactoryMap 的权威设计文档位于源码树 .agents/notes/... 下，该目录不在发布产物中。

### 4.2 客户端 bundle 如何构建与加载

包 @deepseek-ai/dsh-client-modules（两侧都有：lib/index.js 41,704 字节、lib/client.js 40,277 字节、lib/invariant.js 1,615 字节）。README 段落位置：Use this package 为 :26，Declaring a client plugin 为 :32，What the browser loads 为 :36，Live plugin composition 为 :40，Sharing modules 为 :44，Build requirements 为 :48，Understand the implementation 为 :55，Design concept 为 :62，Lazy-CJS model 为 :66，Incremental composition 为 :70，Boot manifest injection 为 :76，Entry ownership 为 :82，Source map 为 :86。

- **声明**：「A browser plugin package declares dsh.client in its package.json with platform: 'web', exports a ./client bundle, and lists any non-baseline module requests under dsh.client.external. The host half turns each declaration into a served bundle under /plugins, ordered so dynamic providers load before their consumers.」—— README.md:34。
- **声明类型与校验**：声明类型用 DshClientManifest，client-modules 校验 JSON 并持有规范化后的 boot 图 —— README.md:28。
- **加载模型（Lazy-CJS）**：「Executing a plugin bundle only registers its factory; every module-body side effect (CSS injection included) lives in the factory closure and runs at materialization (factory(require) → exports, memoized in loadCache).」—— README.md:68。解析顺序为「平台种子表 → 已 memo 的记录 → boot 图行 → 已注册工厂」，其余一律抛错（同处）。
- **动态分包**：「A source import() split by tsdown compiles to require.async(./client.<name>.js); its versioned sibling script arrives only when that expression runs.」—— README.md:38。本仓库实证是 documentpreview 的 lib/client.pdf.js（7,108,786 字节）与 lib/client.excel.js（7,060,788 字节），对应说明「The PDF body loads its package-local client.pdf.js chunk only when a PDF preview mounts; PDF.js, its Worker source, and embedded support data stay out of the startup client.js.」—— ui-sidebar-documentpreview/README.md:66。
- **共享模块表**：「The shell seeds a frozen module table (PLATFORM_MODULES: React, Cordis, and static UI libraries); every dynamic bundle resolves its externals against exactly that baseline. … Composition rejects malformed requests, missing suppliers, self-requests, and synchronous request cycles.」—— README.md:46。
- **bundle 路由与组合**：Node 半边按包增量扫描（无全量重扫路径）；combo route key 形如 /plugins/??...&rev=...，其中一份 bootstrap combo 给 modules 行，其余为 application combo；每个 URL 超过 3 KiB 前就切分；脚本体在首次 GET 时拼接一次并以 source-map 引用结尾；HEAD 不物化任何内容体 —— README.md:72-74（Incremental composition 段起于 :70）。
- **revision 派生**：「Initial publication and HMR derive per-plugin revisions from the entry's mtimeMs, ctimeMs, and size, without hashing artifact contents.」—— README.md:74；因此「Unchanged artifacts therefore retain their revisions across Host restarts, so SSE reconnection does not replace their browser plugins.」—— 同处。
- **boot 注入**：宿主向 head 注入 window.__ModuleLoader__ 队列门面、所有 application combo 的建议式 preload、解析阻塞的 bootstrap combo 脚本，然后才是 boot 图；boot 图为注入的 WebBootEntry 行，形式是 window.__DSH_BOOT__，其中小于号被转义以防插件可控字符串突破 script 元素 —— README.md:80 与 :64（Design concept 段 :62 内）。
- **失败与重试**：「A combo whose script fails to load is requested once more; a combo that loads without registering a row is never re-executed … In both cases each still-missing row then loads its own one-resource combo URL, so one failed batch costs at most three requests per missing row and leaves the rows it did register untouched.」—— README.md:38。
- **热更新**：「HMR switches one changed row to its revisioned one-resource combo URL.」—— README.md:38；「Enabling an ordinary plugin adds its Loader entry; disabling it removes the entry and waits for its asynchronous effects before evicting unused modules and styles.」—— README.md:42。
- **源码地图表格**（「| File | Role |」）：src/index.ts 为 Node 半边（ClientModuleRegistry、扫描、产物快照、可选 combo 路由、结构化 index 行）；src/client/index.ts 为浏览器半边（bootstrap 导出、ctx.modules 注册）；src/client/system.ts 为 ClientModuleSystem（load/materialize/invalidate）；src/client/entries.ts 为页面条目 reconcile、重试与代码替换；src/client/entry-lifecycle.ts 为 Loader fiber 拆除；src/client/manifest.ts 为 wire 类型、boot manifest 解析与 dsh.client 声明解析 —— README.md:88-95。这些路径来自 README 表格，对应 src/ 文件本身不在发布产物中：**未核实**。
- 相关包 dsh-client-hmr 的机制说明段落位置：Use this package 起于 README.md:26、Starting the reload chain 为 :30、What a reload does 为 :34、Configuration 为 :38、Observing success 为 :46、Understand the implementation 为 :53、Design concept 为 :60、The browser swap 为 :64、Cascade and self-reload 为 :68、Failure policy 为 :72、Source map 为 :76。

### 4.3 全量 slot 清单（本机实测）

口径：对 node_modules/@deepseek-ai/ 下所有 dsh-client-* 与 dsh-experimental-client-* 包的 lib/*.js，静态匹配字面量 slots.register({ name: "..."。**这是静态扫描的下界**：动态拼接名、registerFactory、以及通过 slots.inject 建立的父子等待关系均不计入。

共 **76** 个 slot 名，按 slot 名（← 贡献包）列出：

**框架 / 壳层**
- root ← ui-layout
- main ← ui-conversation、ui-plugin-manager、ui-schedule
- shell.leading ← ui-sidebar
- shell.overlay ← ui-chat、ui-plugin-manager、ui-schedule、ui-settings-account、ui-settings-session-log、ui-shortcuts、ui-workspace
- shell.quota-notice ← ui-settings-account

**左侧栏 / 会话列表**
- sidebar ← ui-sidebar
- sidebar.brand.mark、sidebar.brand.name ← ui-brand-official
- sidebar.footer.action ← ui-cordis
- sidebar.panellist ← ui-plugin-manager、ui-schedule
- sidebar.toggle.badge ← ui-settings-general
- sidebar.workspaces、sidebar.workspaces.session.menu.item、sidebar.workspaces.session.row.action ← ui-workspace
- sidebar.session.row.leading、sidebar.session.row.hover ← ui-schedule
- sidebar.workspaces.directoryFlow ← ui-directory-picker-browse、ui-directory-picker-native

**右侧资源面板**
- rightbar、rightbar.session ← ui-sidebar-right
- sidebar.right.pane.tab ← ui-deliverables、ui-plan、ui-schedule、ui-sidebar-browser、ui-sidebar-documentpreview、ui-sidebar-files、ui-sidebar-right、ui-sidebar-terminal、ui-subagent
- sidebar.right.pane.tab.title ← ui-plan、ui-schedule、ui-sidebar-browser、ui-sidebar-documentpreview、ui-sidebar-files、ui-sidebar-right、ui-sidebar-terminal
- sidebar.right.tab.guide.entry ← ui-sidebar-terminal
- sidebar.right.tab.files.actions ← ui-open-in-app
- sidebar.right.tab.document、sidebar.right.tab.document.action、sidebar.right.tab.document.office.pdf ← ui-sidebar-documentpreview
- sidebar.right.tab.document.actions、sidebar.right.tab.document.unpreviewable ← ui-open-in-app

**会话 / 输入区**
- conversation.view ← ui-chat、ui-trajectory
- conversation.chat.node ← ui-chat、ui-goal、ui-tool、ui-user-questions、ui-workflow-run
- conversation.chat.turnTail ← ui-deliverables、ui-plan、ui-schedule
- conversation.chat.assistant-actions ← ui-message-feedback
- conversation.session、conversation.header、conversation.session.header、conversation.composer.bar、main.conversation ← ui-conversation
- conversation.session.header.actions ← ui-agent-preset、ui-jobs、ui-subagent、experimental-client-ui-agent-team
- conversation.session.header.utilities ← ui-open-in-app、ui-schedule
- conversation.session.header.corner ← ui-sidebar-right
- conversation.session.header.lineage ← ui-subagent
- conversation.composer ← ui-approval、ui-subagent、ui-user-questions
- conversation.composer.dock ← ui-chat
- conversation.approval.detail ← ui-chat
- conversation.input.attachments ← ui-attachment
- conversation.input.overlay ← ui-commands、ui-input-trigger、ui-message-feedback
- conversation.input.dock ← ui-conversation、ui-goal
- conversation.input.model ← ui-model-selection
- conversation.input.permission ← ui-permission-presets
- conversation.input.plan、conversation.plan-review.actions ← ui-plan
- conversation.input.activity ← experimental-client-ui-voice-input
- conversation.message.images、conversation.trajectory.images、tool.call.images ← ui-attachment

**首页 / 工作区 / 预设**
- conversation.hero.agentPreset ← ui-agent-preset
- conversation.hero.workspace ← ui-workspace
- conversation.hero.workspace.directoryFlow ← ui-directory-picker-browse、ui-directory-picker-native

**工具视图 / 交付物**
- tool.call.toolview ← ui-cordis、ui-deliverables、ui-skill、ui-tool
- deliverables.file.actions、deliverables.review.file.actions ← ui-open-in-app

**设置**
- settings.section ← ui-agent-preset、ui-settings-account、ui-settings-general、ui-settings-models、ui-settings-plugins
- settings.general.item ← ui-locale、ui-chat、ui-conversation、ui-permission-presets、ui-settings-general、ui-settings-session-log、ui-shortcuts、ui-theme
- settings.trigger、settings.header、settings.action、settings.close ← ui-settings-general
- settings.models.sign-in、settings.launcher ← ui-settings-account
- settings.onboarding ← ui-settings-models
- settings.plugins.tab ← ui-settings-plugin-inventory
- plugins.item ← ui-settings-agent-loop、ui-settings-shell、ui-settings-subagent、ui-settings-web-search
- plugins.bundle.config、plugins.bundle.activation ← experimental-client-ui-voice-input
- sidebar.settings ← ui-settings-general

**子槽约定**：槽名用点号分层，父级用 children 显式声明子槽（例：Chat 在 conversation.view 里声明 conversation.chat.node（kind keyed、scope session）与 conversation.message.images（kind single、scope session）—— ui-chat/lib/client.js:12397-12407）；子槽需等待父级出现，所以注册方用 ctx.slots.inject("<parent>", () => ctx.slots.register(...))（Jobs 用法见 ui-jobs/lib/client.js:610；sidebar-right 的 guide 用法见该包 lib/client.js:9200）。

### 4.4 另一条装配线：Web 端静态资源与页面入口

- 包 @deepseek-ai/dsh-host-frontend-static（README 段落：Summary 为 :10、Use this package 为 :26、Minimal configuration 为 :30、What the server enforces 为 :40、Observable failures 为 :48、Understand the implementation 为 :55、Design concept 为 :60、The traversal fence 为 :64、Source map 为 :68）。
- 本会话运行时给出的约束「apps/web 的 Vite 入口只构建外壳、不是独立应用，因为只有 dsh web 会注入 window.__DSH_BOOT__」与 dsh-client-modules 的 boot 注入契约一致 —— dsh-client-modules/README.md:80。
- **未核实**：发布产物中不存在 apps/web 目录，也没有 docs/subsystems/web-client.md（本次在 app.asar 内只找到 dsh、lib/welcome、renderer/assets、node_modules 四棵子树）。因此「apps/web 结构」与官方 docs/subsystems/web-client.md 的内容无法核对。

---

## 5. 未核实项汇总

1. **src/ 源码行号**：所有包只发布 lib/index.js、lib/client.js、lib/types/**/*.d.ts（files 字段见各包 package.json）。README 中引用的 src/client/JobListAction.tsx、src/client/conversation-nodes/README.md#display-modes、src/client/index.ts 等路径在产物中不存在，其行号未核实。
2. **.agents/notes/... 设计文档**：README 多处链接（如 .agents/notes/implemented/feature/2026-08-26-human-job-kill.md、.agents/notes/implemented/architecture/2026-07-22-slot-type-chain-implementation.md）在产物中不存在，未核实。
3. **docs/subsystems/web-client.md、docs/config-catalog.md、apps/web**：产物中不存在，未核实。
4. **lib/client.js 与源码的对应关系**：产物是 tsdown 打包结果（含 region 注释与内联 sourceMappingURL），本次未校验 sourcemap 内容，「构建产物行号 ↔ 源文件行号」的映射未核实。
5. **本机不存在可写的 DSH 源码检出**（D:\\DeepSeek\\dsh 为空），无法用 pnpm / rg 交叉验证。
6. **工具限制**：read / glob / grep 在 app.asar 路径上不可用、pwsh 不可用（详见文首取证限制）。本文行号由 run_code 内 Node fs 与正则程序化计数得出，并在落笔前逐条回读校验。
7. ui-sidebar（左侧会话列表）与 ui-conversation（会话外壳）的内部实现细节未展开核实，本文只列出它们贡献的 slot 名。
8. 槽名清单是静态扫描下界：registerFactory、动态拼接的 slot 名、以及通过 slots.inject 建立的父子等待关系未计入 76 这个数字。
9. **.tsx 组件的 props/hook 细节**：README 提到的 useTabInfo() 返回字段、useDisclosure 重置绑定等运行时行为的源码实现位置未核实（只有 README 陈述）。
