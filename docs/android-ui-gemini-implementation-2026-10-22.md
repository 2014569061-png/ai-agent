# NEXUS Android UI 精修实施任务书

交接对象：Gemini 编程代理。版本：2026-10-22。

工作区：`D:\AIIIIII\ai-agent\mobile_agent`。本文件交付的是可执行任务与验收要求；文件中的待办不表示已经实施。

## 1. 任务目标与执行范围

在现有 Flutter Android 应用上完成全页面 UI 精修：继续采用蓝白、柔光、实色圆角分组和左侧抽屉导航，重点减少首屏噪声、重复入口、过大占位、说明堆积与样式差异。

用户期望：打开应用可以立即开始对话；需要时容易找到任务、项目和工具；每页清楚呈现当前内容、一个主要动作和需要处理的状态。

本任务覆盖 57 个 Android 页面源文件、额外的 `RunDetailPage` 入口、公共组件、导航、聊天状态及主要弹层。下方有完整清单。保留现有全部真实能力和可达入口。

交接前已完成设计审查，未按本任务书实施新一轮精修。审查中 58 个入口各生成普通字体、窄屏大字体截图，共 116 张；当时 118 项相关测试通过。该结果仅是历史基线，执行者必须重新检查当前代码和验证结果。

先阅读：

1. 项目根目录 [AGENTS.md](../AGENTS.md)。
2. [持续视觉规范](android-ui-style.md)。
3. 本任务书。
4. [逐页审查与问题依据](android-ui-review-2026-10-22.md)。

用户后续明确指令优先；本任务书将审查中的可选建议收敛成以下具体实施方案，不要求再次进行风格探索。

### 必须遵守的边界

- 工作区有大量未提交改动。先检查 `git status --short`，记录本次接手基线。按文件和代码块增量修改，禁止 `reset/clean/checkout` 覆盖其他工作，禁止整目录格式化或无关重构。
- 主改动位于 `lib/presentation/`，配套修改相关 UI 测试和设计规范。保留 controller、provider、路由参数、数据库结构、工具协议和权限决策的语义。发现业务缺陷时记录，不通过假数据或删入口掩盖。
- Android 与 Windows 分支独立。不能强制 Android 进入桌面布局；不能把手机的字号、留白、抽屉和圆角直接应用到桌面分支。
- 保留左侧抽屉，不恢复底部导航栏。手机首页底部只保留输入区与必要状态。
- 不增加账号、会员、云同步、实时通话或未实现的自动化；不制作“精选市场”假内容；不虚构模型能力、进度、完成状态或测试结果。
- 不更换图标库、字体库或引入新 UI 框架；先复用现有组件与代码绘制图形。无须为本任务下载图片或依赖。
- 不修改用户实际服务商密钥，不向模型发送真实请求，不为截图执行删除、恢复、安装系统软件等操作。复杂状态用隔离样例与既有测试验证。
- 不擅自提交、推送、发布或构建正式发布包。本地 Android 调试预览和必要检查属于任务范围。

## 2. 固定设计规格

### 2.1 颜色与表面

| 项目 | 实施值 / 规则 |
| --- | --- |
| 普通页面背景 | `#F7F9FC`，接近实色；减弱普通页面的蓝色渐变 |
| 内容表面 | `#FFFFFF`，不透明，无厚阴影 |
| 主操作 | `#0A59F7` |
| 选中背景 | `#EAF2FF` |
| 主文字 / 次文字 | `#182230` / `#667085` |
| 分割 | 复用 `colorScheme.outlineVariant`，约 0.7dp，低对比 |
| 柔光 | 仅首页欢迎区、输入区域或少量面板；不铺在所有普通页面上 |
| 状态色 | 成功、警告、危险沿用真实语义，同时给文字/图标；不全部改成蓝色 |
| 深色 | 使用既有深色语义色；保留层级，不把上面的浅色常量硬写进深色分支 |

从 `Theme.of(context).colorScheme` 或 `AppTheme.semanticOf(context)` 读取颜色。不要逐页复制一套常量。

### 2.2 字体、几何与密度

| 项目 | 实施规则 |
| --- | --- |
| 一级页标题 | 默认 28sp / 500；不再使用过重的 30sp 大标题 |
| 二级页标题 | 21sp / 500 |
| 欢迎语 | 26sp / 400 |
| 正文 | 15–16sp，行高约 1.5–1.6 |
| 次级说明 | 13sp / 400；时间、简短元数据可 12sp，不承载关键授权说明 |
| 副标题 | 12–13sp / 400；仅补充必要信息，不重复页面标题与功能宣传 |
| 页边距 | 20dp；已有组件自带外边距时不能再叠加 |
| 间距 | 4 / 8 / 12 / 16 / 24 / 32dp |
| 分组表面 / 字段 / 按钮 | 默认圆角 24 / 18 / 16dp；避免逐页再出现 8、12、14 等独立普通卡片规范 |
| 聊天输入 / 底部面板 | 圆角 26 / 28dp |
| 图标 | 普通线性图标 20–22dp，同层级视觉重量一致；不为每个图标都加彩色方块 |
| 点击范围 | 不小于 48×48dp；视觉图标可以较小 |
| 列表行 | 约 56–64dp 的常规密度，随内容和字体自然增高，禁止强行固定高度裁字 |
| 动效 | 约 180–260ms，尊重系统减少动态效果；不新增持续装饰动画 |

