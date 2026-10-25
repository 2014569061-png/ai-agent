"""Fresh regression evidence, without overwriting historical APK sign-offs."""
from emulator_driver_support import ROOT, SERIAL, apk_sha256, write_json
from verify_result_action_approval_emulator import SOURCES
from verify_personal_context_sql_emulator import ContextPreview, SOURCES as CONTEXT_SOURCES


def main():
    preview = ContextPreview()
    hashes = preview.source_hashes(tuple(dict.fromkeys(SOURCES + CONTEXT_SOURCES)))
    suites = {}
    for name, method, expected in (
            ('fileActions', 'ext.nexus.artifactActionsContract', 34),
            ('artifacts', 'ext.nexus.artifactContract', 12),
            ('personalContext', 'ext.nexus.personalContextSqlContract', 51)):
        result = preview.rpc(method, isolateId=preview.isolate)
        assert result['total'] == expected and result['fixtureOnly'] is True
        suites[name] = result
        print('%s: %s/%s' % (name, result['passed'], result['total']))
    passed = all(r['passed'] == r['total'] for r in suites.values())
    write_json(ROOT / 'local/temp/u05-result-approval-regressions-20261019.json', dict(
        passed=passed, fixtureOnly=True, executionTarget=SERIAL, modelCalls=0,
        runtime='existing_debug_preview_hot_reload', notFinalApkSignOff=True,
        baseApkSha256=apk_sha256(), liveSourceSha256=hashes, suites=suites))
    return 0 if passed else 1


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        print('Approval regressions unavailable: ' + type(error).__name__ + '; no endpoint/auth printed.')
        raise SystemExit(2)
