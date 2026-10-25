"""Owned SQLite checks on existing Android preview; never host business tests."""
from emulator_driver_support import ROOT, SERIAL, apk_sha256, write_json
from verify_artifact_actions_emulator import Preview

SOURCES = (
    'lib/application/approval_decision_scope.dart',
    'lib/application/approval_bridge.dart',
    'lib/application/run_approval_scope.dart',
    'lib/application/result_action_approval_scope.dart',
    'lib/application/result_action_service.dart',
    'lib/application/artifact_result_actions.dart',
    'lib/infrastructure/database/result_action_store.dart',
    'lib/infrastructure/database/result_action_approval_store.dart',
    'lib/domain/result_card.dart',
    'lib/presentation/widgets/tool_approval_helper.dart',
    'lib/presentation/artifacts/artifact_center_page.dart',
    'lib/infrastructure/tools/tool_humanizer.dart',
    'lib/debug/result_action_approval_checks.dart',
    'lib/debug/artifact_action_checks.dart',
    'lib/debug/artifact_checks.dart',
)
REPORT = ROOT / 'local/temp/u05-result-approval-contract-20261019.json'


class ApprovalPreview(Preview):
    def approval_fixture(self, mode):
        assert mode in ('open', 'inspect', 'change', 'cover', 'uncover', 'close')
        result = self.rpc('ext.nexus.resultApprovalFixture', isolateId=self.isolate, mode=mode)
        assert result.get('fixtureOnly') is True and result.get('modelCalls') == 0
        return result


def main():
    preview = ApprovalPreview()
    hashes = preview.source_hashes(SOURCES)
    report = preview.rpc('ext.nexus.resultApprovalContract', isolateId=preview.isolate)
    cases = report.get('cases', [])
    assert (report.get('type') == 'ResultApprovalContractChecks' and
            report.get('fixtureOnly') is True and len(cases) == 27 and
            report.get('storage') == 'owned_temporary_sqlite_file' and
            all(isinstance(c.get('passed'), bool) for c in cases) and
            all(report.get(k) == 0 for k in ('modelCalls', 'platformMutations', 'persistentDataMutations')))
    assert report['total'] == len(cases) and report['passed'] == sum(c['passed'] for c in cases)
    report.update(executionTarget=SERIAL, liveSourceSha256=hashes,
                  baseApkSha256=apk_sha256(), runtime='existing_debug_preview_hot_reload',
                  notFinalApkSignOff=True)
    write_json(REPORT, report)
    print('Result approval checks: %s/%s; live sources verified.' % (report['passed'], report['total']))
    for case in cases:
        if not case['passed']:
            print('FAILED: ' + case['name'] + ' (' + case.get('error', 'assertion') + ')')
    return 0 if report['passed'] == report['total'] else 1


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        print('Result approval verification unavailable: ' + type(error).__name__ + '; no endpoint/auth printed.')
        raise SystemExit(2)
