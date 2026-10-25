"""Real preview + Android sharesheet, synthetic files only, no recipient chosen."""
import re
import subprocess
import time
import xml.etree.ElementTree as ET

from emulator_driver_support import ROOT, SERIAL, adb, apk_sha256, write_json
from launch_emulator_debug import ADB
from verify_artifact_actions_emulator import Preview

XML = '/data/local/tmp/nexus-artifact-actions-ui.xml'
REPORT = ROOT / 'local/temp/u05-file-actions-ui-20261019.json'


def nodes():
    adb('shell', 'uiautomator', 'dump', XML)
    return list(ET.fromstring(adb('shell', 'cat', XML)).iter('node'))


def label(n):
    return n.get('text', '') or n.get('content-desc', '')


def wait_for(predicate):
    for _ in range(6):
        current = nodes()
        if predicate(current):
            return current
        time.sleep(0.3)
    raise RuntimeError('Fixed artifact fixture UI assertion failed')


def text_present(text):
    return wait_for(lambda rows: any(text in label(n) for n in rows))


def tap(text, contains=False):
    for n in nodes():
        if (n.get('clickable') == 'true' and n.get('enabled') == 'true' and
                (text in label(n) if contains else label(n) == text)):
            x1, y1, x2, y2 = map(int, re.findall(r'\d+', n.get('bounds', '')))
            adb('shell', 'input', 'tap', str((x1 + x2) // 2), str((y1 + y2) // 2))
            return
    raise RuntimeError('Fixed artifact fixture button not found')


def capture(name):
    result = subprocess.run([str(ADB), '-s', SERIAL, 'exec-out', 'screencap', '-p'],
                            capture_output=True, timeout=30)
    assert result.returncode == 0 and result.stdout.startswith(b'\x89PNG')
    (ROOT / ('local/temp/' + name)).write_bytes(result.stdout)


def main():
    preview = Preview()
    hashes = preview.source_hashes()
    report = dict(passed=False, fixtureOnly=True, executionTarget=SERIAL,
                  modelCalls=0, recipientsChosen=0, realUserDataMutations=0,
                  runtime='existing_debug_preview_hot_reload', notFinalApkSignOff=True,
                  baseApkSha256=apk_sha256(), liveSourceSha256=hashes, checks=[])
    opened = False
    try:
        preview.fixture('actions')
        opened = True
        text_present('隔离验收 · 成果')
        tap('sample.txt\n文件', contains=True)
        text_present('结果卡详情')
        tap('预览文件')
        rows = text_present('ARTIFACT_SOURCE_MARKER v1')
        assert any('副本完整' in label(n) for n in rows)
        assert all(n.get('enabled') == 'false' for n in rows if '系统分享／导出副本' == label(n))
        capture('u05-file-preview-20261019.png')
        report['checks'].append('real_read_only_preview_from_verified_copy')
        adb('shell', 'input', 'keyevent', '4')
        text_present('预览文件已完成')
        report['checks'].append('preview_return_persists_success')
        tap('分享文件')
        text_present('需要确认后才能执行')
        capture('u05-file-share-pending-20261019.png')
        for attempt in range(2):
            tap('确认执行')
            text_present('把文件交给系统分享')
            # Cancelling this dialog must not invoke the platform sharesheet.
            if attempt == 0:
                tap('拒绝')
                text_present('审批已拒绝')
                report['checks'].append('cancel_confirmation_does_not_dispatch')
                tap('重试分享文件')
                text_present('需要确认后才能执行')
                tap('确认执行')
                text_present('把文件交给系统分享')
            tap('确认执行')
            rows = wait_for(lambda rows: any(n.get('package') == 'com.android.intentresolver'
                       and n.get('resource-id', '').endswith('content_preview_filename')
                       and label(n) == 'sample.txt' for n in rows))
            capture('u05-file-sharesheet-%d-20261019.png' % (attempt + 1))
            report['checks'].append('real_system_sharesheet_opened_%d' % (attempt + 1))
            adb('shell', 'input', 'keyevent', '4')
            text_present('已取消系统分享，未确认交付')
            capture('u05-file-share-cancelled-%d-20261019.png' % (attempt + 1))
            report['checks'].append('dismissal_not_success_%d' % (attempt + 1))
            if attempt == 0:
                tap('重试分享文件')
                text_present('需要确认后才能执行')
        # Only pop routes opened by this fixture; leave the original app intact.
        adb('shell', 'input', 'keyevent', '4')
        text_present('隔离验收 · 成果')
        report['passed'] = True
    except Exception as error:
        report['failure'] = type(error).__name__
        raise
    finally:
        if opened:
            # If a UI assertion failed on a sheet, do not tap a random target.
            # Back dismisses only an observed system sharesheet or owned detail.
            for _ in range(4):
                current = nodes()
                if any('隔离验收 · 成果' in label(n) for n in current):
                    break
                if any(n.get('package') == 'com.android.intentresolver' for n in current) or any(
                        '结果卡详情' in label(n) or '成果详情' in label(n) or
                        '把文件交给系统分享' in label(n) for n in current):
                    adb('shell', 'input', 'keyevent', '4')
                else:
                    break
            preview.fixture('close')
        write_json(REPORT, report)
    print('Real file preview/share/cancel/retry UI passed; no recipients or model calls.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Artifact UI verification failed: ' + type(error).__name__ + '; no endpoint/auth printed.')
        raise SystemExit(1)