页头主行采用约 56dp 的基准。需要一级标题时可适度增高，但不能把主标题、副标题和徽标硬塞进固定高度。状态徽标默认移到正文摘要行；修复设备页 `LIVE` 被裁切的问题。

### 2.3 信息层级

- 每页先确定一个主任务和一个主操作。工具栏最多保留两个高频动作，其他动作进入带文字的“更多”。
- 简短说明直接展示；长解释用 `NexusDisclosure` 等明确展开入口承载；技术日志、原始参数、内部 ID 默认折叠。
- 授权对象、费用含义、数据发送范围、覆盖/删除后果和任务结果可信度不能因为简洁而被隐藏。
- 列表按内容分组使用一个表面；同层级不再“卡片套卡片”。正文、日志和代码不必套成独立装饰卡。
- 相同操作在空态、顶部与悬浮按钮中不能重复抢占注意；保留一个明确主入口即可，所有功能仍需可达。
- 文案先用自然中文。协议名、Model ID、命令保留真实原值；主层不直接显示 `success`、`unknown`、内部任务 ID 或堆栈。

## 3. 公共组件改造契约

先读组件调用点，再修改 Android 分支。不要通过全局正则批量替换半径、颜色、文案或路由。

| 文件 / 组件 | 实施任务 | 验收 |
| --- | --- | --- |
| `lib/presentation/theme/mobile_theme.dart`、`widgets/nexus_background.dart`、`widgets/nexus_page_layout.dart` | 统一手机文字层级、普通画布和几何；首页专用柔光仍由首页承担 | 普通页不带明显大面积渐变；深色仍可读；桌面分支保持布局 |
| `widgets/nexus_page_header.dart` | 一级/二级标题、菜单/返回、工具栏与副标题统一；复杂状态放正文 | 菜单和返回按钮视觉对齐；长标题可查看完整值；无第三行徽标裁切；大字体不丢关键状态 |
| `widgets/section_card.dart`、`settings/settings_components.dart` | 统一分组表面、标题、行内边距与分隔线；减少嵌套 | 同类页面边缘对齐；没有双重水平边距；关键说明不被两行省略号截断 |
| `widgets/nexus_list_tile.dart`、`widgets/nexus_search_field.dart` | 自然增高的列表、统一搜索/清空与长名称处理 | 输入和清空即时反映；长名称可展开/查看；48dp 点击目标 |
| `widgets/empty_state_view.dart`、`widgets/async_state_view.dart`、`widgets/nexus_async_content.dart` | 一致的空、加载、局部失败与重试 | 空态位于内容区上半部，不被剩余空间推到底部；小屏可滚动；刷新保留已加载内容 |
| `widgets/nexus_status_badge.dart`、`widgets/nexus_status_pill.dart`、`widgets/nexus_disclosure.dart` | 收敛状态颜色/尺寸与渐进展开规则 | 选中、运行、成功、待核实、部分完成和失败可以区分，含文字/图形 |
| `widgets/nexus_sheet.dart`、`widgets/nexus_action_sheet.dart`、`widgets/confirm_action.dart` | 统一面板标题、安全区、底部动作、键盘与返回 | 单手可操作，面板内容可滚动，键盘不盖按钮，关闭不丢未保存编辑 |

上表为代码定位；若接手时文件已移动，先搜索实际定义，不能新建重复组件。下方清单中省略的公共路径均位于 `lib/presentation/`。

### 空状态统一实现

视觉顺序：40–48dp 图标 → 12dp → 16–18sp 标题 → 8dp → 尽量两行的说明 → 16dp → 可选主操作。

默认放在扣除页头和筛选后的可见内容区上半部，使用可用高度约束与滚动适配；正常手机可从内容顶部约 64–96dp 开始。不要在所有页面硬写同一个大高度，也不要用一个 `Expanded + Center` 让长筛选区把空态持续推下。没有下一步的空页不硬加按钮。

## 4. 高频页面的确定方案

### 4.1 侧栏：主导航、历史与工具分层

定位：`navigation/mobile_shell.dart`、`navigation/mobile_navigation_scope.dart`、`chat/widgets/chat_catalog_drawer.dart`。

实施结构：

1. 顶部小型品牌行与关闭按钮。
2. 一个 48dp 的轻量“新建对话”操作，避免与当前选中目的地同时成为两个大蓝块。
3. 助手、任务、工作区三个紧凑主导航行，约 52dp 起，随大字体增高。
4. 最近会话标题与搜索入口，下面展示会话列表。搜索按需展开，保留现有查询能力与清空入口。
5. 底部固定轻量的“助手与工具”“我的”行；这是抽屉内部的页脚，不是应用底部导航。工具行打开适合手机的分组面板，列出原有 Agent、模型与运行、MCP、提示词、运行与费用、会话与工具等入口。

