"""Fixed Android-isolate checks, no model requests or host business tests.

Works with the existing hot-reload preview. The base APK is explicitly NOT
claimed to contain reloaded sources: verify the live VM's source for each file.
"""
import hashlib
import json
import urllib.parse
import urllib.request

from emulator_driver_support import ROOT, SERIAL, adb, apk_sha256, write_json

SOURCES = (
    'lib/application/artifact_result_actions.dart',
    'lib/application/artifact_service.dart',
    'lib/application/result_action_service.dart',
    'lib/presentation/artifacts/artifact_center_page.dart',
    'lib/debug/artifact_action_checks.dart',
    'lib/debug/artifact_checks.dart',
    'lib/infrastructure/database/app_database.dart',
)
REPORT = ROOT / 'local/temp/u05-file-actions-contract-20261019.json'


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        raise RuntimeError('Debug redirects denied')


class Preview:
    def __init__(self):
        assert adb('emu', 'avd', 'name').splitlines()[0] == 'Nexus_Preview_API_36'
        metadata = json.loads((ROOT / 'local/android-preview/vm-service.json').read_text())
        assert metadata['deviceId'] == SERIAL
        uri = urllib.parse.urlsplit(metadata['wsUri'])
        assert (uri.scheme == 'ws' and uri.hostname == '127.0.0.1' and
                not uri.username and not uri.password and not uri.query and
                not uri.fragment and uri.path.endswith('/ws'))
        self.base = urllib.parse.urlunsplit(('http', uri.netloc, uri.path[:-2], '', ''))
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        self.isolate = next(i['id'] for i in self.rpc('getVM')['isolates'] if i['name'] == 'main')
        libraries = self.rpc('getIsolate', isolateId=self.isolate)['libraries']
        target = next(l['id'] for l in libraries if l['uri'].endswith('/debug/artifact_checks.dart'))
        result = self.rpc('invoke', isolateId=self.isolate, targetId=target,
                          selector='registerArtifactChecks', argumentIds='[]', disableBreakpoints='true')
        assert result.get('type') not in ('Error', '@Error', 'Sentinel')

    def rpc(self, method, **params):
        with self.opener.open(self.base + method + '?' + urllib.parse.urlencode(params), timeout=getattr(self, 'rpc_timeout', 90)) as r:
            raw = r.read(4 * 1024 * 1024 + 1)
        assert len(raw) <= 4 * 1024 * 1024
        envelope = json.loads(raw)
        if 'error' in envelope:
            raise RuntimeError('Fixed debug RPC failed: ' + method)
        return envelope['result']

    def fixture(self, mode):
        assert mode in ('actions', 'close')
        return self.rpc('ext.nexus.artifactActionFixture', isolateId=self.isolate, mode=mode)

    def source_hashes(self, sources=None):
        scripts = self.rpc('getScripts', isolateId=self.isolate)['scripts']
        result = {}
        for path in SOURCES if sources is None else sources:
            suffix = '/' + path.removeprefix('lib/')
            script = next(s for s in scripts if s['uri'].endswith(suffix))
            live = self.rpc('getObject', isolateId=self.isolate, objectId=script['id'])['source']
            disk = (ROOT / path).read_text(encoding='utf-8')
            assert live.replace('\r\n', '\n') == disk.replace('\r\n', '\n'), 'Live source mismatch: ' + path
            result[path] = hashlib.sha256(disk.replace('\r\n', '\n').encode()).hexdigest()
        return result


def main():
    preview = Preview()
    source_hashes = preview.source_hashes()
    report = preview.rpc('ext.nexus.artifactActionsContract', isolateId=preview.isolate)
    cases = report.get('cases', [])
    assert (report.get('type') == 'ArtifactActionContractChecks' and
            report.get('fixtureOnly') is True and len(cases) == 34 and
            report.get('storage') == 'owned_temporary_sqlite_file' and
            all(isinstance(c.get('passed'), bool) for c in cases) and
            all(report.get(k) == 0 for k in ('modelCalls', 'platformMutations', 'persistentDataMutations')))
    assert report['total'] == len(cases) and report['passed'] == sum(c['passed'] for c in cases)
    report.update(executionTarget=SERIAL, liveSourceSha256=source_hashes,
                  baseApkSha256=apk_sha256(), runtime='existing_debug_preview_hot_reload',
                  notFinalApkSignOff=True)
    write_json(REPORT, report)
    print('Artifact action checks: %s/%s; live sources verified; no models/OS actions.' % (report['passed'], report['total']))
    for case in cases:
        if not case['passed']:
            print('FAILED: ' + case['name'])
    return 0 if report['passed'] == report['total'] else 1


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        print('Artifact action verification unavailable: ' + type(error).__name__ + '; no endpoint/auth printed.')
        raise SystemExit(2)
