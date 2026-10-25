"""Real personal-context page against an owned temporary SQLite fixture only."""
import re

from emulator_driver_support import ROOT, SERIAL, adb, apk_sha256, write_json
from verify_artifact_actions_ui_emulator import nodes, label, tap, text_present, capture
from verify_personal_context_sql_emulator import ContextPreview, SOURCES

REPORT = ROOT / 'local/temp/u04-personal-context-ui-20261019.json'


def create(name):
    assert name in ('U04Fixture', 'U04Alias')
    tap('新建条目')
    rows = text_present('新建关联条目')
    field = next(n for n in rows if n.get('class') == 'android.widget.EditText')
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', field.get('bounds', '')))
    adb('shell', 'input', 'tap', str((x1 + x2) // 2), str((y1 + y2) // 2))
    nodes()  # Wait for autofocus/keyboard animations before sending synthetic text.
    adb('shell', 'input', 'text', name)
    assert any(n.get('class') == 'android.widget.EditText' and n.get('text') == name for n in nodes())
    tap('保存')
    text_present('重新添加已遗忘条目？')


def main():
    preview = ContextPreview()
    hashes = preview.source_hashes(SOURCES)
    report = dict(passed=False, fixtureOnly=True, executionTarget=SERIAL,
                  modelCalls=0, realUserDataMutations=0,
                  runtime='existing_debug_preview_hot_reload', notFinalApkSignOff=True,
                  baseApkSha256=apk_sha256(), liveSourceSha256=hashes, checks=[])
    opened = False
    try:
        preview.context_fixture('open')
        opened = True
        text_present('隔离验收 · 个人上下文')
        baseline = preview.context_fixture('inspect')
        assert baseline['active'] == 0 and baseline['forgotten'] == 1 and baseline['tombstones'] >= 4
        create('U04Fixture')
        capture('u04-reentry-confirmation-20261019.png')
        tap('取消')
        text_present('还没有关联上下文')
        assert preview.context_fixture('inspect') == baseline
        report['checks'].append('cancel_reentry_does_not_write_or_remove_guards')
        create('U04Fixture')
        tap('仅重新添加这一次')
        text_present('U04Fixture')
        restored = preview.context_fixture('inspect')
        assert restored['active'] == 1 and restored['forgotten'] == 1
        assert restored['aliases'] == restored['relations'] == 0 and restored['tombstones'] == baseline['tombstones']
        capture('u04-one-shot-reentry-20261019.png')
        report['checks'].append('explicit_reentry_adds_new_entity_without_old_edges_or_unblocking_import')
        tap('U04Fixture', contains=True)
        text_present('遗忘并清理关联')
        tap('遗忘并清理关联', contains=True)
        text_present('确认遗忘')
        capture('u04-forget-scope-20261019.png')
        tap('确认遗忘')
        text_present('还没有关联上下文')
        forgotten = preview.context_fixture('inspect')
        assert forgotten['active'] == 0 and forgotten['forgotten'] == 2
        report['checks'].append('real_management_page_forget_preserves_scope_and_cleans_active_list')
        create('U04Alias')
        capture('u04-alias-reentry-blocked-20261019.png')
        assert preview.context_fixture('inspect') == forgotten
        tap('取消')
        text_present('还没有关联上下文')
        report['checks'].append('old_alias_reentry_requires_fresh_explicit_consent')
        report.update(passed=True, before=baseline, restored=restored, forgotten=forgotten)
    except Exception as error:
        report['failure'] = type(error).__name__
        raise
    finally:
        if opened:
            for _ in range(4):
                rows = nodes()
                if any('隔离验收 · 个人上下文' in label(n) for n in rows):
                    break
                if any(any(s in label(n) for s in ('重新添加已遗忘条目', '新建关联条目', '确认遗忘', '遗忘并清理关联')) for n in rows):
                    adb('shell', 'input', 'keyevent', '4')
                else:
                    break
            preview.context_fixture('close')
        write_json(REPORT, report)
    print('Real personal-context reentry/cancel/forget/alias UI passed; no user data/model calls.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Context UI verification failed: ' + type(error).__name__ + '; no endpoint/auth printed.')
        raise SystemExit(1)
