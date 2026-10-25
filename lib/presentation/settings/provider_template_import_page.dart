import '../widgets/nexus_page_header.dart';
import '../widgets/nexus_page_layout.dart';
import '../widgets/nexus_disclosure.dart';
import '../theme/desktop_theme.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

import '../../domain/provider_template.dart';

/// Importing only prepares a draft. The existing provider editor remains the
/// sole place to enter a secret, test the connection and explicitly save it.
class ProviderTemplateImportPage extends StatefulWidget {
  const ProviderTemplateImportPage({super.key});
  @override
  State<ProviderTemplateImportPage> createState() =>
      _ProviderTemplateImportPageState();
}

class _ProviderTemplateImportPageState
    extends State<ProviderTemplateImportPage> {
  final _input = TextEditingController();
  ProviderTemplate? _template;
  String? _error;
  bool _confirmed = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  late final DeviceCapabilityProfile _capability =
      DeviceCapabilityProfile.evaluate(
    cpuCores: Platform.numberOfProcessors,
    estimatedRamGb: Platform.numberOfProcessors >= 8 ? 8 : 4,
  );

  void _applyRecommendedDraft() {
    final recommended = _capability.buildRecommendedTemplate();
    final pretty =
        const JsonEncoder.withIndent('  ').convert(recommended.toJson());
    setState(() {
      _input.text = pretty;
      _template = recommended;
      _error = null;
      _confirmed = false;
    });
  }

  void _inspect() {
    try {
      final template = ProviderTemplate.parseQrOrJson(_input.text);
      setState(() {
        _template = template;
        _error = null;
        _confirmed = false;
      });
    } on FormatException catch (error) {
      setState(() {
        _template = null;
        _error = error.message;
        _confirmed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final template = _template;
    return Scaffold(
      appBar: const NexusPageHeader(title: '导入配置模板'),
      body: NexusPageLayout(
          child: SafeArea(
              child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
              '仅导入不含密钥的 JSON 模板或 nexus-provider:// 二维码载荷。模板来源未经验证，请核对数据接收方。解析不会联网，也不会保存或激活服务商。'),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('provider-template-input'),
            controller: _input,
            minLines: 6,
            maxLines: 12,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
                labelText: 'JSON 模板',
                errorText: _error,
                errorMaxLines: 4,
                border: const OutlineInputBorder()),
            onChanged: (_) => setState(() {
              _template = null;
              _confirmed = false;
              _error = null;
            }),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _inspect, child: const Text('解析并预览')),
          const SizedBox(height: 12),
          TextButton.icon(
            key: const ValueKey('provider-template-recommend'),
            onPressed: _applyRecommendedDraft,
            icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
            label: const Text('使用推荐模板草稿'),
          ),
          NexusDisclosure(
            title: const Text('推荐依据'),
            child: Text(
              '${_capability.recommendedTier.label} · CPU ${_capability.cpuCores} 核心\n'
              '建议上下文 ${_capability.recommendedContextTokens} tokens\n${_capability.hostingDecision}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          if (template != null) ...[
            Text(template.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            SelectableText(
                '数据接收方：${template.baseUrl}\n协议：${template.protocol}\n模型：${template.model}\n上下文预算：${template.contextTokens}'),
            const SizedBox(height: 8),
            const Text('模型能力尚未检测。继续后请在本机输入 Key，并手动测试连接；连接测试不代表图片或工具能力已经验证。'),
            if (template.isLoopback)
              const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                      '注意：localhost/回环地址指运行此应用的手机，不是你的电脑。电脑上的模型请填写手机可访问的局域网地址。')),
            if (template.baseUrl.scheme == 'http')
              const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('该端点使用明文 HTTP，局域网流量可能被读取；不要在不可信网络传输敏感内容。')),
            Material(
              color: Colors.transparent,
              child: CheckboxListTile(
                key: const ValueKey('provider-template-consent'),
                contentPadding: EdgeInsets.zero,
                value: _confirmed,
                title: const Text('我已核对地址，允许继续配置此数据接收方'),
                onChanged: (value) =>
                    setState(() => _confirmed = value ?? false),
              ),
            ),
            FilledButton(
              key: const ValueKey('provider-template-continue'),
              onPressed:
                  _confirmed ? () => Navigator.of(context).pop(template) : null,
              child: const Text('继续配置（不自动联网）'),
            ),
          ],
          const SizedBox(height: 20),
          if (DesktopTheme.maybeOf(context) == null)
            const NexusDisclosure(
              title: Text('模板格式示例'),
              headerPadding: EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('示例地址不是已连接服务：'),
                  SizedBox(height: 8),
                  SelectableText(
                      '{\n  "schemaVersion": 1,\n  "name": "我的服务商",\n  "baseUrl": "https://example.com/v1",\n  "model": "your-model",\n  "protocol": "openaiCompatible"\n}'),
                ],
              ),
            )
          else ...[
            const Text('模板格式示例（示例地址不是已连接服务）：'),
            const SelectableText(
                '{\n  "schemaVersion": 1,\n  "name": "我的服务商",\n  "baseUrl": "https://example.com/v1",\n  "model": "your-model",\n  "protocol": "openaiCompatible"\n}'),
          ],
        ],
      ))),
    );
  }
}
