"""Targeted, source-matched emulator regression. No model calls or real data.
Uses the existing fixture UI and restores it in finally; not APK release sign-off.
"""
from emulator_driver_support import ROOT, SERIAL, write_json
from verify_conversation_results_emulator import ConversationPreview
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

SOURCES = (
    'lib/application/approval_policy.dart',
    'lib/application/run_event_tracker.dart',
    'lib/application/traced_model_provider.dart',
    'lib/application/operational_metrics.dart',
    'lib/application/chat_controller.dart',
    'lib/presentation/diagnostics/run_analysis_page.dart',
    'lib/presentation/diagnostics/operational_metrics_page.dart',
    'lib/application/foreground_approval_guard.dart',
    'lib/application/tool_pipeline/execution_interceptors.dart',
    'lib/domain/research_artifact.dart',
    'lib/application/research_artifact_service.dart',
    'lib/infrastructure/database/cost_budget_ledger.dart',
    'lib/infrastructure/database/app_database.dart',
    'lib/infrastructure/providers/cost_budget_policy.dart',
    'lib/infrastructure/providers/cost_budget_provider.dart',
    'lib/domain/models.dart',
    'lib/application/agent_executor.dart',
    'lib/application/agent_loop/token_budget.dart',
    'lib/application/chat_run_execution.dart',
    'lib/application/headless_executor.dart',
    'lib/application/agent_draft_service.dart',
    'lib/presentation/dashboard/cost_ledger_page.dart',
    'lib/debug/page_coverage_checks.dart',
    'lib/infrastructure/notifications/notification_service.dart',
    'lib/presentation/dashboard/widgets/token_usage_hero.dart',
    'lib/presentation/scheduled/scheduled_tasks_page.dart',
    'lib/presentation/projects/remote_execution_page.dart',
)


def source_proofs(p):
    scripts = p.rpc('getScripts', isolateId=p.isolate)['scripts']
    pairs = {}
    for path in SOURCES:
        script = next(s for s in scripts if s['uri'].endswith('/' + path.removeprefix('lib/')))
        live = p.rpc('getObject', isolateId=p.isolate, objectId=script['id'])['source']
        pairs[path] = {'live': live.replace('\r\n', '\n'),
                       'disk': (ROOT / path).read_text(encoding='utf-8').replace('\r\n', '\n')}
    with tempfile.TemporaryDirectory(dir=ROOT / 'local/temp') as directory:
        target = Path(directory) / 'source-pairs.json'
        target.write_text(json.dumps(pairs), encoding='utf-8')
        checked = subprocess.run([os.environ.get('NEXUS_DART', 'dart'),
            '--packages=.dart_tool/package_config.json', 'tool/verify_source_tokens.dart', str(target)],
            cwd=ROOT, capture_output=True, text=True, timeout=60, check=True)
        equal = json.loads(checked.stdout)
    for path in SOURCES:
        if equal.get(path) is not True:
            raise AssertionError('Live source mismatch: ' + path)
    return {path: {'liveSha256': hashlib.sha256(pair['live'].encode()).hexdigest(),
                   'diskSha256': hashlib.sha256(pair['disk'].encode()).hexdigest(),
                   'tokenAndCommentEquivalent': equal[path]} for path, pair in pairs.items()}


def main():
    report = dict(passed=False, fixtureOnly=True, modelCalls=0,
                  realUserDataMutations=0, executionTarget=SERIAL,
                  notFinalApkSignOff=True, results=[])
    p = None
    opened = False
    try:
        report['phase'] = 'connect_preview'
        p = ConversationPreview()
        p.rpc_timeout = 90
        report['phase'] = 'match_live_sources'
        hashes = source_proofs(p)
        report['sourceProofs'] = hashes
        report['phase'] = 'open_fixture'
        p.rpc('ext.nexus.pageCoverageUi', isolateId=p.isolate, mode='open')
        opened = True
        for width, height, scale, dark in [('360', '0', '1.6', 'false'),
                                         ('360', '0', '2.0', 'false'),
                                         ('360', '0', '1.6', 'true'),
                                         ('640', '360', '1.6', 'true')]:
            for page in ('dashboard', 'scheduled_tasks', 'remote_execution', 'research_artifacts', 'cost_ledger', 'operational_metrics', 'run_analysis'):
                result = p.rpc('ext.nexus.pageCoverageUi', isolateId=p.isolate,
                               mode='show', page=page, width=width, height=height,
                               scale=scale, dark=dark, waitMs='500')
                ok = (result.get('uiErrors') == 0 and result.get('errors') == []
                      and result.get('width') == float(width)
                      and result.get('height') == float(height)
                      and result.get('scale') == float(scale)
                      and result.get('dark') == (dark == 'true'))
                report['results'].append(dict(page=page, passed=ok, details=result))
            result = p.rpc('ext.nexus.pageCoverageUi', isolateId=p.isolate,
                           mode='sheet', sheet='cost_budget_dialog', width=width,
                           height=height, scale=scale, dark=dark, waitMs='500')
            report['results'].append(dict(sheet='cost_budget_dialog',
                passed=result.get('uiErrors') == 0 and result.get('errors') == [], details=result))
        report['sourcesUnchanged'] = source_proofs(p) == hashes
        report['passed'] = (len(report['results']) == 32
                            and all(r['passed'] for r in report['results'])
                            and report['sourcesUnchanged'])
    except Exception as error:
        report['errorType'] = type(error).__name__
        if str(error).startswith('Live source mismatch: '):
            report['sourceMismatch'] = str(error).removeprefix('Live source mismatch: ')
    finally:
        if opened:
            try:
                p.rpc('ext.nexus.pageCoverageUi', isolateId=p.isolate, mode='close')
            except Exception:
                report['fixtureCleanupFailed'] = True
                report['passed'] = False
        write_json(ROOT / 'local/temp/mobile-review-targeted.json', report)
    print('Mobile review UI: %s/%s, passed=%s, errorType=%s' % (
        sum(r['passed'] for r in report['results']), len(report['results']),
        report['passed'], report.get('errorType', 'none')))
    print('phase=%s sourceMismatch=%s' % (report.get('phase'), report.get('sourceMismatch', 'none')))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
