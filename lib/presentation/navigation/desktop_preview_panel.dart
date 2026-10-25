import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../application/chat_controller.dart';
import '../../application/desktop_preview_service.dart';
import '../../application/desktop_run_service.dart';
import 'desktop_run_dialog.dart';
import '../theme/desktop_theme.dart';
import 'desktop_workbench_panels.dart';

class DesktopPreviewPanel extends ConsumerStatefulWidget {
  const DesktopPreviewPanel(
      {super.key,
      required this.onProject,
      required this.onTerminal,
      this.compact = false});
  final VoidCallback onProject, onTerminal;
  final bool compact;
  @override
  ConsumerState<DesktopPreviewPanel> createState() =>
      _DesktopPreviewPanelState();
}

class _DesktopPreviewPanelState extends ConsumerState<DesktopPreviewPanel> {
  final _server = DesktopPreviewServer();
  final _address = TextEditingController();
  WebviewController? _webview;
  Future<void>? _webviewInitialization;
  String? _root, _error;
  Uri? _url;
  bool _mobile = false, _loading = false;
  bool _closing = false;
  late final AppLifecycleListener _lifecycle;
  Future<void>? _release;
  int _generation = 0;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: () async {
      setState(() => _closing = true);
      await WidgetsBinding.instance.endOfFrame;
      await _releaseResources();
      await DesktopRunService.instance.stopAll();
      return AppExitResponse.exit;
    });
  }

  Future<void> _releaseResources() => _release ??= () async {
        _generation++;
        for (final subscription in _subscriptions) {
          await subscription.cancel();
        }
        await _server.stop();
        await _disposeWebview();
      }();

  Future<void> _initializeWebview() async {
    if (await WebviewController.getWebViewVersion() == null) {
      throw StateError('请安装 Microsoft Edge WebView2 Runtime，或在浏览器中打开预览。');
    }
    if (!mounted) return;
    final controller = WebviewController();
    _webview = controller;
    await controller.initialize();
    if (!mounted) return;
    await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
    _subscriptions.add(controller.onLoadError.listen((error) {
      if (mounted) setState(() => _error = '页面加载失败：$error');
    }));
  }

  Future<void> _changeWorkspace(String? root) async {
    final generation = ++_generation;
    await _server.stop();
    if (_webviewInitialization != null) {
      try {
        await _webviewInitialization;
        if (mounted && generation == _generation) {
          await _webview?.loadUrl('about:blank');
        }
      } catch (_) {/* The next open reports initialization errors. */}
    }
    if (!mounted || generation != _generation || root == null) return;
    final preferences = await SharedPreferences.getInstance();
    if (!mounted || generation != _generation) return;
    _address.text = preferences.getString('desktop.preview.url.$root') ?? '';
    // Restore configuration, but do not start code or network requests silently.
  }

  Future<void> _showUrl(Uri url, {bool persist = false}) async {
    final generation = ++_generation;
    final root = _root;
    setState(() {
      _loading = true;
      _error = null;
      _url = url;
      _address.text = '$url';
    });
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        await (_webviewInitialization ??= _initializeWebview());
        if (!mounted || generation != _generation) return;
        await _webview!.loadUrl('$url');
      } else {
        throw StateError('内嵌网页预览支持 Windows，可在系统浏览器中打开。');
      }
      if (!mounted || generation != _generation) return;
      if (persist && root != null) {
        await (await SharedPreferences.getInstance())
            .setString('desktop.preview.url.$root', '$url');
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        if (_webview == null) _webviewInitialization = null;
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _runProject() async {
    if (_root == null) return;
    final uri = await showDialog<Uri>(
        context: context, builder: (_) => DesktopRunDialog(root: _root!));
    if (uri != null && mounted) await _showUrl(uri);
  }

  Future<void> _openAddress() async {
    if (_loading) return;
    final generation = ++_generation;
    setState(() => _loading = true);
    try {
      final url = DesktopPreviewServer.parseUrl(_address.text);
      await _server.stop();
      if (!mounted || generation != _generation) return;
      await _showUrl(url, persist: true);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openHtml({bool pick = false}) async {
    if (_loading) return;
    final root = _root;
    if (root == null) return widget.onProject();
    final generation = _generation;
    setState(() => _loading = true);
    try {
      String? entry;
      if (!pick) {
        for (final path in [
          'index.html',
          'dist/index.html',
          'build/web/index.html',
          'public/index.html'
        ]) {
          if (await File(p.join(root, path)).exists()) {
            entry = path;
            break;
          }
        }
      }
      if (entry == null) {
        final result = await FilePicker.pickFiles(
            dialogTitle: '选择项目内的 HTML 入口',
            type: FileType.custom,
            allowedExtensions: ['html']);
        entry = result.isEmpty ? null : result.single.path;
      }
      if (entry == null || !mounted || generation != _generation) return;
      final url = await _server.start(root, entry);
      if (!mounted || generation != _generation) {
        await _server.stop();
        return;
      }
      await _showUrl(url);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = '启动预览失败：$error');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _external() async {
    if (_url == null) return;
    try {
      if (!await launchUrl(_url!, mode: LaunchMode.externalApplication)) {
        throw StateError('无法打开系统浏览器');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _addressDialog() async {
    final open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('预览地址'),
                content: TextField(
                    controller: _address,
                    autofocus: true,
                    decoration: const InputDecoration(
                        hintText: 'http://localhost:3000'),
                    onSubmitted: (_) => Navigator.pop(context, true)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('打开'))
                ]));
    if (open == true && mounted) await _openAddress();
  }

  Widget _compactToolbar(DesktopTheme colors) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(children: [
        Expanded(
            child: Text('界面预览', style: Theme.of(context).textTheme.titleSmall)),
        IconButton(
            tooltip: '桌面预览',
            isSelected: !_mobile,
            onPressed: () => setState(() => _mobile = false),
            icon: Icon(Icons.desktop_windows_outlined,
                size: 16, color: !_mobile ? colors.accent : colors.muted)),
        IconButton(
            tooltip: '移动端预览',
            isSelected: _mobile,
            onPressed: () => setState(() => _mobile = true),
            icon: Icon(Icons.phone_android,
                size: 16, color: _mobile ? colors.accent : colors.muted)),
        IconButton(
            tooltip: '刷新预览',
            onPressed: _url == null || _loading ? null : () => _showUrl(_url!),
            icon: const Icon(Icons.refresh, size: 16)),
        PopupMenuButton<String>(
            enabled: !_loading,
            tooltip: '预览选项',
            onSelected: (value) {
              if (value == 'html') unawaited(_openHtml());
              if (value == 'pick') unawaited(_openHtml(pick: true));
              if (value == 'url') unawaited(_addressDialog());
              if (value == 'browser') unawaited(_external());
            },
            itemBuilder: (_) => [
                  const PopupMenuItem(value: 'html', child: Text('预览项目')),
                  const PopupMenuItem(value: 'pick', child: Text('选择 HTML 入口')),
                  const PopupMenuItem(value: 'url', child: Text('输入开发服务器地址')),
                  PopupMenuItem(
                      value: 'browser',
                      enabled: _url != null,
                      child: const Text('在浏览器打开')),
                ]),
      ]));

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_releaseResources());
    _address.dispose();
    super.dispose();
  }

  Future<void> _disposeWebview() async {
    try {
      await _webviewInitialization;
    } catch (_) {/* Initialization failed. */}
    await _webview?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_closing) return const SizedBox.shrink();
    final root =
        ref.watch(chatControllerProvider.select((s) => s.currentWorkspacePath));
    if (_root != root) {
      _root = root;
      _url = null;
      _error = null;
      _loading = false;
      _address.clear();
      unawaited(_changeWorkspace(root));
    }
    final colors = DesktopTheme.maybeOf(context)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.compact)
        _compactToolbar(colors)
      else ...[
        Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                  child: TextField(
                      controller: _address,
                      key: const ValueKey('desktop-preview-address'),
                      onSubmitted: (_) => _openAddress(),
                      decoration: const InputDecoration(
                          hintText: 'http://localhost:3000',
                          prefixIcon: Icon(Icons.language, size: 16)))),
              IconButton(
                  tooltip: '打开预览地址',
                  onPressed: _loading ? null : _openAddress,
                  icon: const Icon(Icons.arrow_forward)),
              IconButton(
                  tooltip: '刷新预览',
                  onPressed:
                      _url == null || _loading ? null : () => _showUrl(_url!),
                  icon: const Icon(Icons.refresh)),
              IconButton(
                  tooltip: '在浏览器打开',
                  onPressed: _url == null ? null : _external,
                  icon: const Icon(Icons.open_in_new)),
            ])),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                      onPressed: _root == null ? null : _runProject,
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: const Text('运行配置')),
                  TextButton(
                      onPressed: _root == null ||
                              !DesktopRunService.instance.running(_root!)
                          ? null
                          : () async {
                              await DesktopRunService.instance.stop(_root!);
                              if (mounted) setState(() {});
                            },
                      child: const Text('停止服务器')),
                  TextButton.icon(
                      onPressed: _loading ? null : () => _openHtml(),
                      icon: const Icon(Icons.web, size: 16),
                      label: const Text('预览项目')),
                  TextButton(
                      onPressed: _loading ? null : () => _openHtml(pick: true),
                      child: const Text('选择 HTML')),
                  TextButton.icon(
                      onPressed: () => setState(() => _mobile = false),
                      style: TextButton.styleFrom(
                          backgroundColor: !_mobile ? colors.selected : null),
                      icon:
                          const Icon(Icons.desktop_windows_outlined, size: 14),
                      label: const Text('桌面')),
                  TextButton.icon(
                      onPressed: () => setState(() => _mobile = true),
                      style: TextButton.styleFrom(
                          backgroundColor: _mobile ? colors.selected : null),
                      icon: const Icon(Icons.phone_android, size: 14),
                      label: const Text('移动端')),
                ])),
      ],
      const Divider(),
      if (_loading) const LinearProgressIndicator(),
      Expanded(
          child: _error != null
              ? DesktopPanelEmpty(
                  message: _error!,
                  action: _url == null ? null : _external,
                  label: '在浏览器打开')
              : _url == null
                  ? DesktopPanelEmpty(
                      message: widget.compact
                          ? '预览真实网页或开发服务器'
                          : '预览真实项目页面\n静态网页可直接预览；开发服务器启动后填入地址。',
                      action: widget.compact
                          ? () => _openHtml()
                          : root == null
                              ? widget.onProject
                              : widget.onTerminal,
                      label: widget.compact
                          ? '预览项目'
                          : root == null
                              ? '选择项目'
                              : '打开终端启动开发服务器')
                  : _webview?.value.isInitialized == true
                      ? ColoredBox(
                          color: colors.sidebar,
                          child: Center(
                              child: SizedBox(
                                  width: _mobile ? 390 : double.infinity,
                                  height: double.infinity,
                                  child: Webview(_webview!,
                                      permissionRequested: (_, __, ___) =>
                                          WebviewPermissionDecision.deny))))
                      : const Center(child: CircularProgressIndicator())),
    ]);
  }
}
