import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// 聊天输入区上方的 Provider 配置引导。
///
/// 关闭只作用于当前 ChatPage 实例；只要 Provider 仍未配置，重新进入聊天页
/// 会再次显示。配置成功后由父级的 [providerConfigured] 条件移除该组件。
class ProviderSetupHint extends StatefulWidget {
  const ProviderSetupHint({
    super.key,
    required this.onConfigure,
    this.onDismiss,
  });

  final Future<void> Function() onConfigure;
  final VoidCallback? onDismiss;

  @override
  State<ProviderSetupHint> createState() => _ProviderSetupHintState();
}

class _ProviderSetupHintState extends State<ProviderSetupHint> {
  bool _dismissed = false;
  bool _configuring = false;

  Future<void> _configure() async {
    if (_configuring) return;
    setState(() => _configuring = true);
    try {
      await widget.onConfigure();
    } finally {
      if (mounted) setState(() => _configuring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleStyle = theme.textTheme.labelLarge?.copyWith(
      color: scheme.onSurface,
      fontWeight: FontWeight.w600,
    );
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.25,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Semantics(
        container: true,
        label: '尚未配置模型服务',
        child: Material(
          color: scheme.primaryContainer.withValues(alpha: .48),
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTokens.radiusControl),
              border: Border.all(
                color: scheme.primary.withValues(alpha: .22),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 20,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('还没有配置模型服务', style: titleStyle),
                      const SizedBox(height: 2),
                      Text(
                        '配置 API Key 或连接本地模型后即可发送消息',
                        style: subtitleStyle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton.tonal(
                  onPressed: _configuring ? null : _configure,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.padded,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: _configuring
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('去配置'),
                ),
                Semantics(
                  button: true,
                  label: '关闭模型配置引导',
                  child: IconButton(
                    tooltip: '关闭模型配置引导',
                    onPressed: () {
                      setState(() => _dismissed = true);
                      widget.onDismiss?.call();
                    },
                    icon: const Icon(Icons.close_rounded, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
