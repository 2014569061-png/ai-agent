import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/development_target.dart';
import '../../../application/environment_service.dart';
import '../../../application/development_tool_installer.dart';
import '../../../infrastructure/update/update_service.dart';
import '../../environment/environment_status_view.dart';
import '../../widgets/nexus_disclosure.dart';
import '../../widgets/nexus_page_header.dart';

/// Replaces every existing value (including `false` and commented examples)
/// while preserving unrelated Termux settings.
const termuxExternalAppsConfigCommand = 'mkdir -p ~/.termux && '
    'properties=~/.termux/termux.properties && tmp="\$properties.nexus-tmp" && '
    '{ [ ! -f "\$properties" ] || sed \'/^[[:space:]]*#\\?[[:space:]]*allow-external-apps[[:space:]]*=/d\' "\$properties"; '
    'printf \'%s\\n\' \'allow-external-apps = true\'; } > "\$tmp" && '
    'mv "\$tmp" "\$properties" && '
    '{ termux-reload-settings 2>/dev/null || true; } && '
    'echo 配置完成，请从最近任务中彻底关闭 Termux 后重新打开';

/// 统一环境检测：展示四个 runtime 的真实可用性，并保留 Termux 安装引导。
class EnvironmentSheet extends ConsumerStatefulWidget {
  const EnvironmentSheet({
    super.key,
    this.toolInstaller,
    this.target,
  });

  final DevelopmentToolInstaller? toolInstaller;
  final DevelopmentTarget? target;

  @override
  ConsumerState<EnvironmentSheet> createState() => _EnvironmentSheetState();
}

enum _StepState { checking, ok, action, optional, failed }

class _StepView {
  final String title;
  final String detail;
  _StepState state = _StepState.checking;
  String? hint;
  _StepView({required this.title, required this.detail});
}

class _EnvironmentSheetState extends ConsumerState<EnvironmentSheet> {
  static const _bridge = MethodChannel('nexus/termux_bridge');
  static const _bridgeDir = '/sdcard/pocketforge-bridge';
  static const _bridgeCallTimeout = Duration(seconds: 5);
  static const _environmentCheckTimeout = Duration(seconds: 10);
  static const _termuxApkUrls = [
    'https://mirrors.tuna.tsinghua.edu.cn/fdroid/archive/com.termux_118.apk',
    'https://f-droid.org/repo/com.termux_118.apk',
  ];
  static const _configCommand = termuxExternalAppsConfigCommand;
  static const _toolchainCommand = 'pkg install -y golang git curl jq && '
      'go env -w GOPROXY=https://goproxy.cn,direct && go env -w GOTOOLCHAIN=local && '
      'termux-wake-lock && echo 工具链就绪,可回到NEXUS点重新检测';

