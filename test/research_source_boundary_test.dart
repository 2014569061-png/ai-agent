import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/application/research_artifact_service.dart';
import 'package:mobile_agent/domain/research_artifact.dart';

void main() {
  for (final uri in ['https://127.0.0.1/private', 'https://169.254.169.254/metadata', 'https://192.168.1.1/private', 'file:///private']) {
    test('citation source rejected before connection: $uri', () async {
      final now = DateTime.utc(2026, 10, 19);
      final citation = EvidenceCitation(id: 'fixture', sourceTitle: 'fixture',
          sourceUri: uri, excerpt: 'fixture', capturedAt: now, verifiedAt: now);
      expect(await ResearchArtifactService.verifyHttpCitation(citation), isFalse);
    });
  }
}
