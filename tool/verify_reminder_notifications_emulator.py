"""One owned reminder alarm; restore the emulator's notification permission."""
from emulator_driver_support import PACKAGE, ROOT, SERIAL, adb, snapshot, restore, write_json
from verify_artifact_actions_emulator import Preview


def main():
    assert SERIAL.startswith('emulator-')
    preview = Preview()
    before = snapshot()
    report = dict(passed=False, executionTarget=SERIAL, fixtureOnly=True,
                  modelCalls=0, realUserDataMutations=0)
    try:
        adb('shell', 'pm', 'grant', PACKAGE, 'android.permission.POST_NOTIFICATIONS')
        result = preview.rpc('ext.nexus.personalContextSqlFixture',
                             isolateId=preview.isolate, mode='delivery')
        report['delivery'] = result
        report['passed'] = result.get('passed') is True
    except Exception as error:
        report['errorType'] = type(error).__name__
    finally:
        try:
            report['restoration'] = restore(before)
        except Exception as error:
            report['restorationErrorType'] = type(error).__name__
            report['passed'] = False
        write_json(ROOT / 'local/temp/mobile-reminder-notification-delivery-20261020.json', report)
    print('Reminder notification delivery:', 'PASS' if report['passed'] else 'FAIL')
    print('Emulator notification permission restored; no real-user reminder rows changed.')
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
