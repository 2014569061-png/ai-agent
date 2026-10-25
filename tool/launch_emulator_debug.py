"""Launch only the existing approved emulator; never discover/query real devices.
No ADB start/kill-server, disconnect, reverse, permission grant or data clear.
"""
from pathlib import Path
import json
import re
import subprocess
import time
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]
ADB = str(ROOT / 'local/android-sdk/platform-tools/adb.exe')
SERIAL = 'emulator-5554'

def adb(*args):
    result = subprocess.run([ADB, '-s', SERIAL, *args], cwd=ROOT,
                            capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=30)
    if result.returncode:
        raise RuntimeError('Emulator ADB operation failed')
    return result.stdout.strip()

def main():
    if adb('emu', 'avd', 'name').splitlines()[0] != 'Nexus_Preview_API_36':
        raise RuntimeError('Approved emulator mismatch')
    adb('shell', 'am', 'start', '-W', '-n', 'com.nexusagent.app.debug/com.nexusagent.app.MainActivity')
    pid = adb('shell', 'pidof', 'com.nexusagent.app.debug')
    if not re.fullmatch(r'\d+', pid):
        raise RuntimeError('Expected one debug app process')
    matches = []
    for _ in range(30):
        # Role permission revocation may finish the old process after start -W.
        # Reconnect only to this approved package's current process.
        try:
            live_pid = adb('shell', 'pidof', 'com.nexusagent.app.debug')
        except RuntimeError:
            live_pid = ''
        if live_pid != pid:
            adb('shell', 'am', 'start', '-W', '-n', 'com.nexusagent.app.debug/com.nexusagent.app.MainActivity')
            pid = adb('shell', 'pidof', 'com.nexusagent.app.debug')
            if not re.fullmatch(r'\d+', pid):
                raise RuntimeError('Expected one restarted debug process')
        logs = adb('logcat', '-d', '--pid=' + pid, '-v', 'raw', '-s', 'flutter')
        matches = re.findall(r'Dart VM service is listening on (http://127\.0\.0\.1:\d+/[^\s]+)', logs)
        if matches:
            time.sleep(0.2)
            try:
                if adb('shell', 'pidof', 'com.nexusagent.app.debug') == pid:
                    break
            except RuntimeError:
                pass
            matches = []
        time.sleep(0.2)
    if not matches:
        raise RuntimeError('No local emulator VM metadata; launch is preserved')
    uri = urllib.parse.urlsplit(matches[-1])
    if not uri.path.endswith('/') or uri.query or uri.fragment:
        raise RuntimeError('Unexpected debug endpoint')
    port = adb('forward', 'tcp:0', 'tcp:' + str(uri.port))
    if not re.fullmatch(r'\d+', port):
        raise RuntimeError('Invalid emulator debug forwarding result')
    target = ROOT / 'local/android-preview/vm-service.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps({'deviceId': SERIAL, 'appPid': pid,
        'forwardPort': int(port),
        'wsUri': urllib.parse.urlunsplit(('ws', '127.0.0.1:' + port, uri.path + 'ws', '', ''))}))
    print('Approved emulator debug app launched. Local VM metadata saved; endpoint/auth not printed.')

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Emulator launch metadata unavailable: ' + type(error).__name__ + '; no private log or endpoint printed.')
        raise SystemExit(1)