保留缓存目的地索引与独立 Navigator：助手 0、任务 1、工作区 2、我的 3。“我的”换位置不改变路由与索引语义。

保留 `MobileDrawerBridge` 对聊天原有新建/切换逻辑的委托，以及 `AssistantEntrySurface` 的可见性保护。不能直接另写一套新建会话方法绕过草稿、附件和外部输入保护。

必须保持：切换目的地保留草稿与子页面；返回先关闭侧栏，再返回详情，最后从其他根页面回助手；待处理角标仍读取真实 attention 状态，不能替换为未读数；历史重命名、收藏、置顶、删除全部保留。

### 4.2 首页与输入区

定位：`chat/chat_page.dart`、`chat/widgets/chat_empty_state.dart`、`capsule_top_bar.dart`、`floating_capsule_input.dart`、`widgets/nexus_assistant_emblem.dart`、`widgets/nexus_home_visuals.dart`。

- 顶部只保留菜单、NEXUS/当前身份与新建对话，延续细线图标。
- 欢迎图形默认约 64dp，复用现有绘制实现；图形到欢迎语约 24dp，欢迎语到副文案 8–12dp，到建议约 20dp。欢迎区从工具栏下约 32–64dp 起，自适应内容高度；不硬占一大块固定空间。
- 欢迎语用“今天想一起完成什么？”，副文案一句即可；最多三个真实建议。可优先整理资料、分析项目及有待继续事项时的继续入口；没有对应状态时使用已有真实建议，不能编造任务。
- 创建 Agent 仍在身份/工具管理中可达，不要求作为首页常驻建议。
- 输入区水平边距 20dp，圆角 26dp，轻微描边与阴影；附件通过加号；长模型 ID 限宽单行，完整信息在选择面板可查看；保留多行输入、已有附件、模式与执行入口。
- 未配置模型时只出现一处清楚引导；键盘弹出隐藏欢迎建议，输入框和最近消息保持可见；关闭键盘不丢草稿。
- 用户自定义背景必须继续生效，不能用新画布覆盖它。

### 4.3 对话、执行与审批

定位：`chat/widgets/chat_message_list.dart`、`message_bubble.dart`、`tool_activity_section.dart`、`plan_panel.dart`、`result_card_view.dart` 和聊天执行状态组件。

- 助手长回答优先正文阅读；用户浅蓝气泡；不为每段助手正文重复加头像、大卡片和厚边框。
- 工具默认呈现动作、状态和短结果，例如“读取项目文件 · 已完成”“分析主要模块 · 进行中”；参数和日志展开查看。
- 当前执行状态只保留一个紧凑摘要。暂停、继续、重试、停止随真实状态出现；不要把暂停和停止混用，不改变各按钮原有业务语义。
- 计划确认与风险审批独立突出；默认可见执行对象、影响和允许/拒绝；本次、本会话、永久信任继续明确区分。
- Token、耗时、费用放详情；未知费用继续标记未知；成果有清楚预览/查看/导出入口，不把“已保存”改为“验证通过”。

### 4.4 任务、工作区与我的

- 任务保留待处理、近期任务、收件箱三种语义；优先任务名、状态、更新时间和下一步，不做满屏大型进度卡。开发任务中心作为专业历史与筛选入口，避免变成第二个任务首页。
- 工作区首页：最近项目列表、一个添加入口、较轻的成果中心入口。项目主页保留现有“概览、文件、终端、任务、产物”五个标签和导航行为，本轮不重写成新路由架构；只精简概览重复入口、环境明细和标签。五标签在窄屏能滚动。
- 我的使用统一页头与搜索；未配置服务商缩成一行提示。按模型与助手、工具与设备、个人数据、外观与系统组织；原有入口全部可达。清除凭证和清空数据不能混为同一操作。

## 5. 完整页面待办清单

状态初始均为“待实施”。以下路径相对 `lib/presentation/`；每行都需要进入交付记录，不能只因继承主题就标成已验收。具体问题依据见逐页审查文档。

批次依赖：B0 基线 → B1 公共组件 → B2 高频协作 → B3 工作区 → B4 配置资料 → B5 设备数据 → B6 诊断基础 → B7 全量验收。某批未完成不代表后续页面可省略。

