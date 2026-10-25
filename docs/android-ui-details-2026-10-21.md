# Android UI 细节收尾

2026-10-21。保持已确认的蓝白风格，按真实页面修整组件细节。

- 知识库、插件的空页面仅保留居中的主要按钮；有内容、加载或错误时仍保留原有创建/导入入口。保留粘贴文本与文件导入的不同能力。
- 两处列表预留底部 104dp，避免悬浮按钮遮住末项；手机页侧边距统一 20dp。
- 搜索框独立监听文本控制器，键入、清空、外部筛选变化时及时更新清空按钮，保留输入焦点和编辑状态。
- 设置分隔线与新版 40dp 图标后的文字起点对齐，默认起点 68dp、末端 16dp、细线 .7dp；显式设置与桌面默认值保留。
- 状态标签支持长文字省略与完整提示，可点击标签至少预留 48dp 点击区域。
- 对话输入区的长模型名可通过长按提示查看完整名称；焦点过渡遵循减少/关闭动画设置。
- 任务空页面改为自然的操作引导，已读与处理完成的区别继续保留在列表说明中。

静态检查通过，8 个相关测试文件共 60 项检查通过。新增回归检查验证搜索框无需父页面刷新、焦点和编辑状态保留，以及窄标签在大字体下可点击、不溢出。

模拟器因 const 分隔线字段类型调整执行了一次热重启，确认 `[preview] Restart complete.`，随后复查知识库、插件、设置与实际搜索状态。未新增文档、插件或模型请求。

日志：`local/temp/ui-detail-analyze.log`、`local/temp/ui-detail-tests.log`。

## 模拟器截图

- [知识库调整前](design-previews/android-details-2026-10-21/knowledge-before.png) / [调整后](design-previews/android-details-2026-10-21/knowledge-after.png)
- [插件调整前](design-previews/android-details-2026-10-21/plugins-before.png) / [调整后](design-previews/android-details-2026-10-21/plugins-after.png)
- [设置调整前](design-previews/android-details-2026-10-21/settings-before.png) / [调整后](design-previews/android-details-2026-10-21/settings-after.png)
- [输入搜索词](design-previews/android-details-2026-10-21/search-editing.png) / [清空搜索](design-previews/android-details-2026-10-21/search-cleared.png)
