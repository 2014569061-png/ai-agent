"""Actual shared approval sheet + Android sharesheet; isolated synthetic files."""
from emulator_driver_support import ROOT, SERIAL, adb, apk_sha256, write_json
from verify_result_action_approval_emulator import ApprovalPreview, SOURCES
from verify_artifact_actions_ui_emulator import nodes, label, tap as tap_control, text_present, wait_for, capture

REPORT = ROOT / 'local/temp/u05-result-approval-ui-20261019.json'


def tap(text, contains=False):
    # A VM-side SQL batch can delay Flutter animation frames while UIAutomator
    # already exposes moving button bounds. Never retry a side-effectful tap;
    # wait for two stable observations before issuing exactly one input event.
    previous = None
    def stable(rows):
        nonlocal previous
        bounds = [n.get('bounds') for n in rows
                  if n.get('clickable') == 'true' and n.get('enabled') == 'true'
                  and (text in label(n) if contains else text == label(n))]
        settled = bool(bounds) and bounds == previous
        previous = bounds
        return settled
    wait_for(stable)
    tap_control(text, contains=contains)


def pending_share():
    tap('分享文件')
    text_present('需要确认后才能执行')
    tap('确认执行')
    rows = text_present('把文件交给系统分享（仅本次）')
    assert not any(any(t in label(n) for t in ('本会话允许', '始终允许', '本计划允许')) for n in rows)


def main():
    preview = ApprovalPreview()
    report = dict(passed=False, fixtureOnly=True, executionTarget=SERIAL,
                  modelCalls=0, recipientsChosen=0, realUserDataMutations=0,
                  runtime='existing_debug_preview_hot_reload', notFinalApkSignOff=True,
                  baseApkSha256=apk_sha256(), liveSourceSha256=preview.source_hashes(SOURCES), checks=[])
    opened = False
    try:
        preview.approval_fixture('open')
        opened = True
        text_present('隔离验收 · 结果审批')
        tap('ScopeShare.txt\n文件', contains=True)
        text_present('结果卡详情')
        pending_share()
        meta = preview.approval_fixture('inspect')
        assert meta['pending'] == 1 and meta['planGrants'] == 0
        capture('u05-result-approval-sheet-20261019.png')
        tap('拒绝')
        text_present('审批已拒绝')
        meta = preview.approval_fixture('inspect')
        assert meta['pending'] == 0 and all(a['attempts'] == 0 for a in meta['actions'])
        report['checks'].append('shared_one_time_sheet_reject_no_execution_no_grants')

        tap('重试分享文件')
        text_present('需要确认后才能执行')
        tap('确认执行')
        text_present('把文件交给系统分享（仅本次）')
        tap('确认执行')
        wait_for(lambda rows: any(n.get('package') == 'com.android.intentresolver'
                 and n.get('resource-id', '').endswith('content_preview_filename')
                 and label(n) == 'ScopeShare.txt' for n in rows))
        capture('u05-result-approval-sharesheet-20261019.png')
        adb('shell', 'input', 'keyevent', '4')
        text_present('已取消系统分享，未确认交付')
        meta = preview.approval_fixture('inspect')
        assert meta['pending'] == 0 and meta['planGrants'] == 0
        assert sum(a['attempts'] for a in meta['actions']) == 1
        assert not any(a['status'] == 'succeeded' for a in meta['actions'])
        report['checks'].append('persisted_approval_dispatches_real_sharesheet_dismissal_not_success')

        tap('重试分享文件')
        text_present('需要确认后才能执行')
        tap('确认执行')
        text_present('把文件交给系统分享（仅本次）')
        preview.approval_fixture('cover')
        text_present('隔离遮盖层 · 结果审批')
        preview.approval_fixture('change')
        # The invalidated approval route must remove ITSELF, not the top route.
        text_present('隔离遮盖层 · 结果审批')
        preview.approval_fixture('uncover')
        text_present('审批期间资源已变化')
        assert not any('把文件交给系统分享（仅本次）' in label(n) for n in nodes())
        meta = preview.approval_fixture('inspect')
        assert meta['pending'] == 0 and sum(a['attempts'] for a in meta['actions']) == 1
        capture('u05-result-approval-stale-20261019.png')
        report['checks'].append('resource_change_removes_only_owned_approval_route_under_cover')

        result = preview.approval_fixture('close')
        opened = False
        assert result['pendingAfterClose'] == 0
        preview.approval_fixture('open')
        opened = True
        text_present('隔离验收 · 结果审批')
        tap('ScopeShare.txt\n文件', contains=True)
        text_present('结果卡详情')
        pending_share()
        result = preview.approval_fixture('close')
        opened = False
        assert result['pendingAfterClose'] == 0
        rows = wait_for(lambda rows: not any('把文件交给系统分享（仅本次）' in label(n) for n in rows))
        assert not any(n.get('package') == 'com.android.intentresolver' for n in rows)
        report['checks'].append('page_disposal_cleans_pending_and_owned_root_sheet_without_dispatch')
        report['passed'] = True
    except Exception as error:
        report['failure'] = type(error).__name__
        capture('u05-result-approval-failure-20261019.png')
        raise
    finally:
        if opened:
            if any(n.get('package') == 'com.android.intentresolver' for n in nodes()):
                adb('shell', 'input', 'keyevent', '4')
            preview.approval_fixture('close')
        write_json(REPORT, report)
    print('Result approval UI: 4/4 scenarios passed; no recipients or model calls.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Result approval UI failed: ' + type(error).__name__ + '; no endpoint/auth printed.')
        raise SystemExit(1)