| ID | 批次 | 页面 / 源码 | 必须落地的结果 |
| --- | --- | --- | --- |
| UI-01 | B2 | 助手 `chat/chat_page.dart` | 完成首页、对话、输入、键盘和执行状态精修；保留草稿、附件、会话切换、外部输入与自定义背景 |
| UI-02 | B2 | 历史 `history/history_page.dart` | 搜索范围清楚；统一筛选和时间分组；标题/一行摘要/时间；管理动作进更多 |
| UI-03 | B2 | 全量搜索 `search/global_search_page.dart` | 搜索加筛选入口；结果主层不显示内部 ID、堆栈或完整路径；保留本地查询边界 |
| UI-04 | B2 | 任务 `jobs/jobs_inbox_page.dart` | 真实待处理优先；列表紧凑；空态靠上；未读不当作待处理或完成 |
| UI-05 | B2 | 开发任务 `tasks/development_tasks_page.dart` | 收敛零计数筛选；明确专业任务历史定位；保留完整状态筛选能力 |
| UI-06 | B2 | 任务详情 `tasks/task_details_page.dart` | 结果、需处理动作、改动和验证优先；无输入不做大空卡；完整流水线/审计折叠 |
| UI-07 | B2 | 定时任务 `scheduled/scheduled_tasks_page.dart` | 区分提醒与 Agent 执行；下次时间/开关/上次结果；权限说明就地呈现 |
| UI-08 | B2 | 工作流 `workflows/mobile_workflows_page.dart` | 先选模板再填参数；步骤摘要化；试跑与实际执行区分，保留预览确认 |
| UI-09 | B3 | 工作区 `projects/project_picker_page.dart` | 最近项目一个列表组；添加一个入口；成果中心轻量化 |
| UI-10 | B3 | 项目主页 `projects/project_home_page.dart` | 保留五标签；概览突出继续开发和最近变化；路径/环境/远程明细折叠；统一边距与圆角 |
| UI-11 | B3 | Git `projects/project_git_page.dart` | 中文变化类型、已选文件范围与提交摘要清楚；差异单独查看；原始状态收起 |
| UI-12 | B3 | 变更集 `projects/project_change_set_page.dart` | 任务/时间/文件数/可回退状态；先看差异再回退；空态解释来源 |
| UI-13 | B3 | 远程连接 `projects/remote_execution_page.dart` | 状态、地址、令牌、接收方核对和连接顺序清楚；技术帮助折叠；不加入未实现的同步按钮 |
| UI-14 | B3 | 网页交付 `projects/static_web_delivery_page.dart` | 预览、核对、保存、导出分阶段；缺入口显示可读原因与恢复入口；原始异常折叠 |
| UI-15 | B3 | 会话工作台 `workbench/session_workbench_page.dart` | 明确本次对话的文件与结果；去掉无意义空闲统计；文件/结果可达 |
| UI-16 | B3 | 开发工作台 `workspace/development_workbench_page.dart` | 展示将验证什么和一个开始动作；等待步骤中性色；失败可重试/交给助手；日志折叠 |
| UI-17 | B3 | 编辑器 `workspace/workspace_editor_page.dart` | 文件名、未保存标识、保存优先；跳行/搜索进工具；扩大正文；保留未保存返回保护 |
| UI-18 | B3 | 终端 `terminal/terminal_page.dart` | 保留深色输出；缩小装饰外框；连接状态和恢复清楚；辅助键一行加展开 |
| UI-19 | B3 | 浏览器 `browser/browser_page.dart` | 地址、控制权、接管清楚；权限和错误局部化；网页为主体；保留真实接管边界 |
| UI-20 | B4 | Agent `agents/agents_page.dart` | 一个创建入口分生成/手动；名称、职责、选中态；参数不铺列表 |
| UI-21 | B4 | Agent 编辑 `agents/agent_editor_page.dart` | 基础角色/模型/工具范围首屏；采样、步数、输出等高级项折叠；保存稳定 |
| UI-22 | B4 | 知识库 `knowledge/knowledge_page.dart` | 文档列表和上传优先；启用作用一句说明；保留片段发送给当前服务商的告知 |
| UI-23 | B4 | 记忆 `memory/memory_page.dart` | 统一“长期记忆”命名；事实/分类/更新时间；注入范围与显式读取区别不变 |
| UI-24 | B4 | 上下文 `settings/personal_context_page.dart` | 用人物/项目/文件例子帮助理解；列表简短；冲突、来源、待确认与遗忘明确 |
| UI-25 | B4 | 提示词 `prompts/prompt_library_page.dart` | 中文命名统一；插入输入框为默认操作；设为系统指令独立且说明范围 |
| UI-26 | B4 | 插件 `plugins/plugins_page.dart` | 区分插件与技能；已安装状态和来源优先；不合并底层数据机制 |
| UI-27 | B4 | 技能 `plugins/skill_market_page.dart` | 内置可用技能优先；导入方式集中；无精选内容时收起占位分区 |
| UI-28 | B4 | MCP `mcp/mcp_servers_page.dart` | 名称统一；名称/类型/状态/工具数；先选协议再显字段；保留进程与数据接收方说明 |
| UI-29 | B4 | 成果 `artifacts/artifact_center_page.dart` | 名称/类型/预览/来源优先；保存、核对、缺失分清；长原则说明进详情 |
| UI-30 | B4 | 研究成果 `artifacts/research_artifacts_page.dart` | 结论、来源数、最近核查和证据状态分层；引用与日志展开；不足不隐藏 |
| UI-31 | B2 | 我的 `settings/settings_page.dart` | 统一页头/搜索；配置提示缩小；用途分组；危险操作底部独立 |
| UI-32 | B4 | 服务商 `settings/provider_list_page.dart` | 已配置优先；一个添加入口收纳预设/API/模板；空态可展示少量真实预设 |
| UI-33 | B4 | 服务商详情 `settings/provider_detail_page.dart` | 中文标题、基础字段顺序、测试与保存层级；高级项折叠；失败不清空输入 |
| UI-34 | B4 | 模型 `settings/model_list_page.dart` | 已选与搜索/列表优先；刷新/自定义次级；保留真实 Model ID 和选择行为 |
| UI-35 | B4 | 模板导入 `settings/provider_template_import_page.dart` | 导入、解析、核对、继续配置；硬件建议/JSON 示例收起；不自动保存启用 |
| UI-36 | B4 | 工具权限 `settings/tool_list_page.dart` | 权限摘要与工具列表分层；长授权说明可完整读取；本次/会话/永久不混淆 |
| UI-37 | B4 | 扩展目录 `settings/extensions_page.dart` | 助手能力/工具连接/运行环境/用量诊断四组；去重复副标题；所有入口保留 |
| UI-38 | B5 | 设备能力 `settings/device_capabilities_page.dart` | 移除裁切的 LIVE 页头徽标；可用/未检查/需授权分清；英文技术面板进详情 |
| UI-39 | B5 | 自动化 `settings/device_automation_page.dart` | 规则为主体；触发器问题局部提示；仍为触发后通知、预览确认执行 |
| UI-40 | B5 | 手机资料备份 `settings/device_backups_page.dart` | 与应用数据备份分清；资料类型/备份摘要/恢复范围；不显示原始异常作正文 |
| UI-41 | B5 | Linux 环境 `settings/linux_environment_page.dart` | 当前目标/可用状态/下一步；仅展示目标依赖；完整能力清单和诊断折叠 |
| UI-42 | B5 | 文件设置 `settings/workspace_files_page.dart` | 明确为文件与存储设置；路径/传输/策略/维护分组；安全状态描述具体范围 |
| UI-43 | B5 | 默认助手 `settings/default_assistant_page.dart` | 实际状态和一个设置动作优先；唤起/语音/页面文字帮助折叠；保留锁屏与发送边界 |
| UI-44 | B5 | 系统编辑器 `settings/system_editors_page.dart` | 接收方可用性先行；手机日期选择与精确时区核对；保留系统最终保存流程 |
| UI-45 | B5 | 数据管理 `settings/data_management_page.dart` | 资料目录优先；备份存储单组；减少与诊断自动化目录争夺主层级 |
| UI-46 | B5 | 应用备份 `settings/data_backup_page.dart` | 最近备份/备份/恢复优先；自动备份单组；维护恢复仅必要时强调；清空独立危险区 |
| UI-47 | B5 | 保险箱 `vault/vault_page.dart` | 轻量导入导出；真实包含范围和密钥选项；密码与覆盖后果清楚 |
| UI-48 | B6 | 外观 `settings/appearance_theme_page.dart` | 三主题一组；主要动效偏好简化；强度/诊断收起；聊天背景独立入口 |
| UI-49 | B6 | 语言 `settings/language_page.dart` | 简单选中列表；减少重复解释；不完整翻译状态如实保留 |
| UI-50 | B6 | 首次引导 `onboarding/onboarding_page.dart` | 一个配置模型主操作和先浏览次操作；缩短冗余介绍；权限按使用场景请求 |
| UI-51 | B6 | 反馈 `feedback/feedback_page.dart` | 问题类型/描述/可选联系；仍通过邮件交接时按钮写“打开邮件草稿”，不能假装已提交 |
| UI-52 | B6 | 仪表盘 `dashboard/dashboard_page.dart` | 聚焦用量和近期运行；待处理轻入口；减少重复最近会话和大空卡 |
| UI-53 | B6 | 费用 `dashboard/cost_ledger_page.dart` | 周期、预留/待确认/已结算及汇总优先；空列表无分页；未知与零费用区别保留 |
| UI-54 | B6 | 运行分析 `diagnostics/run_analysis_page.dart` | 本次状态/耗时/用量优先；减少零值卡和多层统计；完整拆分进详情 |
| UI-55 | B6 | 运行详情 `diagnostics/run_analysis_page.dart` 中 `RunDetailPage` | 标题改“运行详情”；结果/耗时/用量/关联任务会话/时间线；低频缺失指标折叠 |
| UI-56 | B6 | 链路指标 `diagnostics/operational_metrics_page.dart` | 周期/环境/有效样本优先；零样本中性呈现；参考目标未配置不显示达标 |
| UI-57 | B6 | 日志 `diagnostics/log_viewer_page.dart` | 筛选加更多；严重程度/摘要/时间；堆栈/ID 进详情；清理有范围确认 |
| UI-58 | B6 | 审计 `audit/audit_log_page.dart` | 普通日志开关边界简短清楚；动作/对象/决策/结果；参数折叠，授权信息可核对 |

