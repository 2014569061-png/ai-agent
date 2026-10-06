# 动效改造 · 阶段 2：HarmonyOS 动效调研

> 调研日期：2026-09-24（联网）。**只借鉴设计思路和公开的数值规范**；不使用华为图标、HarmonyOS Sans / 鸿蒙黑体、HarmonyOS Symbol、视频素材或 ArkUI 代码。
> 标注：【官方】= developer.huawei.com 原文；【社区】= 第三方文章转述，可信度较低；【推断】= 本文根据原则推导出的 Flutter 参数，不是官方数值。

## 1. 来源

| # | 来源 | 类型 | 要点 |
| --- | --- | --- | --- |
| S1 | [动效 · 设计原则](https://developer.huawei.com/consumer/cn/doc/design-guides/animation-design-principles-0000001750237392) | 官方 | 自然流畅、简洁高效、快速响应、运动一致 |
| S2 | [动效 · 动效属性](https://developer.huawei.com/consumer/cn/doc/design-guides/animation-attributes-0000001797117229) | 官方 | 时长分级、贝塞尔曲线、弹性曲线参数 |
| S3 | [动效 · 转场动效](https://developer.huawei.com/consumer/cn/doc/design-guides/transition-animation-0000001750078488) | 官方 | 层级关系、运动编排、一镜到底、淡入淡出 |
| S4 | [动效 · 手势动效](https://developer.huawei.com/consumer/cn/doc/design-guides/gesture-animation-0000001797038213) | 官方 | 按下即响应、滑动继承手速、过界阻尼 |
| S5 | [视觉风格 · 沉浸光感](https://developer.huawei.com/consumer/cn/doc/design-guides/immersivelight-0000002612101053) | 官方（2026-06） | 光设计语言、三档强度、5 级材质 |
| S6 | [沉浸光感功耗优化](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-constraints) | 官方（2026-09） | 面积、嵌套、动态内容、阴影等功耗规则 |
| S7 | [HarmonyOS 7 新能力](https://developer.huawei.com/consumer/cn/features/) | 官方 | 光随指动、光线勾勒、非线性形变 |
| S8 | [@ohos.curves 转述](https://www.seaxiang.com/blog/pgx9ty) | 社区 | springMotion / responsiveSpringMotion 默认值 |
| S9 | [合理使用页面间转场](https://www.cnblogs.com/strengthen/p/18499935) | 社区（转述官方最佳实践） | 转场场景 → 动效映射表 |
| S10 | [ArkUI 动画性能 / 粒子](https://zhuanlan.zhihu.com/p/32226766729) | 社区 | 粒子动画维度、renderGroup |
| S11 | [HarmonyOS 7 粒子动效支持清单](https://weibo.com/2/detail/5342692629283794) | 社区 | 算力不足的机型暂不支持粒子（光感仍支持），说明需要分级降级 |

## 2. 设计原则（S1）

1. **自然流畅**：帧率稳定、响应及时、跟手是基本要求。
2. **简洁高效**：运动的元素越少越好，缩短路径。
3. **快速响应**：长距离 ≤ 350ms、短距离 ≤ 250ms、较短动画 ≤ 150ms。
4. **运动一致**：同一类运动路径一致，引导视觉焦点。

## 3. 参数

### 3.1 时长（S1、S2）

| 场景 | 官方数值 | 本项目现值 | 结论 |
| --- | --- | --- | --- |
| 颜色类简单动画 | 100ms | instant 100 | 一致 |
| 小范围（开关图标） | 150ms | fast 150 | 一致 |
| 局部（删除一条列表） | 200ms | base 220 | 基本一致 |
| 全屏（打开图片） | 350ms | page 250 / exit 180 | 偏短但仍在范围内，可以保持 |
| 旋转等复杂动画 | 300ms | expand 300 | 一致 |
| 60fps 单帧 | 16.67ms | — | 120Hz 下单帧 8.33ms |

### 3.2 曲线（S2）

| 类型 | 官方值 | 用途 |
| --- | --- | --- |
| 标准曲线 | cubic-bezier(0.40, 0.00, 0.20, 1.00) | 起止都在视线内的同屏变化 |
| 减速曲线 | cubic-bezier(0.00, 0.00, 0.20, 1.00)（与项目一致） | 进场 |
| 其他列出的曲线 | cubic-bezier(0.20, 0.00, 0.10, 1.00)、(0.33, 0.00, 0.67, 1.00) | 页面原文列出，但每条曲线的具体归类**需在官方页面上核对【不确定】** |
| 弹性（interpolatingSpring） | stiffness 128, damping 12, mass 1, velocity 0 ≈ springMotion(response 0.555, dampingFraction 0.53) | 带弹性特征的对象 |
| springMotion 默认 | response 0.55s, dampingFraction 0.825（S8 社区） | 离手动画 |
| responsiveSpringMotion 默认 | response 0.15s, dampingFraction 0.86, overlap 0.25s（S8 社区） | 跟手动画 |

弹性曲线的特点（S2）：可以在任意时刻打断，打断后时长自然衔接；能继承手速；时长由物理参数自动计算。适用于跟手对象和列表滚动、翻页、上滑退出。

**Flutter 换算【推断】**：`SpringDescription.withDampingRatio(mass: 1, stiffness: (2π/response)², ratio: dampingFraction)`。
- 离手 springMotion(0.55, 0.825) → stiffness ≈ 130.5，ratio 0.825
- 跟手 (0.15, 0.86) → stiffness ≈ 1755，ratio 0.86
- 轻弹性 (0.555, 0.53) → stiffness ≈ 128，damping = 2·0.53·√128 ≈ 12，与官方 interpolatingSpring 数值吻合，说明换算公式正确

### 3.3 转场（S3、S9）

- 转场动效占系统全部动效的 60% 以上。先确定**层级关系**：同层级（编辑、页签）/ 上下层级（父子页、新建、搜索）/ 跨层级（跨应用）。
- 运动编排把元素分成四类：**进场、出场、持续、静止**。
- **一镜到底**（重点推荐）：共享元素、共享容器（补间尺寸/圆角）、共享动势（位移/缩放/旋转）。
- **淡入淡出**：单向（只动前景）、交叉（样式差异大时错开时机）。
- 映射表（S9 社区转述）：层级转场 / 列表展开 / 新建 → **左右位移遮罩**；单体卡片展开 / 非固定搜索框 → 一镜到底；编辑 → 淡入淡出；通用 → 缩放。**不要单帧切换，也不要上下位移切换；曲线优先用弹簧。**

### 3.4 手势（S4）

- **点击**：按下接触平均持续 100~130ms，**必须在按下瞬间给出反馈**（项目的 `NexusPressable` 已符合）。
- **滑动**：分跟手、离手瞬间、离手后三段；离手时继承手速。
- **拖拽过界**：用显控比（阻尼）；标题区与内容区用不同阻尼联动，产生层次感。

### 3.5 沉浸光感（S5、S7）

- 光是「塑造空间、传递反馈、引导注意力」的语言；界面像具有光学扩散的介质，背板如薄雾悬浮在内容之上。
- 三档强度：**强**（叠加粒子流转、空间光效）/ **均衡（默认）**（环境光沿边缘柔和流转）/ **弱**（高对比、收敛光彩）。
- 5 级材质：ULTRA_THIN（顶部悬浮 + 渐变模糊）、THIN（底部悬浮 + 渐变蒙层）、THICK（非常驻浮层）、ULTRA_THICK（半模态/弹窗）。**项目已有 `SurfaceLevel { ultraThin … ultraThick }`，思路一致。**
- HarmonyOS 7 新增：光随指动、光线勾勒、非线性形变（S7）。

### 3.6 粒子（S10、S11）

- 粒子动画可在颜色、透明度、大小、速度、加速度、自旋等维度变化，用来营造氛围（S10）。
- HarmonyOS 7 对算力不足的机型**关闭粒子、保留光感**（S11）。本方案的降级顺序照此制定：先关粒子，再简化光晕，最后关模糊。

### 3.7 功耗与降级（S6，Flutter 同样适用）

1. 光感/材质属于「稀缺资源」，要控制面积和层数。
2. **不要嵌套材质**；材质已含模糊时不再叠加模糊。
3. **不要把材质放在视频、动图、动画等动态内容上方**：背景一变就要重新采样。对应到 Flutter：`BackdropFilter` 下面不能放粒子。
4. 参数与子树要保持稳定，不要用定时器频繁改材质参数。
5. 不重复叠加阴影。
6. 弹窗不要接近全屏尺寸。

## 4. 对本项目的结论

| 维度 | 现状 | 差距 |
| --- | --- | --- |
| 时长/曲线 Token | 已按 HarmonyOS 对齐 | 缺弹簧 Token（跟手/离手/轻弹）；`curveAccelerate` 命名有误 |
| 转场 | 左右微位移 | 缺透明度层次和「遮罩」感；两处未统一 |
| 手势 | 按下即缩放 | 缺光随指动、离手弹簧 |
| 光感 | 液态玻璃 + 5 级 Surface | 缺边缘光流转、光线勾勒 |
| 粒子 | 无 | 需要分级、可关闭、避开玻璃区域 |
| 减少动效 | 系统 + App 三档 | 已完善，新动效直接接入即可 |

## 5. 搜索关键词（便于复核）

`HarmonyOS 动效属性 时长 曲线`、`HarmonyOS 转场动效 一镜到底`、`HarmonyOS 手势动效 跟手 离手`、`沉浸光感 功耗优化`、`curves.springMotion response dampingFraction`、`ArkUI Particle 粒子动画`、`HarmonyOS 应用UX体验标准 转场动效时长下限`

【不确定】「应用 UX 体验标准」中「转场动效时长下限」的具体数值没有抓取到官方原文，实现时统一以 S1 的上限为准，下限按 ≥ 150ms 处理（推断）。
