import copy
import json
from pathlib import Path
import tempfile
import unittest
from release_evidence_gate import REQUIRED, digest, validate


class ReleaseEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / 'lib').mkdir()
        (self.root / 'lib/main.dart').write_text('void main() {}', encoding='utf-8')
        self.apk = self.root / 'app.apk'
        self.apk.write_bytes(b'fixture-only-not-an-apk')
        report = self.root / 'report.json'
        report.write_text(json.dumps({'passed': True, 'sourcesUnchanged': True}), encoding='utf-8')
        self.evidence = {'schema': 1, 'channel': 'private-apk', 'blockers': [],
                         'apkSha256': digest(self.apk), 'certificateSha256': 'fixture-cert',
                         'sourceSha256': {'lib/main.dart': digest(self.root / 'lib/main.dart')},
                         'gates': {name: {'status': 'passed', 'apkSha256': digest(self.apk),
                             'reviewedBy': 'fixture-reviewer', 'verifiedAt': '2026-10-19T00:00:00Z',
                             'report': 'report.json', 'reportSha256': digest(report)} for name in REQUIRED}}

    def check(self, data=None):
        return validate(self.root, self.apk, self.evidence if data is None else data, 'fixture-cert')

    def test_complete_fixture(self):
        self.assertEqual(self.check(), [])

    def test_missing_every_gate(self):
        for gate in REQUIRED:
            data = copy.deepcopy(self.evidence)
            del data['gates'][gate]
            self.assertTrue(self.check(data))

    def test_failed_pending_and_unknown_cannot_pass(self):
        for status in ('failed', 'running', 'blocked', 'unknown', None):
            data = copy.deepcopy(self.evidence)
            data['gates']['arm64_runtime']['status'] = status
            self.assertTrue(self.check(data))

    def test_artifact_changed(self):
        self.apk.write_bytes(b'changed')
        self.assertIn('apk_mismatch', self.check())

    def test_source_changed(self):
        (self.root / 'lib/main.dart').write_text('changed', encoding='utf-8')
        self.assertIn('source_mismatch:lib/main.dart', self.check())

    def test_new_source_missing_from_manifest(self):
        (self.root / 'lib/new.dart').write_text('new', encoding='utf-8')
        self.assertIn('incomplete_dart_sources', self.check())

    def test_report_changed(self):
        (self.root / 'report.json').write_text('{}', encoding='utf-8')
        self.assertTrue(self.check())

    def test_failed_report_cannot_be_labeled_passed(self):
        report = self.root / 'report.json'
        report.write_text(json.dumps({'passed': False, 'errorType': 'TimeoutException'}), encoding='utf-8')
        for gate in self.evidence['gates'].values():
            gate['reportSha256'] = digest(report)
        self.assertIn('report_not_passed:static_analysis', self.check())

    def test_path_escape(self):
        self.evidence['sourceSha256']['../outside'] = 'bad'
        self.assertIn('invalid_source_path', self.check())

    def test_wrong_certificate(self):
        self.evidence['certificateSha256'] = 'other'
        self.assertIn('certificate_mismatch', self.check())

    def test_missing_blockers_is_not_clear(self):
        del self.evidence['blockers']
        self.assertIn('open_or_missing_blockers', self.check())

    def test_other_channel_needs_review(self):
        self.evidence['channel'] = 'play-store'
        self.assertIn('channel_not_reviewed', self.check())


if __name__ == '__main__':
    unittest.main()
