import '../infrastructure/remote/remote_executor_client.dart';

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

  factory RemoteHandshake.fromJson(Map<String, dynamic> json) =>
      RemoteHandshake(
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

  factory RemoteExecutionProbe.forEndpoint(Uri endpoint, String token) =>
      RemoteExecutionProbe(
          handshakeClient:
              RemoteExecutorClient(endpoint: endpoint, token: token).handshake);

  final Future<Map<String, dynamic>> Function()? handshakeClient;

  Future<RemoteHandshake> handshake() async {
    final client = handshakeClient;
    if (client == null) {
      throw StateError('尚未配置远程执行端，未发起网络请求');
    }
    final raw = await client();
    if (raw['protocolVersion'] != 'nexus-remote/1' ||
        raw['arch'] is! String ||
        (raw['arch'] as String).isEmpty ||
        raw['arch'] == 'unknown' ||
        raw['toolchain'] is! List ||
        (raw['toolchain'] as List).any((item) => item is! String) ||
        raw['freeBytes'] is! int ||
        (raw['freeBytes'] as int) < 0 ||
        raw['maxConcurrency'] is! int ||
        (raw['maxConcurrency'] as int) < 1) {
      throw const FormatException('远程协议或能力响应无效');
    }
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

class RemotePairingLease {
  const RemotePairingLease({
    required this.pairingId,
    required this.endpoint,
    required this.arch,
    required this.protocolVersion,
    required this.pairedAtUtc,
    required this.leaseExpiresAtUtc,
    this.revoked = false,
  });

  final String pairingId;
  final String endpoint;
  final String arch;
  final String protocolVersion;
  final DateTime pairedAtUtc;
  final DateTime leaseExpiresAtUtc;
  final bool revoked;

  bool isLeaseActive({DateTime? now}) {
    if (revoked) return false;
    final clock = (now ?? DateTime.now()).toUtc();
    return clock.isBefore(leaseExpiresAtUtc);
  }

  RemotePairingLease renew({
    Duration ttl = const Duration(minutes: 30),
    DateTime? now,
  }) {
    if (revoked) {
      throw StateError('已撤销配对的远程执行端不可续期租约');
    }
    final clock = (now ?? DateTime.now()).toUtc();
    return RemotePairingLease(
      pairingId: pairingId,
      endpoint: endpoint,
      arch: arch,
      protocolVersion: protocolVersion,
      pairedAtUtc: pairedAtUtc,
      leaseExpiresAtUtc: clock.add(ttl),
      revoked: false,
    );
  }

  RemotePairingLease revoke() => RemotePairingLease(
        pairingId: pairingId,
        endpoint: endpoint,
        arch: arch,
        protocolVersion: protocolVersion,
        pairedAtUtc: pairedAtUtc,
        leaseExpiresAtUtc: leaseExpiresAtUtc,
        revoked: true,
      );

  /// Reconciles remote jobs after a disconnect or lease expiration without
  /// silently replaying side-effectful jobs.
  RemoteJobStatus reconcileAfterDisconnect(
    RemoteJobStatus job, {
    DateTime? now,
  }) {
    if (revoked) {
      return RemoteJobStatus(
        runId: job.runId,
        jobId: job.jobId,
        status: 'pairing_revoked_halted',
        artifactHash: job.artifactHash,
      );
    }
    if (!isLeaseActive(now: now) &&
        (job.status == 'running' || job.status == 'queued')) {
      return RemoteJobStatus(
        runId: job.runId,
        jobId: job.jobId,
        status: 'lease_expired_needs_reconcile',
        artifactHash: job.artifactHash,
      );
    }
    return job;
  }
}
