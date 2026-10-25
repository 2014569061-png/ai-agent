import 'dart:io';

import '../domain/result_card.dart';
import 'artifact_service.dart';
import 'result_action_service.dart';

typedef ArtifactLookup = Future<ProjectArtifact?> Function(String id);

/// A share sheet being dismissed or reporting no outcome is not delivery success.
enum ArtifactShareOutcome { handedOff, dismissed, unavailable }

/// Reads the saved private copy, never a path/URL supplied in a card snapshot.
class ArtifactResultResourceReader implements ResultResourceReader {
  const ArtifactResultResourceReader({
    required this.lookup,
    required this.artifacts,
  });

  final ArtifactLookup lookup;
  final ArtifactService artifacts;

  @override
  Future<ResultResourceSnapshot?> read({
    required String resourceType,
    required String resourceId,
  }) async {
    if (resourceType != 'artifact') return null;
    final artifact = await lookup(resourceId);
    if (artifact == null || artifact.id != resourceId) return null;
    final payload = await artifacts.inspectPayload(artifact);
    return ResultResourceSnapshot(
      resourceType: resourceType,
      resourceId: resourceId,
      // Artifacts are immutable copies; a new saved copy has a new ID.
      version: 1,
      status: switch (payload.state) {
        ArtifactPayloadState.intact => ResultCardStatus.active,
        ArtifactPayloadState.changed => ResultCardStatus.changed,
        _ => ResultCardStatus.unavailable,
      },
    );
  }
}

/// The production file adapter. Platform operations are wired by the owning UI;
/// unsupported reminder/calendar/route/diff actions remain fail-closed.
class ArtifactResultActionExecutor implements ResultActionExecutor {
  const ArtifactResultActionExecutor({
    required this.lookup,
    required this.artifacts,
    required this.canInteract,
    required this.openPreview,
    required this.shareFile,
  });

  final ArtifactLookup lookup;
  final ArtifactService artifacts;
  final bool Function() canInteract;
  final Future<bool> Function(ProjectArtifact artifact) openPreview;
  final Future<ArtifactShareOutcome> Function(File file) shareFile;

  @override
  Future<ResultActionExecutionResult> execute(
      ResultActionExecutionRequest request) async {
    if (request.executorKey != request.actionType ||
        !const {'file.preview', 'file.share'}.contains(request.actionType) ||
        request.card.kind != ResultCardKind.file ||
        request.card.resourceType != 'artifact' ||
        request.card.resourceVersion != 1) {
      return const ResultActionExecutionResult.failed(
          message: '该资源没有可用的文件执行器，未执行操作');
    }
    final artifact = await lookup(request.card.resourceId);
    if (artifact == null || artifact.id != request.card.resourceId) {
      return const ResultActionExecutionResult.failed(
          message: '成果记录已删除，未执行操作；请刷新');
    }
    // Repeat integrity and permission checks at the actual dispatch boundary.
    final file = await artifacts.verifiedPayload(artifact);
    if (!canInteract() ||
        (request.canContinue != null && !await request.canContinue!())) {
      return const ResultActionExecutionResult.failed(
          message: '页面已关闭、应用不在前台或处于只读模式，未执行操作');
    }
    if (request.actionType == 'file.preview') {
      return await openPreview(artifact)
          ? const ResultActionExecutionResult.succeeded(message: '文件预览已打开')
          : const ResultActionExecutionResult.failed(
              message: '未能打开文件预览；请刷新后重试');
    }
    final outcome = await shareFile(file);
    return switch (outcome) {
      ArtifactShareOutcome.handedOff =>
        const ResultActionExecutionResult.succeeded(
          message: '已交给系统分享；不代表接收方已经保存或收到',
          result: {'delivery': 'system_handoff_only'},
        ),
      ArtifactShareOutcome.dismissed =>
        const ResultActionExecutionResult.failed(message: '已取消系统分享，未确认交付'),
      ArtifactShareOutcome.unavailable =>
        const ResultActionExecutionResult.failed(
            message: '系统未返回可确认的分享结果，交付状态未知；请检查系统分享状态'),
    };
  }
}
