import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import threading
import time
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from windows_remote_executor import Executor, JobError, Server


class ExecutorTests(unittest.TestCase):
    def setUp(self):
        parent = Path('local/temp')
        parent.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix='remote-executor-test-', dir=parent)
        self.root = Path(self.temp.name).resolve()
        self.state = self.root / 'state'
        self.token = self.root / 'token'
        self.tasks = {
            'wait': {'argv': [sys.executable, '-c', 'import time; time.sleep(3)'], 'cwd': str(self.root), 'timeout': 10},
            'write': {'argv': [sys.executable, '-c', "from pathlib import Path; Path('result.txt').write_text('version-one')"], 'cwd': str(self.root), 'artifacts': ['result.txt']},
            'fail': {'argv': [sys.executable, '-c', 'raise SystemExit(7)'], 'cwd': str(self.root)},
            'missing': {'argv': [sys.executable, '-c', 'print(1)'], 'cwd': str(self.root), 'artifacts': ['missing.txt']},
        }
        self.store = Executor(self.state, self.token, self.tasks)

    def tearDown(self):
        self.store.close()
        self.temp.cleanup()

    def submit(self, name='diagnostic', key='request-1', run='run-1'):
        return self.store.submit({'requestId': key, 'runId': run, 'task': name})[0]

    def wait(self, job_id, statuses=('completed', 'failed', 'unknown', 'cancelled')):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            job = self.store.get(job_id)
            if job['status'] in statuses:
                return job
            time.sleep(.02)
        self.fail('job did not reach expected state')

    def test_auth_rotation_and_revocation(self):
        token = self.token.read_text().strip()
        self.assertFalse(self.store.authorized(''))
        self.assertTrue(self.store.authorized('Bearer ' + token))
        self.token.write_text('x' * 48)
        self.assertFalse(self.store.authorized('Bearer ' + token))
        self.token.unlink()
        self.assertFalse(self.store.authorized('Bearer ' + 'x' * 48))

    def test_handshake_is_real(self):
        data = self.store.handshake()
        self.assertEqual(data['protocolVersion'], 'nexus-remote/1')
        self.assertGreater(data['freeBytes'], 0)
        self.assertNotEqual(data['arch'], 'unknown')
        self.assertIn('diagnostic', data['tasks'])

    def test_process_logs_and_idempotency(self):
        one = self.submit()
        two = self.submit()
        self.assertEqual(one['jobId'], two['jobId'])
        job = self.wait(one['jobId'])
        self.assertEqual(job['status'], 'completed')
        self.assertEqual(job['exitCode'], 0)
        self.assertIn('NEXUS remote diagnostic', self.store.logs(one['jobId']))
        self.assertEqual(len(self.store.list_jobs()), 1)
        with self.assertRaises(JobError) as error:
            self.submit('fail')
        self.assertEqual(error.exception.code, 409)

    def test_no_remote_commands_or_unknown_tasks(self):
        for payload in [
            {'requestId': 'x', 'runId': 'y', 'task': 'diagnostic', 'command': 'whoami'},
            {'requestId': 'x', 'runId': 'y', 'task': 'not-configured'},
            {'requestId': '', 'runId': 'y', 'task': 'diagnostic'},
        ]:
            with self.assertRaises(JobError):
                self.store.submit(payload)
        self.assertEqual(self.store.list_jobs(), [])

    def test_failed_process_is_not_success(self):
        job = self.wait(self.submit('fail')['jobId'])
        self.assertEqual(job['status'], 'failed')
        self.assertEqual(job['exitCode'], 7)

    def test_queued_cancel_does_not_start(self):
        running = self.submit('wait', key='first')
        self.wait(running['jobId'], statuses=('running',))
        queued = self.submit('diagnostic', key='second')
        self.assertEqual(self.store.cancel(queued['jobId'])['status'], 'cancelled')
        self.store.cancel(running['jobId'])
        self.wait(running['jobId'])
        self.assertEqual(self.store.get(queued['jobId'])['status'], 'cancelled')
        self.assertEqual(self.store.logs(queued['jobId']), '')

    def test_running_cancel_does_not_claim_undo_or_full_tree_stop(self):
        job = self.submit('wait')
        self.wait(job['jobId'], statuses=('running',))
        self.store.cancel(job['jobId'])
        result = self.wait(job['jobId'])
        self.assertEqual(result['status'], 'unknown')
        self.assertIn('effects', result['reason'])

    def test_artifacts_are_snapshotted_with_integrity(self):
        job = self.wait(self.submit('write')['jobId'])
        self.assertEqual(job['status'], 'completed')
        (self.root / 'result.txt').write_text('version-two')
        data, digest = self.store.artifact(job['jobId'], 0)
        self.assertEqual(data, b'version-one')
        self.assertEqual(len(digest), 64)
        (self.state / (job['jobId'] + '.artifacts') / '0').write_bytes(b'tampered')
        with self.assertRaises(JobError) as error:
            self.store.artifact(job['jobId'], 0)
        self.assertEqual(error.exception.code, 409)

    def test_missing_artifact_cannot_be_reported_complete(self):
        result = self.wait(self.submit('missing')['jobId'])
        self.assertEqual(result['status'], 'unknown')

    def test_restart_preserves_completed_jobs_and_does_not_replay(self):
        job = self.wait(self.submit()['jobId'])
        self.store.close()
        self.store = Executor(self.state, self.token, self.tasks)
        self.assertEqual(self.store.get(job['jobId'])['status'], 'completed')
        self.assertEqual(self.submit()['jobId'], job['jobId'])
        # Simulate a crash snapshot, not a real second execution.
        self.store._update(job['jobId'], status='running')
        self.store.close()
        self.store = Executor(self.state, self.token, self.tasks)
        self.assertEqual(self.store.get(job['jobId'])['status'], 'unknown')
        self.assertEqual(self.submit()['status'], 'unknown')

    def test_only_one_executor_can_own_the_state(self):
        with self.assertRaises(ValueError):
            Executor(self.state, self.token, self.tasks)

    def test_http_auth_and_submit_query(self):
        server = Server(('127.0.0.1', 0), self.store)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = f'http://127.0.0.1:{server.server_port}'
        token = self.token.read_text().strip()
        try:
            with self.assertRaises(HTTPError) as error:
                urlopen(url + '/handshake', timeout=3)
            self.assertEqual(error.exception.code, 401)
            headers = {'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'}
            request = Request(url + '/jobs', data=json.dumps({'requestId': 'http-1', 'runId': 'run-1', 'task': 'diagnostic'}).encode(), headers=headers)
            with urlopen(request, timeout=3) as response:
                self.assertEqual(response.status, 201)
                job = json.load(response)
            self.wait(job['jobId'])
            with urlopen(Request(url + '/jobs/' + job['jobId'], headers=headers), timeout=3) as response:
                self.assertEqual(json.load(response)['status'], 'completed')
            with self.assertRaises(HTTPError) as error:
                urlopen(Request(url + '/handshake', headers={**headers, 'Origin': 'https://untrusted.example'}), timeout=3)
            self.assertEqual(error.exception.code, 401)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_public_bind_is_rejected(self):
        with self.assertRaises(ValueError):
            Server(('0.0.0.0', 0), self.store)


if __name__ == '__main__':
    unittest.main()