## 6. 弹层与状态清单

各批处理关联页面时同步处理相关面板；B7 逐项复核，不能只验收静态首屏。

| ID | 面板 / 定位 | 实施与验收 |
| --- | --- | --- |
| M-01 | `chat/widgets/attachment_drawer_panel.dart` | 附件缩略图/名称/读取状态/删除清楚；拍照、相册、文件轻量分组；关闭和返回不丢草稿 |
| M-02 | `chat/widgets/input_tool_grid_sheet.dart` | 统一图标与低密度布局；消除彩色功能宫格感；与侧栏同名功能去歧义 |
| M-03 | `chat/widgets/model_picker_sheet.dart` | 搜索、当前服务商/模型、列表；模式选择独立分组；大字体仍可操作 |
| M-04 | `chat/widgets/session_configuration_sheet.dart` | 模式/模型/Agent/项目基础组，执行参数次级；不连续堆叠多个面板 |
| M-05 | 计划确认、`tasks/collaboration_plan_sheet.dart` | 目标、步骤、影响、修改/确认清楚；长推理折叠，授权范围保留 |
| M-06 | `chat/widgets/tool_approval_sheet.dart` | 动作/对象/影响/允许拒绝；原始 JSON 折叠；信任范围、失效、后台交接语义不变 |
| M-07 | `settings/device_action_confirm_sheet.dart` | 预览变化与不可逆项；逐项执行结果；覆盖/恢复/Root 等真实后果不可弱化 |
| M-08 | `voice/speech_capture_sheet.dart` | 未开始/听取/识别/可编辑/停止分清；转写为主体；自动发送显式选择，不做通话界面 |
| M-09 | `navigation/assistant_input_review_sheet.dart` | 来源、有效性、可编辑内容、加入草稿；敏感信息提示保留；过期不能继续确认 |
| M-10 | 提示词、记忆、上下文编辑面板 | 标题/必填/保存/未保存返回一致；长正文充分展开；键盘不遮挡 |
| M-11 | 服务商、MCP、配置模板面板 | 协议驱动字段；错误就地；敏感值可控查看；基础与高级分层 |
| M-12 | 备份、导入导出、密码确认 | 展示范围/目的地/覆盖结果；密码错误可修正；不虚构云备份 |
| M-13 | `chat/widgets/environment_sheet.dart`、项目安装任务 | 目标/依赖/进度/下一步；完整日志折叠；不画无真实分母的百分比 |
| M-14 | `workspace/file_tree_sheet.dart`、文件预览 | 当前路径和目录清楚；长名称可查看；复制与引用可达 |
| M-15 | `workspace/terminal_sheet.dart`、`workspace/workspace_sheet_frame.dart` | 与独立终端状态/辅助键一致；安全区/键盘适配；关闭不误终止会话 |
| M-16 | `branches/branch_tree_sheet.dart`、`presets/run_presets_sheet.dart` | 选中状态与切换影响明确；原始配置次级；保留真实预设与分支 |
| M-17 | `chat/widgets/session_metrics_sheet.dart` | 摘要先行，未知/预估/结算清楚；不恢复输入区常驻指标栏 |
| M-18 | `settings/update_sheet.dart`、`projects/install_job_sheet.dart` | 版本/来源/进度/一个主操作；发布说明次级；保留系统授权与真实失败状态 |

