"""New independent evidence; do not overwrite historical approval/APK reports."""
from emulator_driver_support import ROOT, SERIAL, apk_sha256, write_json
from verify_conversation_results_emulator import SOURCES
from verify_personal_context_sql_emulator import ContextPreview, SOURCES as CONTEXT_SOURCES


def main():
    p = ContextPreview()
    p.rpc_timeout = 240
    sources = tuple(dict.fromkeys(SOURCES + CONTEXT_SOURCES))
    hashes = p.source_hashes(sources)
    suites = {}
    for name, method, expected in (
            ('approval', 'ext.nexus.resultApprovalContract', 27),
            ('fileActions', 'ext.nexus.artifactActionsContract', 34),
            ('artifacts', 'ext.nexus.artifactContract', 12),
            ('personalContext', 'ext.nexus.personalContextSqlContract', 51)):
        result = p.rpc(method, isolateId=p.isolate)
        assert result['total'] == expected and result['fixtureOnly'] is True
        suites[name] = result
        print('%s: %s/%s' % (name, result['passed'], result['total']), flush=True)
    assert p.source_hashes(sources) == hashes
    passed = all(r['passed'] == r['total'] for r in suites.values())
    write_json(ROOT / 'local/temp/u05-conversation-results-regressions-20261019.json', dict(
        passed=passed, fixtureOnly=True, executionTarget=SERIAL, modelCalls=0,
        runtime='existing_debug_preview_hot_reload', notFinalApkSignOff=True,
        baseApkSha256=apk_sha256(), liveSourceSha256=hashes, suites=suites))
    return 0 if passed else 1


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        print('Conversation regressions unavailable: ' + type(error).__name__ + '; no endpoint/auth printed.')
        raise SystemExit(2)
