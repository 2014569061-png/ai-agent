import 'package:flutter/material.dart';

import '../../application/remote_execution_probe.dart';
import '../widgets/nexus_page_header.dart';
import '../widgets/section_card.dart';

class RemoteExecutionPage extends StatefulWidget {
  const RemoteExecutionPage({super.key});

  @override
  State<RemoteExecutionPage> createState() => _RemoteExecutionPageState();
}

class _RemoteExecutionPageState extends State<RemoteExecutionPage> {
  RemoteHandshake? _handshake;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    try {
      final handshake = await const RemoteExecutionProbe().handshake();
      if (!mounted) return;
      setState(() {
        _handshake = handshake;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final handshake = _handshake;
    return Scaffold(
      appBar: const NexusPageHeader(
        title: '远程执行验证',
        subtitle: '先确认架构、工具链和协议版本，再决定是否同步代码',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                SectionCard(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error ??
                        '协议 ${handshake?.protocolVersion}\n'
                            '架构 ${handshake?.arch}\n'
                            '并发 ${handshake?.maxConcurrency}\n'
                            '可用空间 ${handshake?.freeBytes} bytes\n'
                            '工具链 ${(handshake?.toolchain ?? const []).join(', ')}\n\n'
                            '重连后只查询既有 runId/jobId，不重复启动构建。',
                  ),
                ),
              ],
            ),
    );
  }
}