统一检查：加载、空数据、有数据、长名称、局部失败、重试、禁用与原因、选中、运行、暂停、审批、完成、部分完成、待核实、过期、冲突、键盘、返回、未保存、大字体、深色和屏幕阅读器。

## 7. 分批执行与停止条件

### B0：建立基线

- 确认实际工作区、当前 AGENTS、文件改动与 Android 路由；核对清单是否因其他工作增加页面。
- 确认已有预览进程与模拟器，不重复启动；保存接手时高频页面截图。
- 运行必要基线检查，记录已有失败；不要把已有失败悄悄算成本次通过。
- 建立 `docs/android-ui-gemini-progress.md`：页面 ID、实施状态、测试证据、实际模拟器截图、未验证项。

### B1：公共组件

先完成第 3 节，用首页、任务列表、设置、一个编辑表单、一个错误状态和设备能力验证不同结构。公共组件通过后继续后续批次，避免逐页复制样式。

### B2–B6：按清单实施

逐页处理结构、层级、状态和交互；每批运行关联检查并截图，确认 Android 实际分支已更新。不要在未读调用点时大改导航或共用状态；不要因为某批通过就跳过其他页面。

### B7：全量验收与交付

- 核对 UI-01 至 UI-58 和 M-01 至 M-18 的实施/验证状态；新增入口同步登记页面清单测试。
- 运行全量页面渲染与相关交互回归；实际检查各主要用户旅程和更改较大的页面。
- 对无法在模拟器验证的原生/ARM64 能力写明限制和未验证事项，不标“全部通过”。
- 更新 `docs/android-ui-style.md` 与必要的 AGENTS 风格条目，保持后续页面沿用同一规则；不覆盖已有协作说明。
- 输出最终变更说明、页面映射、测试结果、截图位置和剩余问题；保持调试预览运行。

