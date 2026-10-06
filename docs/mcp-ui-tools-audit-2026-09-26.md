# UI 打磨 · 工具 / 扩展 / 设备组审计（2026-09-26）

范围：`lib/presentation/settings/` 下 tool_list_page、extensions_page、device_capabilities_page、
device_automation_page、linux_environment_page、workspace_files_page。
基线截图：`artifacts/ui-shots/tools_shots_test.dart` → `tl_{tools,ext,caps,auto,linux,ws}_{light,dark}.png`
（自动化页注入假 bridge + 3 条规则 / 2 条执行记录；未注入时 Android 分支停留在骨架屏——测试环境的
未 mock 通道需真实事件循环，非产品问题）。

## 问题清单

| # | 页面 | 问题 | 严重度 |
|---|---|---|---|
| 1 | 全组（+确认 sheet、数据备份） | `AppPalette.success/warning/danger` 作 `iconColor`：浅色保留语义色，深色被 `normalizeIconTint` 降为灰——状态图标在深色下失去含义 | 高 |
| 2 | 工具清单 | 图标按“分类”随意着色（终端、多模态=危险红，计算器=成功绿），与右侧风险徽标重复编码且语义错误；深浅两主题配色不一致 | 中 |
| 3 | 工具清单 | 筛选为描边 ChoiceChip（标签样式未继承主题字体），搜索框为描边方框；与设置/历史/任务页的无描边填充胶囊不一致 | 中 |
| 4 | 设备能力 | 徽标用 `AppPalette.*` 浅色值：深色下琥珀 #9A6700 文字对比度不足 | 中 |
| 5 | 设备能力 | “徽标 + 操作按钮”横排占 ~180px，副标题被挤成几个字（Shizuku：“以 adb（uid 2000）运行：…”）；“当前执行通道”三段信息被截断 | 高 |
| 6 | 设备自动化 | 执行记录“部分成功”用红色错误图标（应为警告）；含 Root 动作的规则闪电图标为危险红 | 低 |
| 7 | Linux / 工作区 | 装饰性琥珀/绿色（默认工作目录、重新初始化、环境检测、导出会话）无语义；实心/描边图标混用 | 低 |
| — | 扩展与环境 | 版式正常，无需改动（文件非 formatter-clean，不动） | — |

## 计划（X 系列，逐项提交）

- **X1** `normalizeIconTint` 识别 AppPalette 浅/深两套语义色并映射到当前主题 → 一处修复全部调用点；新增单测。
- **X2** 工具清单：图标统一中性（风险仅由徽标表达），详情 sheet 头部同步。
- **X3** 工具清单：无描边填充筛选胶囊（W4 样式）+ 胶囊搜索框（T2 样式）。
- **X4** 设备能力：徽标/图标改用 `AppTheme.semanticOf`；徽标与操作按钮纵向堆叠；“当前执行通道”副标题 3 行（SettingsTile 新增 `subtitleMaxLines`，默认 2）。
- **X5** 设备自动化：部分成功 → 警告色图标；需 Root 规则 → 警告色。
- **X6** Linux / 工作区：去掉装饰色，统一描边图标；保留真实语义（就绪状态、危险清理）。

约束：不改逻辑；能力页绝不自动执行 su；只格式化原本 clean 的文件；每项前后双主题截图 + analyze + 相关测试。

## 交付（2026-09-26）

| 项 | 提交 | 文件 | 结果 |
|---|---|---|---|
| X1 | `8e5f152` | settings_components.dart、test/settings_icon_tint_test.dart（+2） | 深色下 AppPalette 语义色图标不再变灰（自动化、能力、Linux、工作区、确认 sheet、数据备份同时受益） |
| X2 | `23ec3dd` | tool_list_page.dart | 工具图标中性化，删除按分类着色；详情 sheet 头部改中性浅底 |
| X3 | `070162f` | tool_list_page.dart、test/settings_page_test.dart | 无描边填充筛选胶囊（Key `tool-filter-<name>`，标签正常渲染）、胶囊搜索框 + 与上方卡片 16px 间距；测试覆盖切换筛选 |
| X4 | `c59feb9` | device_capabilities_page.dart、settings_components.dart | 徽标/图标用主题语义色；徽标与操作纵向堆叠；SettingsTile `subtitleMaxLines`（默认 2）：执行通道 3 行、Shizuku 4 行；未改动 su 触发逻辑 |
| X5 | `4127bea` | device_automation_page.dart | 部分成功 → 警告图标/色；需 Root 规则 → 警告色 |
| X6 | `d6605d7` | linux_environment_page.dart、workspace_files_page.dart（手改，未格式化） | 去掉装饰色、描边图标；状态徽标与危险项改为主题语义色 |

验证：每项 `flutter analyze` 无问题、组内相关测试 + tools 截图 12/12；全量 `flutter test` 1541 通过；
fast ARM64 APK 构建成功（60.7s）。分支 `feat/harmony-motion`，未推送；只提交了本组文件。
遗留（未改）：扩展与环境页（非 formatter-clean，版式无问题）；工作区“最近访问目录”箭头用浅色 muted（影响极小）。