  late final List<_StepView> _steps;
  bool _running = false;
  String _installStatus = '';
  String _commonToolsStatus = '';
  bool _installingCommonTools = false;
  String? _termuxInspectionError;
  EnvironmentSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    final target = widget.target;
    _steps = target == null
        ? [
            _StepView(
                title: '1. 安装 Termux', detail: '桥的另一半(Go 工具链)运行在 Termux 沙箱里'),
            _StepView(title: '2. 允许本应用调用 Termux', detail: '在 Termux 中执行一条配置命令'),
            _StepView(title: '3. 安装 Go 工具链', detail: 'golang/git/curl 等,含国内加速'),
          ]
        : [
            _StepView(
              title: '1. 检查可用运行时',
              detail: '优先使用内置 Alpine；Termux 是可选补充环境。',
            ),
            _StepView(
              title: '2. 检查 ${target.label} 工具',
              detail: target.environmentNote,
            ),
            _StepView(
              title: '3. 给出下一步',
              detail: '只安装当前目标需要的工具，不安装无关 SDK。',
            ),
          ];
    _detect();
  }

  Future<void> _detect() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      if (widget.target != null) {
        await _detectTarget();
        return;
      }
      // The full runtime/tool inventory is intentionally independent from the
      // Termux setup steps. A slow optional compiler probe must never turn
      // "Termux installed" into a red installation failure.
      unawaited(_refreshSnapshot());

      // Step 1: Termux 是否安装
      _set(0, _StepState.checking);
      bool installed = false;
      _termuxInspectionError = null;
      try {
        installed = await _bridge
                .invokeMethod('isTermuxInstalled')
                .timeout(_bridgeCallTimeout) ==
            true;
      } on TimeoutException {
        _termuxInspectionError = 'Termux 检测超时；请先打开 Termux、允许外部调用和后台运行后重试。';
      } on MissingPluginException {
        _termuxInspectionError = '当前平台没有注册 Termux 桥，请确认使用 Android 版本。';
      } catch (error) {
        _termuxInspectionError = 'Termux 检测失败：$error';
      }
      if (!installed) {
        _set(0, _StepState.action,
            hint: _termuxInspectionError ??
                '点击下方按钮下载并安装 Termux(F-Droid 官方版,清华镜像优先)。'
                    '安装完成后回到本页点"重新检测"。');
        _set(1, _StepState.optional,
            hint: 'Termux 是外部工具链，可按需安装；内置 Alpine/Android Shell 的状态见上方检测结果。');
        _set(2, _StepState.optional, hint: '可选：仅在需要 Termux Go 工具链时安装。');
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
    } on TimeoutException {
      _set(0, _StepState.failed, hint: '环境检测超时；请打开 Termux、确认桥授权和后台运行设置后重试。');
      _set(1, _StepState.action,
          hint: '请在 Termux 执行下方 allow-external-apps 配置命令后重试。');
      _set(2, _StepState.failed, hint: '等待环境检测完成');
    } catch (error) {
      _set(0, _StepState.failed, hint: '环境检测失败：$error');
      _set(1, _StepState.action, hint: '请先打开 Termux 并检查桥授权后重试。');
      _set(2, _StepState.failed, hint: '等待环境检测完成');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _detectTarget() async {
    final target = widget.target!;
    for (var index = 0; index < _steps.length; index++) {
      _set(index, _StepState.checking);
    }
    await _refreshSnapshot();
    if (!mounted) return;

    if (target == DevelopmentTarget.staticWeb) {
      _set(0, _StepState.ok, hint: '静态网页不依赖 Linux 运行时。');
      _set(1, _StepState.ok, hint: '文件工具即可创建 HTML、CSS 和 JavaScript。');
      _set(2, _StepState.ok, hint: '需要预览时再启用静态预览服务即可。');
      return;
    }
    if (target == DevelopmentTarget.windowsExe) {
      _set(0, _StepState.optional,
          hint: '可在手机上编辑源码，但 Windows 构建需交给 Windows 宿主机。');
      _set(1, _StepState.optional, hint: target.environmentNote);
      _set(2, _StepState.optional,
          hint: '本页不会伪造 Windows SDK、MSVC 或 Windows 运行库已安装。');
      return;
    }

    final snapshot = _snapshot;
    if (snapshot == null) {
      _set(0, _StepState.failed, hint: '运行时检测未完成，请点击重新检测。');
      _set(1, _StepState.optional, hint: target.environmentNote);
      _set(2, _StepState.optional, hint: '当前没有足够的真实探测结果。');
      return;
    }
    final tools = {for (final tool in snapshot.tools) tool.id: tool};
    final missing = target.tools.where((requirement) =>
        requirement.required && tools[requirement.id]?.available != true);
    final missingList = missing.toList(growable: false);
    _set(
      0,
      snapshot.selected.available ? _StepState.ok : _StepState.action,
      hint: snapshot.selected.available
          ? '已找到 ${snapshot.selected.label}。'
          : '没有可用 Linux 运行时，请先配置 Alpine 或 Termux。',
    );
    if (missingList.isEmpty) {
      _set(1, _StepState.ok, hint: '当前目标的必需工具已探测可用。');
      _set(2, _StepState.ok, hint: '可以继续执行项目对应的验证或构建。');
    } else if (missingList.any((item) => item.canInstallOnLinux)) {
      _set(1, _StepState.action,
          hint: '缺少 ${missingList.map((item) => item.label).join('、')}，可按需安装。');
      _set(2, _StepState.optional, hint: '安装完成后点击重新检测，不会安装无关 SDK。');
    } else {
      _set(1, _StepState.optional,
          hint: '缺少外部 SDK：${missingList.map((item) => item.label).join('、')}。');
      _set(2, _StepState.optional, hint: target.environmentNote);
    }
  }

  Future<void> _refreshSnapshot() async {
    try {
      final service = ref.read(environmentServiceProvider);
      service.invalidate();
      final snapshot =
          await service.inspect(force: true).timeout(_environmentCheckTimeout);
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (_) {
      // Candidate-level timeouts are rendered by the environment status view.
      // The setup steps below have their own, more specific diagnostics.
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
      await _bridge.invokeMethod('runInTermux', {
        'command': script,
        'timeoutMs': timeout.inMilliseconds,
      }).timeout(_bridgeCallTimeout);
    } on TimeoutException {
      return (
        false,
        '等待 Termux 执行超时。请打开 Termux、确认 allow-external-apps=true，'
            '并关闭电池限制后重试。',
      );
    } on PlatformException catch (e) {
      final msg = e.code == 'PERMISSION_DENIED'
          ? '用户拒绝了 Termux 调用权限,请重试并允许'
          : '无法启动 Termux 服务:${e.message}';
      return (false, msg);
    } on MissingPluginException {
      return (false, '当前平台没有注册 Termux 桥，请确认使用 Android 版本。');
    } catch (error) {
      return (false, '无法启动 Termux 服务：$error');
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

  Future<void> _installCommonTools() async {
    if (_installingCommonTools) return;
    setState(() {
      _installingCommonTools = true;
      _commonToolsStatus = widget.target == null
          ? '正在下载并安装常用工具，首次配置通常需要几分钟，请保持应用在前台…'
          : '正在按“${widget.target!.label}”安装所需工具，请保持应用在前台…';
    });
    DevelopmentToolInstallResult result;
    try {
      final installer = widget.toolInstaller ?? DevelopmentToolInstaller();
      result = await installer.installForTarget(widget.target);
    } catch (error) {
      result = DevelopmentToolInstallResult(
        succeeded: false,
        message: '安装未完成：$error。请检查网络和剩余空间后重试。',
      );
    }
    if (!mounted) return;
    setState(() {
      _installingCommonTools = false;
      _commonToolsStatus = result.message;
    });
    if (result.succeeded) {
      await _detect();
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
    return NexusDisclosure(
      headerPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      leading: const Icon(Icons.terminal, size: 20),
      title: Text(label, style: Theme.of(context).textTheme.bodySmall),
      child: _commandBlock(context, label, command),
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
        subtitle: 'Alpine / Termux / Android Shell / 本机进程',
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('检测四个运行时的真实可用性，不能用“安装了 Termux”代替 Alpine 状态。',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          if (widget.target != null) _targetSummaryCard(context),
          if (widget.target == null) _commonToolsCard(context),
          if (_snapshot != null) ...[
            const SizedBox(height: 12),
            EnvironmentStatusCard(
              snapshot: _snapshot!,
              compact: widget.target != null,
              toolIds: widget.target?.tools.map((tool) => tool.id).toSet(),
              toolSectionTitle: widget.target == null
                  ? null
                  : '当前目标工具（${widget.target!.label}）',
              showGlobalMissing: widget.target == null,
            ),
          ],
          if (widget.target == null) ...[
            const SizedBox(height: 12),
            Text('Termux 安装引导仍可用于补充工具链，但不会覆盖上面的 runtime 检测。',
                style: Theme.of(context).textTheme.bodySmall),
          ],
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
          if (widget.target == null) ...[
            const SizedBox(height: 24),
            Text(
                '说明:Termux 桥的执行结果是加密写入本机共享目录的,全程不经过电脑;'
                '若长期未打开 Termux 被系统冻结,执行会超时,打开一次 Termux 即可恢复。',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  Widget _targetSummaryCard(BuildContext context) {
    final target = widget.target!;
    final theme = Theme.of(context);
    final canInstall = target.tools.any((tool) => tool.canInstallOnLinux);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.track_changes_rounded),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('本次只检查：${target.label}',
                      style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(target.environmentNote),
            if (target.tools.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final tool in target.tools)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${tool.required ? '必需' : '可选'} · ${tool.label}：${tool.description}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
            if (canInstall) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _running || _installingCommonTools
                      ? null
                      : _installCommonTools,
                  icon: _installingCommonTools
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_done_rounded),
                  label: Text(_installingCommonTools
                      ? '正在配置，请勿退出'
                      : '按需安装 ${target.label} 工具'),
                ),
              ),
            ],
            if (_commonToolsStatus.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_commonToolsStatus, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  Widget _commonToolsCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_fix_high_rounded),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('新手一键配置', style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('自动安装 Node.js、npm、Python、pip、Go、Git、curl 和 jq；'
                '优先安装到内置 Alpine，无需复制命令。'),
            const SizedBox(height: 6),
            Text(
              '建议预留数百 MB 空间并连接 Wi-Fi。Flutter SDK、Android SDK、aapt2 和 d8 '
              '体积大且手机兼容性有限，不会自动安装。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _running || _installingCommonTools
                    ? null
                    : _installCommonTools,
                icon: _installingCommonTools
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_done_rounded),
                label: Text(
                  _installingCommonTools ? '正在配置，请勿退出' : '一键安装常用开发工具',
                ),
              ),
            ),
            if (_commonToolsStatus.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_commonToolsStatus, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stepCard(BuildContext context, _StepView s) {
    final (icon, color) = switch (s.state) {
      _StepState.checking => (Icons.hourglass_top, Colors.grey),
      _StepState.ok => (Icons.check_circle, Colors.green),
      _StepState.action => (Icons.error_outline, Colors.orange),
      _StepState.optional => (Icons.info_outline, Colors.blueGrey),
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
          if (widget.target == null &&
              s == _steps[0] &&
              s.state == _StepState.action)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.icon(
                onPressed: _running ? null : _installTermux,
                icon: const Icon(Icons.download),
                label: const Text('下载并安装 Termux'),
              ),
            ),
          if (widget.target == null && s == _steps[1]) ...[
            if (s.state == _StepState.action || s.state == _StepState.optional)
              _commandBlock(context, '配置命令(整段复制,粘贴到 Termux 回车)', _configCommand)
            else if (s.state == _StepState.ok)
              _collapsedCommand(context, '查看配置命令(重置环境/换机时使用)', _configCommand),
          ],
          if (widget.target == null && s == _steps[2]) ...[
            if (s.state == _StepState.action || s.state == _StepState.optional)
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