通常不需要每批等待用户确认；在既定范围内持续实施。有破坏性数据动作或超出 UI 的重大能力改动时不擅自执行，先完成不依赖它的工作并记录具体原因。

## 8. 检查命令与 Android 预览

以下为 PowerShell，先在工作区根目录运行。单独恢复依赖或执行工具也必须保持缓存与临时文件在工作区内。

```powershell
Set-Location 'D:\AIIIIII\ai-agent\mobile_agent'
$env:PUB_CACHE = Join-Path $PWD 'local/pub-cache'
$env:TEMP = Join-Path $PWD 'local/temp'
$env:TMP = $env:TEMP
$env:GRADLE_USER_HOME = Join-Path $PWD 'local/gradle-cache'
$env:ANDROID_HOME = Join-Path $PWD 'local/android-sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:ANDROID_AVD_HOME = Join-Path $PWD 'local/android-avd'
$env:ANDROID_USER_HOME = Join-Path $PWD 'local/android-user'

git status --short
Get-CimInstance Win32_Process |
  Where-Object { $_.CommandLine -match 'android_preview.dart|flutter_tools.snapshot.+run' } |
  Select-Object ProcessId, CommandLine
./local/android-sdk/platform-tools/adb.exe devices
```

从设备列表读取真实序列号，然后核对 AVD；不要把示例序列号当成固定值：

```powershell
$previewSerial = '<从 adb devices 读取的序列号>'
./local/android-sdk/platform-tools/adb.exe -s $previewSerial emu avd name
```

仅当没有可用预览会话时启动：

```powershell
./tool/run-android-preview.ps1 -Flutter 'C:/src/flutter/bin/flutter.bat'
```

已有调试终端需看到 `[preview] Ready`。保存 UI 后确认 `[preview] Hot reload complete.`；初始化变更用 `R` 热重启，不能只看模拟器窗口还在。保持预览运行。

静态与全页面布局检查：

```powershell
C:/src/flutter/bin/flutter.bat analyze --no-pub
C:/src/flutter/bin/flutter.bat test --no-pub --dart-define=NEXUS_UI_GALLERY=true test/android_ui_inventory_test.dart
```

页面图输出：`local/temp/android-ui-gallery/`。测试覆盖当前普通 411×891、窄屏 360×891 / 1.6 倍文字；它们是测试渲染，不是实际设备截图。

按改动选择相关测试，不机械运行所有历史测试，也不删断言来获得通过：

| 改动范围 | 优先使用的现有测试 |
| --- | --- |
| 导航、首页、会话与键盘 | `mobile_shell_test.dart`、`chat_empty_state_test.dart`、`chat_visual_hierarchy_test.dart`、`chat_state_matrix_test.dart`、`chat_drawer_back_test.dart`、`keyboard_insets_test.dart`、`keyboard_avoider_test.dart` |
| 草稿、附件、外部输入与历史 | `chat_page_attachments_test.dart`、`chat_page_deep_link_regression_test.dart`、`chat_history_selection_test.dart`、`mobile_review_regression_test.dart` |
| 面板、审批 | `input_tool_grid_sheet_test.dart`、`model_picker_sheet_test.dart`、`mcp_sheet_layout_test.dart`、`nexus_sheet_semantics_test.dart`、`device_action_confirm_sheet_test.dart`、`tool_approval_background_test.dart`、`foreground_approval_guard_test.dart` |
| 项目、编辑、浏览器、终端 | `project_home_mobile_compact_test.dart`、`development_workbench_mobile_test.dart`、`workspace_editor_mobile_test.dart`、`browser_page_test.dart`、`terminal_page_test.dart`、`terminal_lifecycle_regression_test.dart`、`terminal_accessory_bar_test.dart` |
| 服务商、模板、费用与诊断 | `provider_settings_labels_test.dart`、`provider_detail_context_auto_test.dart`、`provider_template_import_page_test.dart`、`mobile_cost_ledger_widget_test.dart`、`mobile_operational_metrics_test.dart`、`mobile_ui_detail_test.dart` |

测试路径均以 `test/` 开头。按行为变化更新必要的测试；纯装饰变化不编写镜像实现的无效测试。视觉断言调整必须说明新的合理布局，不能绕过能力与安全语义断言。

Windows 下 `.bat` 可能错误转义包含 `|` 的测试过滤表达式。需要正则筛选时可直接调用 Dart 工具快照，避免管道被 shell 解释：

```powershell
C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe `
  C:/src/flutter/bin/cache/flutter_tools.snapshot test --no-pub `
  test/android_ui_inventory_test.dart --name 'chat/chat_page.dart|jobs/jobs_inbox_page.dart'
```

只格式化本批实际修改的文件，避免 `dart format lib/` 等全目录格式化。

### 实际模拟器截图

```powershell
$evidenceDir = Join-Path $PWD 'docs/design-previews/android-ui-refinement'
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
./local/android-sdk/platform-tools/adb.exe -s $previewSerial shell screencap -p /sdcard/nexus-ui-review.png
./local/android-sdk/platform-tools/adb.exe -s $previewSerial pull /sdcard/nexus-ui-review.png (Join-Path $evidenceDir 'B2-home-after.png')
```

