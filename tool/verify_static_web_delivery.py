"""Exercise the fixed, isolated web delivery UI on the configured emulator."""
import hashlib
import json
from pathlib import Path
import subprocess
import urllib.parse
import urllib.request

from emulator_contract_support import NoRedirect, VerificationFailure, contract_main


def main():
    root = Path(__file__).resolve().parents[1]
    out = root / 'local/temp/mobile-dev-20261021'
    out.mkdir(parents=True, exist_ok=True)
    metadata = json.loads((root / 'local/android-preview/vm-service.json').read_text(encoding='utf-8'))
    device = metadata.get('deviceId')
    if device != 'emulator-5554':
        raise VerificationFailure('The configured preview emulator is required')
    adb = root / 'local/android-sdk/platform-tools/adb.exe'
    avd = subprocess.check_output([str(adb), '-s', device, 'emu', 'avd', 'name'], text=True)
    if avd.splitlines()[0].strip() != 'Nexus_Preview_API_36':
        raise VerificationFailure('Unexpected emulator')
    uri = urllib.parse.urlsplit(metadata['wsUri'])
    if (uri.scheme != 'ws' or uri.hostname != '127.0.0.1' or uri.username or
            uri.password or uri.query or uri.fragment or not uri.path.endswith('/ws')):
        raise VerificationFailure('Invalid preview endpoint')
    base = urllib.parse.urlunsplit(('http', uri.netloc, uri.path[:-2], '', ''))
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())

    def rpc(method, **params):
        url = base + method + ('?' + urllib.parse.urlencode(params) if params else '')
        with opener.open(url, timeout=35) as response:
            data = response.read(2 * 1024 * 1024 + 1)
        if len(data) > 2 * 1024 * 1024:
            raise VerificationFailure('Response exceeds budget')
        envelope = json.loads(data)
        if envelope.get('error'):
            raise VerificationFailure('Fixed UI RPC failed')
        return envelope['result']

    vm = rpc('getVM')
    isolate = next(row['id'] for row in vm['isolates'] if row['name'] == 'main')

    def ui(mode, **params):
        return rpc('ext.nexus.pageCoverageUi', isolateId=isolate, mode=mode, **params)

    def hashes():
        return {str(file.relative_to(root)).replace('\\', '/'): hashlib.sha256(file.read_bytes()).hexdigest()
                for file in sorted((root / 'lib').rglob('*.dart'))}

    before = hashes()
    report = {'fixtureOnly': True, 'modelCalls': 0, 'executionTarget': device,
              'notReleaseSignOff': True, 'sourceSha256': before, 'ui': [], 'passed': False}
    opened = False
    try:
        opened = ui('open').get('opened') is True
        if not opened:
            raise VerificationFailure('Isolated fixture did not open')
        for width, height, scale, dark in [('360', '800', '1.6', 'false'),
                                          ('360', '800', '2.0', 'false'),
                                          ('360', '800', '1.6', 'true'),
                                          ('640', '360', '1.6', 'true')]:
            result = ui('show', page='static_web_delivery', width=width, height=height,
                        scale=scale, dark=dark, waitMs='700')
            result['passed'] = result.get('uiErrors') == 0 and result.get('errors') == []
            report['ui'].append(result)
            with (out / f'web-delivery-{width}w-{scale}x-{dark}.png').open('wb') as capture:
                subprocess.run([str(adb), '-s', device, 'exec-out', 'screencap', '-p'],
                               stdout=capture, check=True, timeout=15)
            if not result['passed']:
                raise VerificationFailure('Mobile layout failed')
        ui('show', page='static_web_delivery', width='360', height='800', scale='1.0',
           dark='false', waitMs='700')
        saved = ui('web_delivery_save')
        report['delivery'] = saved
        if (saved.get('saved') is not True or saved.get('artifactCount') != 1 or
                saved.get('archiveEntries') != ['index.html', 'styles.css'] or saved.get('uiErrors') != 0):
            raise VerificationFailure('Verified archive delivery failed')
        report['passed'] = True
    except Exception as error:
        report['errorType'] = type(error).__name__
    finally:
        if opened:
            try:
                ui('close')
            except Exception:
                report['cleanupFailed'] = True
                report['passed'] = False
        report['sourcesUnchanged'] = hashes() == before
        report['passed'] = report['passed'] and report['sourcesUnchanged']
        (out / 'emulator-web-delivery.json').write_text(
            json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f"Web delivery emulator: {len(report['ui'])}/4 layouts; "
          f"saved={report.get('delivery', {}).get('saved', False)}; passed={report['passed']}")
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(contract_main(main))
