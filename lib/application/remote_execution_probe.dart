class RemoteHandshake {
  const RemoteHandshake({
    required this.protocolVersion,
    required this.arch,
    required this.toolchain,
    required this.freeBytes,
    required this.maxConcurrency,
  });

  final String protocolVersion;
  final String arch;
  final List<String> toolchain;
  final int freeBytes;
  final int maxConcurrency;

  factory RemoteHandshake.fromJson(Map<String, dynamic> json) => RemoteHandshake(
        protocolVersion: json['protocolVersion']?.toString() ?? '',
        arch: json['arch']?.toString() ?? '',
        toolchain: (json['toolchain'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(growable: false),
        freeBytes: (json['freeBytes'] as num?)?.toInt() ?? 0,
        maxConcurrency: (json['maxConcurrency'] as num?)?.toInt() ?? 1,
      );
}

class RemoteJobStatus {
  const RemoteJobStatus({
    required this.runId,
    required this.jobId,
    required this.status,
    this.artifactHash,
  });

  final String runId;
  final String jobId;
  final String status;
  final String? artifactHash;
}

/// C1 技术验证：用既有作业事件契约查询远端，不在阶段 A 接入多家后端。
class RemoteExecutionProbe {
  const RemoteExecutionProbe({this.handshakeClient});

  final Future<Map<String, dynamic>> Function()? handshakeClient;

  Future<RemoteHandshake> handshake() async {
    final raw = await (handshakeClient ??
        (() async => <String, dynamic>{
              'protocolVersion': 'nexus-remote/0',
              'arch': 'unknown',
              'toolchain': const <String>[],
              'freeBytes': 0,
              'maxConcurrency': 1,
            }))();
    return RemoteHandshake.fromJson(raw);
  }

  RemoteJobStatus statusFor({
    required String runId,
    required String jobId,
    required String status,
    String? artifactHash,
  }) {
    return RemoteJobStatus(
      runId: runId,
      jobId: jobId,
      status: status,
      artifactHash: artifactHash,
    );
  }
}
