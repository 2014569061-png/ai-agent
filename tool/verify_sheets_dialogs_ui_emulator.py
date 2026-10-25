"""10 interactive sheets & dialogs verified at 360dp (1.6x/2.0x), Dark Theme, and 640x360 Landscape."""
from emulator_driver_support import ROOT, SERIAL, apk_sha256, write_json
from verify_artifact_actions_ui_emulator import capture
from verify_conversation_results_emulator import ConversationPreview

SCREENSHOT_SHEETS = (
    'confirm_danger_dialog',
    'action_sheet',
    'tool_approval_sheet',
    'device_action_confirm_sheet',
    'session_metrics_sheet',
    'input_tool_grid_sheet',
)


def main():
    p = ConversationPreview()
    p.rpc('ext.nexus.conversationResultsContract', isolateId=p.isolate)
    meta = p.rpc('ext.nexus.pageCoverageUi', isolateId=p.isolate, mode='list')
    sheets = meta['sheets']
    report = dict(
        passed=False,
        fixtureOnly=True,
        executionTarget=SERIAL,
        modelCalls=0,
        realUserDataMutations=0,
        runtime='existing_debug_preview_hot_reload',
        notFinalApkSignOff=True,
        baseApkSha256=apk_sha256(),
        totalSheets=len(sheets),
        passed16x=0,
        passed20x=0,
        passedDark16x=0,
        passedLandscapeDark16x=0,
        results=[],
    )
    opened = False
    try:
        p.rpc('ext.nexus.pageCoverageUi', isolateId=p.isolate, mode='open')
        opened = True
        for key in sheets:
            r16 = p.rpc('ext.nexus.pageCoverageUi', isolateId=p.isolate,
                        mode='sheet', sheet=key, width='360', height='0', scale='1.6', dark='false', waitMs='350')
            if key in SCREENSHOT_SHEETS:
                capture(f'major-sheet-coverage-{key}-360w-16x-20261019.png')
            r20 = p.rpc('ext.nexus.pageCoverageUi', isolateId=p.isolate,
                        mode='sheet', sheet=key, width='360', height='0', scale='2.0', dark='false', waitMs='300')
            rdark = p.rpc('ext.nexus.pageCoverageUi', isolateId=p.isolate,
                          mode='sheet', sheet=key, width='360', height='0', scale='1.6', dark='true', waitMs='300')
            rland = p.rpc('ext.nexus.pageCoverageUi', isolateId=p.isolate,
                          mode='sheet', sheet=key, width='640', height='360', scale='1.6', dark='true', waitMs='350')
            if key in ('tool_approval_sheet', 'device_action_confirm_sheet', 'session_metrics_sheet'):
                capture(f'major-sheet-coverage-{key}-landscape-640x360-dark-16x-20261019.png')
            p.rpc('ext.nexus.pageCoverageUi', isolateId=p.isolate, mode='pop_sheet')

            ok16 = r16.get('uiErrors', 0) == 0
            ok20 = r20.get('uiErrors', 0) == 0
            okdark = rdark.get('uiErrors', 0) == 0
            okland = rland.get('uiErrors', 0) == 0
            if ok16:
                report['passed16x'] += 1
            if ok20:
                report['passed20x'] += 1
            if okdark:
                report['passedDark16x'] += 1
            if okland:
                report['passedLandscapeDark16x'] += 1
            report['results'].append({
                'sheet': key,
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
                    f"OVERFLOW/ERROR on sheet {key}: 1.6x={r16.get('errors')} "
                    f"2.0x={r20.get('errors')} dark={rdark.get('errors')} "
                    f"landscape={rland.get('errors')}"
                )
        report['passed'] = (
            report['passed16x'] == len(sheets)
            and report['passed20x'] == len(sheets)
            and report['passedDark16x'] == len(sheets)
            and report['passedLandscapeDark16x'] == len(sheets)
        )
    finally:
        if opened:
            p.rpc('ext.nexus.pageCoverageUi', isolateId=p.isolate, mode='close')
        write_json(ROOT / 'local/temp/major-sheet-coverage-ui-20261019.json', report)
    print(
        f"Sheet coverage UI: 1.6x={report['passed16x']}/{len(sheets)}, "
        f"2.0x={report['passed20x']}/{len(sheets)}, "
        f"dark1.6x={report['passedDark16x']}/{len(sheets)}, "
        f"landscapeDark1.6x={report['passedLandscapeDark16x']}/{len(sheets)}"
    )
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