等待实际界面加载和动画稳定后截图，必要时先做一次 UI 层级读取确认页面。文件名必须对应实际页面与状态；不把概念图、上一帧或测试截图标为真实设备验收。不要覆盖已有审查基线图。

## 9. 必须验收的用户旅程

| 旅程 | 完成条件 |
| --- | --- |
| 新会话 → 输入草稿 → 任务 → 返回助手 | 草稿、附件、选中模型保留；没有恢复底部导航 |
| 侧栏 → 工作区详情 → 切其他主入口 → 返回工作区 | 保留子页面与浏览位置；返回先关侧栏再退详情；终端/代码横向手势不被吞掉 |
| 输入 → 键盘 → 附件/工具面板 → 系统返回 | 输入与操作可见；返回逐层关闭；不退出 App 或同时关闭两个层级 |
| 对话执行 → 计划确认 / 审批 → 暂停或继续 → 结果 | 状态与动作真实；授权范围和副作用清楚；详细记录可展开；成果可查看/导出 |
| 无模型 → 添加服务商 → 选择模型 → 测试/保存 | 配置引导单一清晰；测试与保存不混淆；失败不丢输入；真实接收方可核对 |
| 项目 → 文件编辑 → 未保存返回 → Git / 变更 / 交付 | 保存保护存在；选中文件与提交范围准确；预览、保存副本和验证状态分开 |
| 搜索/列表 → 长名称 → 筛选 → 局部失败/重试 | 全名有查看入口；筛选有效；错误局部化；无内容跳动和重复主按钮 |
| 数据备份/恢复、设备操作预览 | 用隔离样例检查界面与确认；范围、覆盖、权限、密钥处理与不可逆项可理解，不能实际覆盖用户数据 |

复杂状态可使用既有样例和测试，不要求为了验收向真实模型付费或操作真实私密数据。ARM64 内置运行时能力不能因 x86 模拟器界面可见就标为已验证。

## 10. 完成判据与交付格式

必须同时满足：

- UI-01 至 UI-58 和 M-01 至 M-18 均有实施结论与证据；未验证、受限、失败明确标记。
- 每页首屏内容、主操作、次入口、默认收起信息可从实际界面确认；没有靠删除能力实现简洁。
- 普通手机、窄屏大字体、长名称、深色、键盘与返回等相关状态无裁切与不可达操作。
- Android 实际显示已更新，共用组件未破坏桌面分支。
- 静态与相关检查通过，或明确列出接手前已有问题及阻塞；测试环境插件报错不冒充真实设备故障，真实故障也不归咎于测试环境而跳过。
- 后续视觉规范已同步，预览可继续使用。

交付记录建议使用以下表格；同页有多种关键状态可拆行：

| 页面/面板 ID | 结构与样式已改 | 交互检查 | 普通/大字体测试 | 实际模拟器页面/状态截图 | 未验证或受限 |
| --- | --- | --- | --- | --- | --- |
| UI-01 | 待实施 | 待验证 | 待验证 | 待补充 | 待说明 |

最终说明需包含：改了什么及原因、全部入口映射、实际执行的检查和结果、截图路径、剩余问题。禁止只写“全部统一了”“所有页面都验收了”而没有逐项记录。

## 11. 可直接复制给 Gemini 的执行提示词

```text
请直接在 D:\AIIIIII\ai-agent\mobile_agent 实施 Android 全页面 UI 精修。

先阅读根目录 AGENTS.md，然后阅读：
1. docs/android-ui-style.md
2. docs/android-ui-gemini-implementation-2026-10-22.md
3. docs/android-ui-review-2026-10-22.md

以实施任务书为工作清单，完成 B0–B7、UI-01–UI-58 和 M-01–M-18。
目标是保留蓝白、柔光、实色圆角与左侧抽屉，减少首屏噪声、重复入口、说明堆积和过大留白；不重新探索视觉风格，不恢复底部导航。

保留所有现有真实能力、入口、草稿、会话状态、审批与数据语义；不要虚构账号、云同步、通话、模型能力或自动化。只改 Android 实际分支，保护桌面布局。工作区有大量既有改动，必须增量修改，不清理或覆盖其他人的工作，不整目录格式化。

先做公共组件，再按批次逐页实施。阶段性更新进展并持续完成任务，无须每批重复请求确认。不要只改主题就宣布完成。保留完整页面清单和逐项证据，说明未验证与受限状态。

复用已有 Android 模拟器和预览；先检查实际设备序列号与调试进程，避免重复启动。确认 Ready 和热重载成功，并检查实际画面。全部下载、缓存、临时文件放工作区 local/。不连接真实收费模型、不执行恢复/清空用户数据等危险操作。复杂状态使用隔离样例和现有测试。

建立 docs/android-ui-gemini-progress.md，持续登记页面/面板 ID、改动、测试、实际截图与限制。最终交付代码、规范更新、入口映射、检查结果、截图与剩余问题。未经要求不要提交、推送或发布，保持调试预览运行。
```
