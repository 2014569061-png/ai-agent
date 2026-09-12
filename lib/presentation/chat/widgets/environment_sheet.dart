import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../infrastructure/update/update_service.dart';
import '../../widgets/nexus_page_header.dart';

/// G1 开发环境引导:检测 Termux / 桥授权 / Go 工具链,分步引导新设备
/// 在无电脑的情况下完成手机端开发环境的一次性配置。
class EnvironmentSheet extends StatefulWidget {
  const EnvironmentSheet({super.key});

  @override
  State<EnvironmentSheet> createState() => _EnvironmentSheetState();
}

enum _StepState { checking, ok, action, failed }

class _StepView {
  final String title;
  final String detail;
  _StepState state = _StepState.checking;
  String? hint;
  _StepView({required this.title, required this.detail});
}

class _EnvironmentSheetState extends State<EnvironmentSheet> {
  static const _bridge = MethodChannel('nexus/termux_bridge');
  static const _bridgeDir = '/sdcard/pocketforge-bridge';
  static const _termuxApkUrls = [
    'https://mirrors.tuna.tsinghua.edu.cn/fdroid/archive/com.termux_118.apk',
    'https://f-droid.org/repo/com.termux_118.apk',
  ];
  static const _configCommand =
      'mkdir -p ~/.termux && sed -i "s/^#[[:space:]]*allow-external-apps[[:space:]]*=.*/allow-external-apps = true/" '
      '~/.termux/termux.properties 2>/dev/null; '
      'grep -q "^allow-external-apps" ~/.termux/termux.properties 2>/dev/null || '
      'echo "allow-external-apps = true" >> ~/.termux/termux.properties; '
      'termux-reload-settings 2>/dev/null; '
      'echo 配置完成,请完全退出Termux(通知栏滑掉或系统里强行停止)后重新打开';
  static const _toolchainCommand = 'pkg install -y golang git curl jq && '
      'go env -w GOPROXY=https://goproxy.cn,direct && go env -w GOTOOLCHAIN=local && '
      'termux-wake-lock && echo 工具链就绪,可回到NEXUS点重新检测';

  late final List<_StepView> _steps;
  bool _running = false;
  String _installStatus = '';

  @override
  void initState() {
    super.initState();
    _steps = [
      _StepView(title: '1. 安装 Termux', detail: '桥的另一半(Go 工具链)运行在 Termux 沙箱里'),
      _StepView(title: '2. 允许本应用调用 Termux', detail: '在 Termux 中执行一条配置命令'),
      _StepView(title: '3. 安装 Go 工具链', detail: 'golang/git/curl 等,含国内加速'),
    ];
    _detect();
  }

  Future<void> _detect() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      // Step 1: Termux 是否安装
      _set(0, _StepState.checking);
      bool installed = false;
      try {
        installed = await _bridge.invokeMethod('isTermuxInstalled') == true;
      } catch (_) {}
      if (!installed) {
        _set(0, _StepState.action,
            hint: '点击下方按钮下载并安装 Termux(F-Droid 官方版,清华镜像优先)。'
                '安装完成后回到本页点"重新检测"。');
        _set(1, _StepState.failed, hint: '依赖上一步');
        _set(2, _StepState.failed, hint: '依赖上一步');
        return;
      }
      _set(0, _StepState.ok);

      // Step 2: 桥是否授权(allow-external-apps)。超时即未配置或 Termux 被冻结。
      _set(1, _StepState.checking);
      final bridge =
          await _runBridged('echo bridge-ok', const Duration(seconds: 6));
      if (!bridge.$1) {
        _set(1, _StepState.action, hint: bridge.$2);
        _set(2, _StepState.failed, hint: '依赖上一步');
        return;
      }
      _set(1, _StepState.ok);

