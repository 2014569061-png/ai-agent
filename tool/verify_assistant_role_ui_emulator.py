"""Real Android assistant selection/session checks on the approved emulator.

No audio, model calls, user chat writes or external sends. Restore the original
emulator assistant/recognizer settings even if verification fails.
"""
import json
import hashlib
import traceback
import urllib.parse
import urllib.request
from pathlib import Path
from launch_emulator_debug import adb, SERIAL
from launch_emulator_debug import main as launch_debug
from verify_speech_capture_ui_emulator import tap, visible, nodes, capture
import emulator_driver_support as support

ROOT = Path(__file__).resolve().parents[1]
ROLE = 'android.app.role.ASSISTANT'
PACKAGE = 'com.nexusagent.app.debug'


def rpc(mode='inspect'):
    metadata = json.loads((ROOT / 'local/android-preview/vm-service.json').read_text())
    assert metadata['deviceId'] == SERIAL
    uri = urllib.parse.urlsplit(metadata['wsUri'])
    assert (uri.scheme == 'ws' and uri.hostname == '127.0.0.1' and
            not uri.username and not uri.password and not uri.query and not uri.fragment)
    base = urllib.parse.urlunsplit(('http', uri.netloc, uri.path[:-2], '', ''))

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args):
            raise RuntimeError('Redirect denied')

    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())

    def vm(method, **params):
        with opener.open(base + method + '?' + urllib.parse.urlencode(params), timeout=30) as response:
            envelope = json.load(response)
        assert 'error' not in envelope
        return envelope['result']

    isolate = next(i['id'] for i in vm('getVM')['isolates'] if i['name'] == 'main')
    result = vm('ext.nexus.assistantRoleFixture', isolateId=isolate, mode=mode)
    assert result['type'] == 'AssistantRoleUiStatus'
    return result


# snapshot()/restore() now also carry the runtime permissions this round may
# change (a role grant can hand the app RECORD_AUDIO); see
# tool/emulator_driver_support.py for why the naive restore was wrong.
snapshot = support.snapshot
restore = support.restore


def current_pid():
    try:
        return adb('shell', 'pidof', PACKAGE)
    except RuntimeError:
        return None


def main():
    assert adb('emu', 'avd', 'name').splitlines()[0] == 'Nexus_Preview_API_36'
    previous = snapshot()
    support.write_json(ROOT / 'local/temp/major-assistant-role-before-20261019.json', previous)
    report = {'executionTarget': SERIAL, 'modelCalls': 0, 'realAudioStarted': False,
              'contextCaptured': False, 'originalDeviceStateRestored': False,
              'permissionBaseline': {name: state['granted'] for name, state in previous['permissions'].items()},
              'apkSha256': hashlib.sha256((ROOT / 'build/app/outputs/flutter-apk/app-debug.apk').read_bytes()).hexdigest()}
    try:
        support.ensure_debug_app(lambda: rpc('inspect'))
        before = rpc('open')['status']
        assert before['supported'] and not before['connected']
        assert visible('尚未选择 NEXUS')
        capture('major-assistant-role-unselected-20261019.png')
        tap('选择默认助手')
        assert not rpc()['status']['connected']
        adb('shell', 'input', 'keyevent', 'KEYCODE_BACK')
        assert visible('尚未选择 NEXUS')
        report['chooserCancelDoesNotGrant'] = True
        tap('选择默认助手')
        tap('Default digital assistant app')
        tap('NEXUS Debug')
        # Android's role request dialog may include a final affirmative button.
        labels = {n.get('text', '') for n in nodes()}
        for label in ['Use app', 'Set default', 'Allow', 'OK', '使用应用', '设为默认', '允许', '确定']:
            if label in labels:
                tap(label)
                break
        for _ in range(4):
            if visible('默认系统助手'):
                break
            adb('shell', 'input', 'keyevent', 'KEYCODE_BACK')
        tap('刷新状态')
        selected = rpc()['status']
        assert selected['roleHeld'] and selected['selected'] and selected['active'] and selected['ready'] and selected['connected']
        assert visible('系统助手已激活')
        assert not selected['contextCollection'] and not selected['backgroundMicrophone'] and not selected['hotword']
        capture('major-assistant-role-active-20261019.png')
        report['selected'] = selected
        tap('检查系统唤起')
        assert visible('NEXUS 系统助手') and visible('打开助手')
        tap('关闭')
        adb('shell', 'input', 'keyevent', 'KEYCODE_ASSIST')
        assert visible('NEXUS 系统助手')
        tap('打开助手')
        assert not visible('NEXUS 系统助手')
        report['realSessionAndSystemAssistKey'] = True
        report['explicitOpenPreservesCoveredRoute'] = rpc()['routeOpen']
        assert report['explicitOpenPreservesCoveredRoute']
        # Revoke using the OS role API, then verify the production page reads it.
        previous_pid = current_pid()
        adb('shell', 'cmd', 'role', 'remove-role-holder', ROLE, PACKAGE)
        # Revoking role-granted runtime permissions can kill the app. Reconnect
        # to the new real process instead of reading an obsolete isolate URL.
        if current_pid() != previous_pid:
            launch_debug()
            rpc('open')
            report['revocationRestartedProcess'] = True
        tap('刷新状态')
        revoked = rpc()['status']
        assert not revoked['roleHeld'] and not revoked['connected']
        assert visible('尚未选择 NEXUS')
        report['revoked'] = revoked
        report['passed'] = True
    finally:
        try:
            if current_pid():
                route_pid = current_pid()
                try:
                    rpc('close')
                except Exception:
                    # A killed process owns no live fixture route.
                    assert current_pid() != route_pid, 'Owned route cleanup failed in a live process'
                    report['routeCleanupInterruptedByProcessExit'] = True
        finally:
            try:
                report['restore'] = restore(previous)
                report['originalDeviceStateRestored'] = True
                support.ensure_debug_app(lambda: rpc('inspect'))
                report['appAliveAfterRestore'] = True
            finally:
                support.write_json(ROOT / 'local/temp/major-assistant-role-ui-20261019.json', report)
    print('Real assistant role UI/session/assist key/revocation passed; original emulator settings and runtime '
          'permissions restored from a pre-round baseline; no audio/model.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        line = traceback.extract_tb(error.__traceback__)[-1].lineno
        print('Assistant role UI verification failed: ' + type(error).__name__ +
              ' at driver line ' + str(line) + '; endpoint/private UI not printed.')
        raise SystemExit(1)
