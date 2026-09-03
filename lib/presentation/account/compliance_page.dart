import 'package:flutter/material.dart';

/// 合规落地页（§8.2 / M3）：用户协议 + 隐私政策。
/// 托管 Key 模式声明"请求经 NEXUS 中转，仅用于计费，不存储对话"。
class CompliancePage extends StatelessWidget {
  const CompliancePage({super.key});
  static const _tos = '用户协议\n\n'
      '1. NEXUS Agent 客户端功能基于本地优先设计。使用"内置额度"（托管 Key）模式时，'
      '你的请求将通过 NEXUS 后端中转至模型服务商，用于身份校验、用量计费与内容合规，'
      '请求内容不做长期存储。\n'
      '2. 不得将服务用于违法用途。我们保留对违规账号限制或封禁的权利。\n'
      '3. 你需自行妥善保管账号凭据；开启二次验证（2FA）可增强账户安全。\n'
      '4. 我们可能按需更新本协议，更新后将在应用内提示。';
  static const _privacy = '隐私政策\n\n'
      '1. 本地数据：对话记录、记忆、知识库等默认仅存储在你的设备上，加密导出由你掌控。\n'
      '2. 匿名统计：为改进产品，我们收集匿名、聚合级的激活/付费漏斗数据，可选关闭，不采集对话内容。\n'
      '3. 托管 Key 中转：请求经 NEXUS 后端计费与合规审核，仅用于保障服务运行，不存储对话正文。\n'
      '4. 账号注销：你可在"账号"页随时注销并删除后端数据。';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('协议与隐私'),
          bottom: const TabBar(tabs: [Tab(text: '用户协议'), Tab(text: '隐私政策')]),
        ),
        body: TabBarView(
          children: [
            _doc(theme, _tos),
            _doc(theme, _privacy),
          ],
        ),
      ),
    );
  }

  Widget _doc(ThemeData theme, String text) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.6)),
    );
  }
}