      // Step 3: Go 工具链
      _set(2, _StepState.checking);
      final go = await _runBridged('go version', const Duration(seconds: 15));
      if (go.$1 && (go.$2 ?? '').contains('go version')) {
        _set(2, _StepState.ok);
      } else {
        _set(2, _StepState.action, hint: '桥已就绪但缺少 Go,点击下方按钮复制工具链安装命令');
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _set(int index, _StepState state, {String? hint}) {
    _steps[index].state = state;
    _steps[index].hint = hint;
    if (mounted) setState(() {});
  }

  /// 经桥执行命令,返回 (是否成功, 输出/失败原因)。独立于 TerminalCommandService(不依赖工作区)。
  Future<(bool, String?)> _runBridged(String command, Duration timeout) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final outFile = '$_bridgeDir/env-out-$id.txt';
    final codeFile = '$_bridgeDir/env-code-$id.txt';
    try {
      Directory(_bridgeDir).createSync(recursive: true);
    } catch (_) {}
    final script = "{\n$command\n} > '$outFile' 2>&1\necho \$? > '$codeFile'";
    try {
      await _bridge.invokeMethod('runInTermux',
          {'command': script, 'timeoutMs': timeout.inMilliseconds});
    } on PlatformException catch (e) {
      final msg = e.code == 'PERMISSION_DENIED'
          ? '用户拒绝了 Termux 调用权限,请重试并允许'
          : '无法启动 Termux 服务:${e.message}';
      return (false, msg);
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 400));
      final cf = File(codeFile);
      if (!cf.existsSync()) continue;
      final code = int.tryParse(cf.readAsStringSync().trim()) ?? -1;
      var out = '';
      final of = File(outFile);
      if (of.existsSync()) out = of.readAsStringSync();
      try {
        of.deleteSync();
        cf.deleteSync();
      } catch (_) {}
      return (code == 0, code == 0 ? out : '命令退出码 $code:$out');
    }
    return (
      false,
      '等待 Termux 执行超时。通常原因:① 未配置 allow-external-apps(复制下方命令到 Termux 执行);'
          '② Termux 被系统冻结(先打开一次 Termux 再重试)'
    );
  }

  Future<void> _installTermux() async {
    setState(() => _installStatus = '正在下载 Termux(约 90MB,清华镜像)...');
    for (final url in _termuxApkUrls) {
      final ok = await UpdateService().downloadAndInstall(url);
      if (!mounted) return;
      if (ok) {
        setState(() => _installStatus = '已拉起系统安装,完成后回来点"重新检测"');
        return;
      }
      setState(() => _installStatus = '源 $url 失败,尝试下一个源...');
    }
    if (mounted) {
      setState(
          () => _installStatus = '全部下载源失败,请检查网络后重试,或手动从 F-Droid 安装 Termux');
    }
  }

  void _copy(String label, String command) {
    Clipboard.setData(ClipboardData(text: command));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('$label 已复制,请打开 Termux 长按粘贴并回车执行')),
    );
  }

  /// 已就绪状态下收纳命令的折叠项(重置环境/换机时展开使用)。
  Widget _collapsedCommand(BuildContext context, String label, String command) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        leading: const Icon(Icons.terminal, size: 20),
        title: Text(label, style: Theme.of(context).textTheme.bodySmall),
        children: [_commandBlock(context, label, command)],
      ),
    );
  }

  /// 命令展示块:整段可见(SelectableText 可长按手动选择)+ 一键复制按钮。
  Widget _commandBlock(BuildContext context, String label, String command) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontWeight: FontWeight.w500)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy, size: 18),
            tooltip: '复制',
            onPressed: () => _copy(label, command),
          ),
        ]),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: dark ? Colors.black54 : const Color(0xFF1E1E28),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            command,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.4,
              color: dark ? Colors.white70 : Colors.greenAccent,
            ),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const NexusPageHeader(
        title: '开发环境检测',
        subtitle: 'Termux 桥与离线编译工具链',
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('在手机上开发 Windows exe 需要一次性配置以下环境。',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          for (final s in _steps) _stepCard(context, s),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _running ? null : _detect,
                icon: const Icon(Icons.refresh),
                label: const Text('重新检测'),
              ),
            ),
          ]),
          if (_installStatus.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_installStatus, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 24),
          Text(
              '说明:Termux 桥的执行结果是加密写入本机共享目录的,全程不经过电脑;'
              '若长期未打开 Termux 被系统冻结,执行会超时,打开一次 Termux 即可恢复。',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _stepCard(BuildContext context, _StepView s) {
    final (icon, color) = switch (s.state) {
      _StepState.checking => (Icons.hourglass_top, Colors.grey),
      _StepState.ok => (Icons.check_circle, Colors.green),
      _StepState.action => (Icons.error_outline, Colors.orange),
      _StepState.failed => (Icons.cancel, Colors.red),
    };
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(
                child: Text(s.title,
                    style: Theme.of(context).textTheme.titleMedium)),
          ]),
          const SizedBox(height: 4),
          Text(s.detail, style: Theme.of(context).textTheme.bodySmall),
          if (s.hint != null) ...[
            const SizedBox(height: 6),
            Text(s.hint!, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (s == _steps[0] && s.state == _StepState.action)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.icon(
                onPressed: _running ? null : _installTermux,
                icon: const Icon(Icons.download),
                label: const Text('下载并安装 Termux'),
              ),
            ),
          if (s == _steps[1]) ...[
            if (s.state == _StepState.action)
              _commandBlock(context, '配置命令(整段复制,粘贴到 Termux 回车)', _configCommand)
            else if (s.state == _StepState.ok)
              _collapsedCommand(context, '查看配置命令(重置环境/换机时使用)', _configCommand),
          ],
          if (s == _steps[2]) ...[
            if (s.state == _StepState.action)
              _commandBlock(
                  context, '工具链安装命令(整段复制,粘贴到 Termux 回车)', _toolchainCommand)
            else if (s.state == _StepState.ok)
              _collapsedCommand(
                  context, '查看工具链安装命令(重装工具链时使用)', _toolchainCommand),
          ],
        ]),
      ),
    );
  }
}
