"""Transport regressions; no emulator, model calls or platform mutations."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from emulator_contract_support import (
    NoRedirect, VerificationFailure, contract_main, run_contract,
)


class ContractTransportTest(unittest.TestCase):
    def setUp(self):
        temp_root = Path(__file__).resolve().parents[1] / 'local/temp'
        temp_root.mkdir(parents=True, exist_ok=True)
        temporary = tempfile.TemporaryDirectory(dir=temp_root)
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.metadata = self.root / 'local/android-preview/vm-service.json'
        self.metadata.parent.mkdir(parents=True)
        self.report_path = self.root / 'reports/contract.json'
        self.set_endpoint('ws://127.0.0.1:12345/secret/ws')
        self.report = {
            'type': 'ExampleContractChecks', 'fixtureOnly': True,
            'cases': [{'passed': True}, {'passed': True}],
            'passed': 2, 'total': 2, 'modelCalls': 0, 'platformMutations': 0,
        }
        self.opener = Mock()
        patcher = patch('emulator_contract_support.urllib.request.build_opener',
                        return_value=self.opener)
        patcher.start()
        self.addCleanup(patcher.stop)

    def set_endpoint(self, uri, device='emulator-5554'):
        self.metadata.write_text(json.dumps({'deviceId': device, 'wsUri': uri}),
                                 encoding='utf-8')

    def run_contract(self, report=None, **kwargs):
        self.opener.open.side_effect = [
            io.BytesIO(json.dumps({'result': {'isolates': [
                {'id': 'isolates/1', 'name': 'main'}]}}).encode()),
            io.BytesIO(json.dumps({'result': report or self.report}).encode()),
        ]
        with contextlib.redirect_stdout(io.StringIO()):
            return run_contract(
                self.root, self.report_path, method='ext.nexus.exampleContract',
                result_type='ExampleContractChecks', expected_cases=2, **kwargs)

    def test_success_preserves_rpc_timeout_and_report(self):
        self.assertEqual(self.run_contract(timeout=90), 0)
        written = json.loads(self.report_path.read_text(encoding='utf-8'))
        self.assertEqual(written['executionTarget'], 'emulator-5554')
        self.assertEqual(written['cases'], self.report['cases'])
        self.assertEqual(self.opener.open.call_args_list[1].args[0],
                         'http://127.0.0.1:12345/secret/ext.nexus.exampleContract?isolateId=isolates%2F1')
        self.assertTrue(all(call.kwargs['timeout'] == 90
                            for call in self.opener.open.call_args_list))

    def test_failed_checks_write_report_and_return_one(self):
        self.report['cases'][1]['passed'] = False
        self.report['passed'] = 1
        self.assertEqual(self.run_contract(), 1)
        self.assertTrue(self.report_path.is_file())

    def test_unapproved_device_and_endpoints_never_connect(self):
        for uri, device in [
            ('ws://127.0.0.1:12345/secret/ws', 'phone-123'),
            ('ws://example.com/secret/ws', 'emulator-5554'),
            ('http://127.0.0.1/secret/ws', 'emulator-5554'),
            ('ws://user:secret@127.0.0.1/secret/ws', 'emulator-5554'),
            ('ws://127.0.0.1/secret/ws?secret=1', 'emulator-5554'),
            ('ws://127.0.0.1/secret/ws#secret', 'emulator-5554'),
            ('ws://127.0.0.1/secret/', 'emulator-5554'),
        ]:
            with self.subTest(uri=uri, device=device):
                self.set_endpoint(uri, device)
                with self.assertRaises(VerificationFailure):
                    self.run_contract()
        self.opener.open.assert_not_called()

    def test_invalid_results_are_rejected_without_writing(self):
        for changes in [
            {'type': 'WrongChecks'}, {'fixtureOnly': False}, {'modelCalls': 1},
            {'platformMutations': 1}, {'cases': None}, {'cases': []},
            {'cases': [{'passed': 1}, {'passed': True}]},
            {'cases': [None, {'passed': True}]}, {'passed': 1}, {'total': 3},
        ]:
            with self.subTest(changes=changes):
                with self.assertRaises(VerificationFailure):
                    self.run_contract({**self.report, **changes})
                self.assertFalse(self.report_path.exists())

    def test_redirect_is_rejected(self):
        with self.assertRaises(VerificationFailure):
            NoRedirect().redirect_request(None, None, 302, '', {}, 'http://example.com')

    def test_oversize_response_and_rpc_error_are_rejected(self):
        for raw in [b' ' * (2 * 1024 * 1024 + 1), b'{"error":{"message":"secret"}}']:
            self.opener.open.side_effect = None
            self.opener.open.return_value = io.BytesIO(raw)
            with self.assertRaises(VerificationFailure):
                run_contract(self.root, self.report_path,
                             method='ext.nexus.exampleContract',
                             result_type='ExampleContractChecks', expected_cases=2)
            self.assertFalse(self.report_path.exists())

    def test_cli_redacts_unexpected_exception_details(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = contract_main(Mock(side_effect=ValueError('endpoint-secret')))
        self.assertEqual(status, 2)
        self.assertIn('ValueError', output.getvalue())
        self.assertNotIn('endpoint-secret', output.getvalue())


if __name__ == '__main__':
    unittest.main()
