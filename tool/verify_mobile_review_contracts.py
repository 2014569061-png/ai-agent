"""Fixture-only simulator contracts; selected live-source proof, not APK sign-off."""
from emulator_driver_support import ROOT, SERIAL, write_json
from verify_conversation_results_emulator import ConversationPreview
from verify_mobile_review import source_proofs

SUITES = {'artifactActionsContract': 36, 'personalContextSqlContract': 69,
          'planProtocolContract': 228, 'memoryScopeContract': 28,
          'memoryKnowledgeContract': 12, 'conversationResultsContract': 40}


def main():
    report = dict(passed=False, fixtureOnly=True, modelCalls=0,
                  executionTarget=SERIAL, notFinalApkSignOff=True, suites={})
    try:
        p = ConversationPreview()
        p.rpc_timeout = 240
        before = source_proofs(p)
        report['sourceProofs'] = before
        for name, minimum in SUITES.items():
            result = p.rpc('ext.nexus.' + name, isolateId=p.isolate)
            passed = (result.get('fixtureOnly') is True
                      and result.get('modelCalls') == 0
                      and result.get('platformMutations') == 0
                      and result.get('persistentDataMutations') == 0
                      and result.get('total', 0) >= minimum
                      and result.get('passed') == result.get('total'))
            report['suites'][name] = dict(passed=passed, details=result)
            print('%s: %s/%s' % (name, result.get('passed'), result.get('total')), flush=True)
        report['sourcesUnchanged'] = source_proofs(p) == before
        report['passed'] = (report['sourcesUnchanged']
                            and len(report['suites']) == len(SUITES)
                            and all(v['passed'] for v in report['suites'].values()))
    except Exception as error:
        report['errorType'] = type(error).__name__
        if str(error).startswith('Live source mismatch: '):
            report['sourceMismatch'] = str(error).removeprefix('Live source mismatch: ')
    finally:
        write_json(ROOT / 'local/temp/mobile-review-contracts.json', report)
    print('Fixture contracts passed=%s errorType=%s' % (report['passed'], report.get('errorType', 'none')))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
