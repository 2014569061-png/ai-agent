"""Local debug-VM inspection for isolated on-device UI acceptance fixtures.

Connects only to the named emulator's existing debug app and ADB forwarding.
It does not restart the app, change its real database, or make model calls.
"""
import json
import subprocess
import time
import urllib.parse
import urllib.request

from mobile_ui_probe import ADB, EVIDENCE


class VM:
    def __init__(self, serial='emulator-5554'):
        def adb(*args):
            return subprocess.check_output([str(ADB), '-s', serial, *args], timeout=20).decode('utf-8', errors='replace')
        if adb('shell', 'getprop', 'ro.kernel.qemu').strip() != '1':
            raise RuntimeError('A debug emulator is required.')
        if adb('emu', 'avd', 'name').splitlines()[0] != 'Nexus_Preview_API_36':
            raise RuntimeError('Unexpected emulator.')
        pid = adb('shell', 'pidof', 'com.nexusagent.app.debug').strip()
        if not pid.isdigit():
            raise RuntimeError('Expected one running debug app.')
        lines = adb('logcat', '-d', '--pid=' + pid, '-s', 'flutter').splitlines()
        urls = [line.split('listening on ', 1)[1].strip() for line in lines
                if 'Dart VM service is listening on ' in line]
        if not urls:
            raise RuntimeError('Debug service discovery is unavailable; do not restart the preview.')
        parsed = urllib.parse.urlsplit(urls[-1])
        self.device_uri = urls[-1]
        if parsed.hostname != '127.0.0.1' or parsed.scheme != 'http':
            raise RuntimeError('Only loopback debug services are allowed.')
        forwards = [line.split() for line in adb('forward', '--list').splitlines()]
        matching = [f for f in forwards if len(f) == 3 and f[0] == serial and f[2] == 'tcp:' + str(parsed.port)]
        if not matching:
            raise RuntimeError('Use the preview existing ADB forwarding; none was found.')
        port = matching[0][1].split(':')[1]
        self.base = 'http://127.0.0.1:' + port + parsed.path
        isolates = self.call('getVM')['isolates']
        self.isolate = next(i['id'] for i in isolates if i['name'] == 'main')
        self.metadata = self.call('getIsolate', isolateId=self.isolate)
        self.libraries = self.metadata['libraries']

    def call(self, method, **arguments):
        encoded = {key: json.dumps(value) if isinstance(value, (dict, list, bool)) else str(value)
                   for key, value in arguments.items()}
        url = self.base + method + '?' + urllib.parse.urlencode(encoded)
        with urllib.request.urlopen(url, timeout=20) as response:
            result = json.load(response)
        if 'error' in result:
            raise RuntimeError(json.dumps(result['error'], ensure_ascii=False))
        return result['result']

    def library(self, suffix):
        found = [lib for lib in self.libraries if lib['uri'] == suffix or lib['uri'].endswith('/' + suffix)]
        if len(found) != 1:
            raise RuntimeError('Library must match exactly once: ' + suffix)
        return found[0]['id']

    def invoke_fixture(self, action):
        allowed = {'openMobileResultFixture', 'verifyDebugOnly', 'openMobileProjectFixture', 'openMobileChatFixture',
                   'openMobileApprovalFixture', 'openMobileTerminalFixture',
                   'setMobileFixtureDark', 'setMobileFixtureLight', 'mobileUiFixtureStatus',
                   'closeMobileUiFixture', 'scrollMobileChatToEnd', 'startMobileChatStreamingFixture',
                   'showMobileProjectFixture', 'openMobileEditorFixture',
                   'openMobileLargeFileFixture', 'resetMobileFixtureTimings',
                   'unfocusMobileFixtureInputs', 'openMobileSshFailureFixture',
                   'openMobileSshDisconnectedFixture'}
        if action not in allowed:
            raise ValueError('Only explicit isolated-fixture actions are allowed.')
        ref = self.call('invoke', isolateId=self.isolate,
                        targetId=self.library('debug/mobile_ui_acceptance.dart'),
                        selector=action, argumentIds=[], disableBreakpoints=True)
        if ref.get('type') in ('@Error', 'Error', 'Sentinel'):
            raise RuntimeError(json.dumps(ref, ensure_ascii=False))
        if '_Future' in ref.get('class', {}).get('name', ''):
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                obj = self.call('getObject', isolateId=self.isolate, objectId=ref['id'])
                fields = {f['decl']['name']: f['value'] for f in obj.get('fields', [])}
                state = int(fields.get('_state', {}).get('valueAsString', '0'))
                if state & 8:
                    ref = fields['_resultOrListeners']
                    break
                if state & 16:
                    raise RuntimeError('Unexpected unhandled debug future: ' + json.dumps(fields))
                time.sleep(0.05)
            else:
                raise TimeoutError('Debug expression did not finish within 15 seconds.')
        if ref.get('kind') == 'String' and ref.get('valueAsStringIsTruncated'):
            ref = self.call('getObject', isolateId=self.isolate, objectId=ref['id'],
                            offset=0, count=ref['length'])
        if str(ref.get('valueAsString', '')).startswith('#MCP_UI_ERROR#'):
            raise RuntimeError(ref['valueAsString'])
        return ref


if __name__ == '__main__':
    vm = VM()
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    (EVIDENCE / 'vm-metadata.json').write_text(json.dumps(vm.metadata), encoding='utf-8')
    for lib in vm.libraries:
        if any(name in lib['uri'] for name in ['project_home_page.dart', 'chat_page.dart', 'app_database.dart', 'native.dart', 'workspace_git_page.dart']):
            print(json.dumps(lib, ensure_ascii=False))
