# 桌面改版复核与快捷方式交付

复核日期：2026-10-09。主要桌面改版已经落到源码，已生成并检查新版 Windows Release；本记录更新交接文档中尚未验证的状态。

## 本轮补齐

- 修复两倍文字下侧栏品牌标题溢出；空间不足时隐藏 DESKTOP 辅助标签，保留品牌和导航。
- 修复截图测试的等待卡死，采用隔离的会话、数据库和设备数据，不发送模型请求；正确应用文字缩放，检查各场景布局异常，加载真实中文及等宽字体，并等待主题过渡结束。
- 颜色门槛保留 103，字号门槛保留 223，时长门槛保留 35。颜色统计排除集中定义语义颜色的 DesktopTheme；提示等待时间改用现有 AppTokens.durationExpand。

## 验证结果

- 最终 Flutter analyze：无问题，日志 artifacts/desktop/review-final-analyze.log。
- 全量回归首次运行：1840 项通过，唯一失败为主题新增后的质量门槛统计。修正后质量门槛和渲染测试两项复测通过，日志 artifacts/desktop/review-final-ui-tests.log。没有重跑全量测试并声称一次全绿。
- 源码覆盖率 65.61%，高于 55% 门槛；未记录意图的静默异常为 0；git diff --check 通过。
- 10 个截图场景通过：深浅主题首页和聊天、1280×800、900×640、1.5/2.0 倍文字、设置和设备弹窗。截图位于 artifacts/desktop/desktop-*.png，使用明确隔离的测试数据。
- 最终 Windows Release 构建成功。从最终 ZIP 解压启动，窗口响应正常；144 DPI 下最小逻辑客户区 900×640；正常关闭退出码 0。日志 artifacts/desktop/review-native-smoke.log。
- 独立程序目录全部 75 个文件与 Release 目录逐一校验哈希一致。

## 程序与快捷方式

- 桌面快捷方式：C:/Users/HJIE/Desktop/NEXUS Agent.lnk
- 程序：D:/AIIIIII/ai-agent/mobile_agent/dist/windows/NEXUS-Agent/mobile_agent.exe
- 快捷方式的工作目录为完整程序目录，并使用程序图标。保留该目录中的 DLL 和 data 文件夹。
- 发布包：dist/windows/nexus-agent-0.9.0-95-windows-x64.zip
- SHA-256：31388243ca5204a56f19e5ab1ad5b1db5680896fd9d6e2bfae94263e042d35c2

尚未连接 Android 真机，投屏和手机控制没有完成端到端验收；截图中的设备属于测试数据。本机启动检查没有发送模型请求，不代表真实账号和模型连通性已验收。本轮没有提交或推送代码。
