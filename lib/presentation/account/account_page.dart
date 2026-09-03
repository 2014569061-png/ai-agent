import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/account_services.dart';
import '../../application/billing_api.dart';
import '../../application/providers.dart';

/// 账号页：注册/登录、会话状态、设备管理、2FA、注销（§4.4）。
class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});
  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _isLogin = true;

  @override
  void dispose() {
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    final api = ref.read(billingApiProvider);
    final account = ref.read(accountServiceProvider);
    final entitlement = ref.read(entitlementServiceProvider);
    try {
      if (_isLogin) {
        final result = await api.login(
          email: _email.text.trim().isEmpty ? null : _email.text.trim(),
          phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          password: _password.text,
          code: _code.text.trim().isEmpty ? null : _code.text.trim(),
        );
        final session = result.session;
        if (session == null) {
          setState(() => _error = '需要 TOTP 二次校验码');
          return;
        }
        await account.saveSession(session);
        // 登录后端会签发托管 Key，写入后即 Pro、可走内置额度。
        if (session.apiKey.isNotEmpty) {
          await entitlement.grantManagedKey(session.apiKey);
        }
      } else {
        final session = await api.register(
          email: _email.text.trim().isEmpty ? null : _email.text.trim(),
          phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          password: _password.text,
        );
        await account.saveSession(session);
        await entitlement.grantManagedKey(session.apiKey);
      }
      if (mounted) setState(() { _busy = false; });
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.toString(); });
    }
  }

  Future<void> _logout() async {
    await ref.read(accountServiceProvider).clearSession();
    await ref.read(entitlementServiceProvider).revoke();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isPro = ref.watch(isProProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('账号与登录')),
      body: isPro.when(
        data: (pro) => pro ? _signedIn() : _signInForm(),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _signInForm(),
      ),
    );
  }

  Widget _signInForm() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('登录')),
            ButtonSegment(value: false, label: Text('注册')),
          ],
          selected: {_isLogin},
          onSelectionChanged: (s) => setState(() => _isLogin = s.first),
        ),
        const SizedBox(height: 16),
        TextField(controller: _email, decoration: const InputDecoration(labelText: '邮箱', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _phone, decoration: const InputDecoration(labelText: '手机号（可选）', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: '密码（≥6位）', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _code, decoration: const InputDecoration(labelText: 'TOTP 二次校验码（如已开启2FA）', border: OutlineInputBorder())),
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(_isLogin ? '登录' : '注册并获取托管 Key')),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 12),
        const Text('注册即自动获得托管 Key，成为 Pro 用户；请求经 NEXUS 中转，仅用于计费不存储对话。', style: TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _signedIn() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const ListTile(leading: Icon(Icons.verified_user), title: Text('Pro 会员'), subtitle: Text('已启用内置额度（托管 Key）')),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('退出登录'),
          onTap: _logout,
        ),
      ],
    );
  }
}
