"""50 mobile candidate pages verified at 360dp portrait (1.6x/2.0x), Dark Theme, and 640x360 Landscape."""
from emulator_driver_support import ROOT, SERIAL, apk_sha256, write_json
from verify_artifact_actions_ui_emulator import capture
from verify_conversation_results_emulator import ConversationPreview

SCREENSHOT_PAGES = (
    'agents',
    'agent_editor',
    'skill_market',
    'dashboard',
    'run_analysis',
    'mcp_servers',
    'onboarding',
    'task_details',
    'session_workbench',
    'development_workbench',
    'data_management',
    'device_backups',
    'device_capabilities',
    'terminal',
)

DARK_LANDSCAPE_SCREENSHOT_PAGES = (
    'dashboard',
    'onboarding',
    'history',
    'jobs_inbox',
    'knowledge',
    'memory',
    'settings',
    'artifact_center',
)


def main():
    p = ConversationPreview()
    p.rpc('ext.nexus.conversationResultsContract', isolateId=p.isolate)
    meta = p.rpc('ext.nexus.pageCoverageUi', isolateId=p.isolate, mode='list')
    pages = meta['pages']
    report = dict(
        passed=False,
        fixtureOnly=True,
        executionTarget=SERIAL,
        modelCalls=0,
        realUserDataMutations=0,
        runtime='existing_debug_preview_hot_reload',
        notFinalApkSignOff=True,
        baseApkSha256=apk_sha256(),
        totalPages=len(pages),
        passedPages16x=0,
        passedPages20x=0,
        passedPagesDark16x=0,
        passedPagesLandscapeDark16x=0,
        results=[],
    )
    opened = False
    try:
        p.rpc('ext.nexus.pageCoverageUi', isolateId=p.isolate, mode='open')
        opened = True
        for key in pages:
            r16 = p.rpc('ext.nexus.pageCoverageUi', isolateId=p.isolate,
                        mode='show', page=key, width='360', height='0', scale='1.6', dark='false')
            if key in SCREENSHOT_PAGES:
                capture(f'major-page-coverage-{key}-360w-16x-20261019.png')
            r20 = p.rpc('ext.nexus.pageCoverageUi', isolateId=p.isolate,
                        mode='show', page=key, width='360', height='0', scale='2.0', dark='false')
            rdark = p.rpc('ext.nexus.pageCoverageUi', isolateId=p.isolate,
                          mode='show', page=key, width='360', height='0', scale='1.6', dark='true')
            if key in DARK_LANDSCAPE_SCREENSHOT_PAGES:
                capture(f'major-page-coverage-{key}-dark-360w-16x-20261019.png')
            rland = p.rpc('ext.nexus.pageCoverageUi', isolateId=p.isolate,
                          mode='show', page=key, width='640', height='360', scale='1.6', dark='true')
            if key in DARK_LANDSCAPE_SCREENSHOT_PAGES:
                capture(f'major-page-coverage-{key}-landscape-640x360-dark-16x-20261019.png')

            ok16 = r16.get('uiErrors', 0) == 0
            ok20 = r20.get('uiErrors', 0) == 0
            okdark = rdark.get('uiErrors', 0) == 0
            okland = rland.get('uiErrors', 0) == 0
            if ok16:
                report['passedPages16x'] += 1
            if ok20:
                report['passedPages20x'] += 1
            if okdark:
                report['passedPagesDark16x'] += 1
            if okland:
                report['passedPagesLandscapeDark16x'] += 1
            report['results'].append({
                'page': key,
                'ok16x': ok16,
                'ok20x': ok20,
                'okDark16x': okdark,
                'okLandscapeDark16x': okland,
                'errors16x': r16.get('errors', []),
                'errors20x': r20.get('errors', []),
                'errorsDark16x': rdark.get('errors', []),
                'errorsLandscapeDark16x': rland.get('errors', []),
            })
            if not (ok16 and ok20 and okdark and okland):
                print(
                    f"OVERFLOW/ERROR on {key}: 1.6x={r16.get('errors')} "
                    f"2.0x={r20.get('errors')} dark={rdark.get('errors')} "
                    f"landscape={rland.get('errors')}"
                )
        report['passed'] = (
            report['passedPages16x'] == len(pages)
            and report['passedPages20x'] == len(pages)
            and report['passedPagesDark16x'] == len(pages)
            and report['passedPagesLandscapeDark16x'] == len(pages)
        )
    finally:
        if opened:
            p.rpc('ext.nexus.pageCoverageUi', isolateId=p.isolate, mode='close')
        write_json(ROOT / 'local/temp/major-page-coverage-ui-20261019.json', report)
    print(
        f"Page coverage UI: 1.6x={report['passedPages16x']}/{len(pages)}, "
        f"2.0x={report['passedPages20x']}/{len(pages)}, "
        f"dark1.6x={report['passedPagesDark16x']}/{len(pages)}, "
        f"landscapeDark1.6x={report['passedPagesLandscapeDark16x']}/{len(pages)}"
    )
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
