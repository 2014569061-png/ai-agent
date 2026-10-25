"""Fixed on-emulator SQLite checks. No real user DB, models, or host test suite."""
from emulator_driver_support import ROOT, SERIAL, apk_sha256, write_json
from verify_artifact_actions_emulator import Preview

SOURCES = (
    'lib/application/personal_context_service.dart',
    'lib/infrastructure/database/personal_context_store.dart',
    'lib/infrastructure/database/app_database.dart',
    'lib/domain/personal_context.dart',
    'lib/presentation/settings/personal_context_page.dart',
    'lib/debug/personal_context_checks.dart',
    'lib/debug/personal_context_sql_checks.dart',
    'lib/debug/plan_protocol_checks.dart',
    'lib/infrastructure/files/vault_exporter_io.dart',
)
REPORT = ROOT / 'local/temp/u04-personal-context-sql-20261019.json'


class ContextPreview(Preview):
    def __init__(self):
        super().__init__()
        libraries = self.rpc('getIsolate', isolateId=self.isolate)['libraries']
        target = next(l['id'] for l in libraries if l['uri'].endswith('/debug/plan_protocol_checks.dart'))
        result = self.rpc('invoke', isolateId=self.isolate, targetId=target,
                          selector='registerPlanProtocolChecks', argumentIds='[]', disableBreakpoints='true')
        assert result.get('type') not in ('Error', '@Error', 'Sentinel')

    def context_fixture(self, mode):
        assert mode in ('open', 'inspect', 'close')
        result = self.rpc('ext.nexus.personalContextSqlFixture', isolateId=self.isolate, mode=mode)
        assert result.get('fixtureOnly') is True and result.get('modelCalls') == 0
        return result


def main():
    preview = ContextPreview()
    hashes = preview.source_hashes(SOURCES)
    report = preview.rpc('ext.nexus.personalContextSqlContract', isolateId=preview.isolate)
    cases = report.get('cases', [])
    assert (report.get('type') == 'PersonalContextSqlContractChecks' and
            report.get('fixtureOnly') is True and len(cases) == 51 and
            report.get('storage') == 'owned_temporary_sqlite_file' and
            all(isinstance(c.get('passed'), bool) for c in cases) and
            all(report.get(k) == 0 for k in ('modelCalls', 'platformMutations', 'persistentDataMutations')))
    assert report['total'] == len(cases) and report['passed'] == sum(c['passed'] for c in cases)
    report.update(executionTarget=SERIAL, liveSourceSha256=hashes,
                  baseApkSha256=apk_sha256(), runtime='existing_debug_preview_hot_reload',
                  notFinalApkSignOff=True)
    write_json(REPORT, report)
    print('Personal context SQLite checks: %s/%s; live sources verified; no models/OS actions.' % (report['passed'], report['total']))
    for case in cases:
        if not case['passed']:
            print('FAILED: ' + case['name'] + ' (' + case.get('error', 'assertion') + ')')
    return 0 if report['passed'] == report['total'] else 1


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        print('Context verification unavailable: ' + type(error).__name__ + '; no endpoint/auth printed.')
        raise SystemExit(2)
