import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infrastructure/sync/sync_service.dart';
import '../widgets/floating_toast.dart';
import '../widgets/immersive_sheet.dart';
import '../widgets/section_card.dart';

/// 云同步（D1，Pro 卖点）：恢复码生成/导入 + 加密同步说明。
/// 后端未上线时入口置灰提示「需 NEXUS 账号服务」。
class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});

  @override
  ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage> {
  Future<void> _generateRecoveryCode() async {
    final password = await _askPassword('设置同步口令（恢复码口令）');
    if (password == null || !mounted) return;
    final code =
        await ref.read(syncServiceProvider).exportRecoveryCode(password);
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    FloatingToast.show(context, '恢复码已复制，请妥善保存（跨设备同步用）');
  }

  Future<void> _importRecoveryCode() async {
    final code = await _askPassword('粘贴恢复码');
    if (code == null || !mounted) return;
    final ok = await ref.read(syncServiceProvider).importRecoveryCode(code);
    if (!mounted) return;
    FloatingToast.show(context, ok ? '恢复码已导入，密钥已派生' : '恢复码格式无效');
  }

  Future<String?> _askPassword(String title) async {
    final controller = TextEditingController();
    final result = await showImmersiveDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: '内容')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('确定')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('云同步')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SectionCard(
          child: ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('生成恢复码'),
            subtitle: const Text('口令派生密钥（scrypt/PBKDF2），服务端只存密文'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _generateRecoveryCode,
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: ListTile(
            leading: const Icon(Icons.sync_alt),
            title: const Text('导入恢复码'),
            subtitle: const Text('在另一台设备输入恢复码以同步'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _importRecoveryCode,
          ),
        ),
        const SizedBox(height: 16),
        const SectionCard(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('云同步暂不可用'),
            subtitle: Text('需 NEXUS 账号服务（v0.3 托管后端）。当前仅提供本地加密密钥派生与恢复码能力。'),
          ),
        ),
        const SizedBox(height: 8),
        Text('同步后端地址：${sync.isConfigured ? '已配置' : '未配置'}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF627D98))),
      ]),
    );
  }
}
