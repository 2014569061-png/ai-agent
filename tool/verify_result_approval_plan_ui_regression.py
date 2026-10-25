"""Existing production plan approvals still revoke/grant only their own scope."""
from emulator_driver_support import ROOT, SERIAL, apk_sha256, write_json
from verify_personal_context_sql_emulator import ContextPreview
from verify_result_action_approval_emulator import SOURCES
from verify_artifact_actions_ui_emulator import nodes, label, tap, text_present, capture


def main():
    preview = ContextPreview()
    report = dict(passed=False, fixtureOnly=True, modelCalls=0, externalActions=0,
                  executionTarget=SERIAL, baseApkSha256=apk_sha256(),
                  runtime='existing_debug_preview_hot_reload', notFinalApkSignOff=True,
                  liveSourceSha256=preview.source_hashes(SOURCES), checks=[])
    def action(mode):
        result = preview.rpc('ext.nexus.approvalScopeFixture', isolateId=preview.isolate, mode=mode)
        assert result['fixtureOnly'] and result['modelCalls'] == result['externalActions'] == 0
        return result
    opened = False
    try:
        action('open')
        opened = True
        text_present('隔离验收 · 持久审批')
        tap('打开隔离审批')
        text_present('本计划允许')
        action('cover')
        text_present('隔离遮盖层')
        action('correct')
        text_present('隔离遮盖层')
        action('uncover')
        text_present('隔离审批状态：reject')
        assert not any('本计划允许' in label(n) for n in nodes())
        stale = action('inspect')
        assert stale['pendingRows'] == stale['scopeRows'] == stale['planGrantRows'] == 0
        report['checks'].append('plan_invalidation_removes_only_owned_route')
        tap('打开隔离审批')
        text_present('本计划允许')
        tap('本计划允许')
        text_present('隔离审批状态：allowSession')
        granted = action('inspect')
        assert granted['planTrusted'] and granted['planGrantRows'] == 1
        assert granted['globalSessionGrants'] == granted['globalPersistentGrants'] == 0
        action('correct')
        revoked = action('inspect')
        assert not revoked['planTrusted'] and revoked['planVersion'] == 3
        capture('u05-approval-plan-regression-20261019.png')
        report['checks'].append('plan_only_grant_and_correction_revocation_unchanged')
        report.update(passed=True, invalidated=stale, granted=granted, revoked=revoked)
    finally:
        if opened:
            action('close')
        write_json(ROOT / 'local/temp/u05-approval-plan-ui-regression-20261019.json', report)
    print('Production plan approval UI regression: 2/2; no device settings changed.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Plan approval UI regression failed: ' + type(error).__name__ + '; no endpoint/auth printed.')
        raise SystemExit(1)
