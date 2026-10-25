import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/desktop_device_service.dart';

class DesktopDevicesDialog extends ConsumerStatefulWidget {
  const DesktopDevicesDialog({super.key});

  @override
  ConsumerState<DesktopDevicesDialog> createState() =>
      _DesktopDevicesDialogState();
}

class _DesktopDevicesDialogState extends ConsumerState<DesktopDevicesDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _perform(
      Future<void> Function(DesktopDeviceService) action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(desktopDeviceServiceProvider));
      if (mounted) await ref.read(desktopDevicesProvider.notifier).refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _configure() async {
    final service = ref.read(desktopDeviceServiceProvider);
    final adb = TextEditingController(text: service.adbOverride ?? '');
    final scrcpy = TextEditingController(text: service.scrcpyOverride ?? '');
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('设备工具设置'),
              content: SizedBox(
                  width: 480,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('留空时自动检测 PATH 和 Android SDK。选择程序文件后即可使用。'),
                    const SizedBox(height: 16),
                    for (final entry in [
                      (adb, 'ADB 程序路径'),
                      (scrcpy, 'scrcpy 程序路径')
                    ])
                      Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextField(
                            controller: entry.$1,
                            decoration: InputDecoration(
                                labelText: entry.$2,
                                suffixIcon: IconButton(
                                  tooltip: '选择程序',
                                  icon: const Icon(Icons.folder_open),
                                  onPressed: () async {
                                    final file = await FilePicker.pickFile();
                                    if (context.mounted && file != null) {
                                      entry.$1.text = file.xFile.path;
                                    }
                                  },
                                )),
                          )),
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('保存')),
              ],
            ));
    final adbPath = adb.text;
    final scrcpyPath = scrcpy.text;
    adb.dispose();
    scrcpy.dispose();
    if (accepted == true && mounted) {
      await _perform((service) => service.configure(adbPath, scrcpyPath));
    }
  }

  Future<void> _input() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('向设备输入文字'),
              content: SizedBox(
                  width: 420,
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                        hintText: '输入英文或数字', helperText: '中文请在投屏窗口中粘贴'),
                  )),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, controller.text),
                    child: const Text('输入')),
              ],
            ));
    controller.dispose();
    if (text != null && mounted) {
      await _perform((service) => service.inputText(text));
    }
  }

  Future<void> _screenshot() async {
    await _perform((service) async {
      final bytes = Uint8List.fromList(await service.screenshot());
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('设备截图'),
                content: SizedBox(
                    width: 480,
                    height: 500,
                    child: Image.memory(bytes, fit: BoxFit.contain)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('关闭')),
                  FilledButton(
                      onPressed: () async {
                        try {
                          final path = await FilePicker.saveFile(
                            dialogTitle: '保存截图',
                            fileName:
                                'device-${DateTime.now().millisecondsSinceEpoch}.png',
                            type: FileType.custom,
                            allowedExtensions: ['png'],
                            bytes: bytes,
                            mimeType: 'image/png',
                          );
                          if (path == null) return;
                          if (context.mounted) Navigator.pop(context);
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('保存失败：$error')));
                          }
                        }
                      },
                      child: const Text('保存 PNG')),
                ],
              ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(desktopDevicesProvider);
    final snapshot = state.asData?.value;
    final connected =
        snapshot?.selected?.connected == true && snapshot?.problem == null;
    final enabled = !_busy && connected;
    return AlertDialog(
      title: Row(children: [
        const Expanded(child: Text('Android 设备')),
        IconButton(
            tooltip: '设备工具设置',
            onPressed: _busy ? null : _configure,
            icon: const Icon(Icons.settings_outlined)),
        IconButton(
            tooltip: '刷新设备',
            onPressed: _busy
                ? null
                : () => ref.read(desktopDevicesProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh)),
      ]),
      content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.isLoading) const LinearProgressIndicator(),
              if (state.hasError) Text('设备检测失败：${state.error}'),
              if (snapshot != null) ...[
                if (snapshot.adbPath == null)
                  const Text('未找到 ADB。请在设备工具设置中选择 Android SDK 的 adb.exe。'),
                if (snapshot.problem != null)
                  SelectableText('检测失败：${snapshot.problem}'),
                if (snapshot.adbPath != null &&
                    snapshot.devices.isEmpty &&
                    snapshot.problem == null)
                  const Text('没有连接的设备。连接 USB 后，在手机上开启并授权 USB 调试。'),
                for (final device in snapshot.devices)
                  ListTile(
                    leading: Icon(device.serial == snapshot.selectedSerial
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off),
                    title: Text(device.label),
                    subtitle: Text('${device.serial} · ${device.statusLabel}'),
                    onTap: _busy
                        ? null
                        : () => ref
                            .read(desktopDevicesProvider.notifier)
                            .select(device.serial),
                  ),
                const SizedBox(height: 16),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                      onPressed: enabled &&
                              snapshot.scrcpyPath != null &&
                              snapshot.mirroringSerial == null
                          ? () => _perform((service) => service.startMirror())
                          : null,
                      icon: const Icon(Icons.cast),
                      label: const Text('开始投屏')),
                  OutlinedButton(
                      onPressed: !_busy && snapshot.mirroringSerial != null
                          ? () => _perform((service) => service.stopMirror())
                          : null,
                      child: const Text('停止投屏')),
                  OutlinedButton(
                      onPressed: enabled
                          ? () => _perform((service) => service.back())
                          : null,
                      child: const Text('返回')),
                  OutlinedButton(
                      onPressed: enabled
                          ? () => _perform((service) => service.home())
                          : null,
                      child: const Text('主页')),
                  OutlinedButton(
                      onPressed: enabled ? _input : null,
                      child: const Text('输入文字')),
                  OutlinedButton(
                      onPressed: enabled ? _screenshot : null,
                      child: const Text('截图')),
                ]),
                if (snapshot.scrcpyPath == null)
                  const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('投屏需要 scrcpy。安装后在设备工具设置中选择 scrcpy.exe。')),
                if (snapshot.mirroringSerial != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('正在投屏：${snapshot.mirroringSerial}')),
              ],
              if (_busy)
                const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator()),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SelectableText(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
            ],
          ))),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('关闭'))
      ],
    );
  }
}
