# 模型与服务商设置页 UI 审计（2026-09-26）

范围：`provider_list_page.dart`（模型提供商）、`provider_detail_page.dart`（服务商配置）、`model_list_page.dart`（模型列表）。
截图：`artifacts/ui-shots/providers_shots_test.dart`（393 宽 @2x 长截图，动效关闭）。示例数据：3 个已配置服务商（DeepSeek 激活、Claude、本地 Ollama 无 Key），详情页含展开的高级参数，模型页为 OpenAI 预设且未填 Key（不请求网络）。
三个页面和 `settings_components.dart` 都没有 WIP 改动，且改前均为 formatter-clean。

截图伪影：详情页底部两个按钮文字显示为方块（按钮样式未指定字体族），真机正常。

## 问题

| 编号 | 页面 | 问题 |
| --- | --- | --- |
| P1 | 服务商配置 | 「基础配置」卡片上内边距只有 12，第一个输入框的浮动标签「服务商名称 *」被卡片顶部裁掉一半 |
| P2 | 模型提供商 | 内置预设的副标题显示内部枚举名 `openaiCompatible`、`gemini` |
| P3 | 模型提供商 | 已配置行副标题是「模型 · Key 状态」，模型名长时（Claude）Key 状态被省略号吃掉 |
| P4 | 模型提供商 | 首字母方块三套样式：激活为品牌蓝，未激活为浅灰，预设为深灰实心白字（浅色模式下很重）；「新增」卡两个图标一灰一琥珀色 |
| P5 | 模型列表 | 搜索框是描边方框，与设置页 T2、历史页 V3 的无描边胶囊不一致 |
| P6 | 模型列表 | 每个未选中模型都挂「可用」徽标（`isAvailable` 恒为 true，没有信息量）；「添加自定义模型」用成功绿图标；「从远端自动获取」的箭头硬编码浅色主题灰；上下文标签显示原始数字 |
| P7 | 全部 | `SettingsGroupCard` 圆角 12，设置主页、历史、任务等已改页面为 16 |

## 方案（顺序 Q1→Q6）

- Q1：「基础配置」卡片上内边距改为 20，浮动标签完整显示。（P1）
- Q2：预设副标题改用中文协议名（OpenAI 兼容 / Anthropic / Gemini，与详情页下拉框一致）；已配置行副标题改为「Key 状态 · 模型」，截断只影响模型名。（P2、P3）
- Q3：首字母方块统一为浅填充 + 主题文字色，只有激活项用品牌色；「新增」卡两个图标统一为中性灰。（P4）
- Q4：模型搜索框改为与设置页 T2 相同的无描边浅底胶囊，聚焦时品牌色细描边。（P5）
- Q5：去掉恒为「可用」的徽标（选中项的「默认」徽标保留）；自定义模型图标改中性；箭头改用主题次要色；上下文显示为「128K 上下文」。（P6）
- Q6：`SettingsGroupCard` 圆角改为 16。影响所有使用该组件的设置子页，属于有意统一；不改 `SectionCard`。（P7）

不改：保存 / 测试连接 / 删除 / 激活 / 远端拉取等逻辑，表单校验和未保存提示。

## 交付（2026-09-26）

分支 `feat/harmony-motion`，未推送。每项都只格式化改动的文件，并跑过 analyze、设置相关测试（ui_refactor_regression / settings_page / wired_pages_smoke）和截图对比。全部完成后跑了一次全量测试（1537 通过，含新增 2 个）和快速 APK 构建（通过）。

| 项 | 提交 | 内容 | 解决 |
| --- | --- | --- | --- |
| Q1 | 12a0dc6 | 基础配置卡内容区顶部加 8 的留白。只加卡片内边距无效：玻璃卡片在内边距以内裁切，浮动标签画在输入框上方，会被裁掉 | P1 |
| Q2+Q3 | fe8e66c | 预设副标题改用 `providerProtocolLabel`（OpenAI 兼容 / Anthropic / Gemini / 代理）；已配置行改为「Key 状态 · 模型」；首字母方块统一为 `_ProviderMonogram`（浅填充 + 主题文字色，激活项品牌色）；「新增」卡图标统一中性灰，标题改为「新增 OpenAI 兼容服务」，副标题缩成一行 | P2、P3、P4 |
| Q4+Q5 | 587cbdd | 模型搜索框改为 T2 同款胶囊；删除恒为「可用」的徽标和 `_DisplayModel.isAvailable`；自定义模型图标、远端获取箭头改用主题次要色，云图标改描边款；上下文用 `formatContextTokens` 显示为 128K / 1M；新增 `test/provider_settings_labels_test.dart` | P5、P6 |
| Q6 | 2ba6309 | `SettingsGroupCard` 圆角改为 `kSettingsCardRadius`（16），13 个设置子页一起生效；`SectionCard` 未改 | P7 |

对比截图：`artifacts/ui-shots/pv_*_{light,dark}.png`（改后），截图测试可随时重跑。

需真机确认：服务商配置页底部两个按钮的文字（截图里是字体伪影）；其它设置子页圆角变为 16 后，是否有卡片内部元素贴边。
