"""Scoped chat results tested inside the existing Android debug isolate."""
from emulator_driver_support import ROOT, SERIAL, apk_sha256, write_json
from verify_result_action_approval_emulator import ApprovalPreview, SOURCES as APPROVAL_SOURCES

SOURCES = tuple(dict.fromkeys(APPROVAL_SOURCES + (
    'lib/infrastructure/database/conversation_result_store.dart',
    'lib/presentation/chat/widgets/conversation_result_timeline.dart',
    'lib/presentation/chat/widgets/chat_message_list.dart',
    'lib/presentation/chat/widgets/chat_empty_state.dart',
    'lib/presentation/chat/widgets/result_card_view.dart',
    'lib/presentation/chat/widgets/plan_panel.dart',
    'lib/presentation/chat/widgets/tool_activity_section.dart',
    'lib/presentation/chat/chat_page.dart',
    'lib/debug/conversation_result_checks.dart',
)))


class ConversationPreview(ApprovalPreview):
    rpc_timeout = 240
    def conversation_fixture(self, mode):
        assert mode in (
            'open', 'inspect', 'switch', 'switchWhileDetail', 'deleteTask',
            'lateResult', 'emptyMessages', 'normalMessages', 'seedPage',
            'scrollBottom', 'scrollTop', 'breakRead', 'restoreRead',
            'largeText', 'normalText', 'backgroundPause', 'foregroundResume',
            'showTools', 'hideTools', 'close')
        result = self.rpc('ext.nexus.conversationResultsFixture', isolateId=self.isolate, mode=mode)
        assert result.get('fixtureOnly') is True and result.get('modelCalls') == 0
        return result


def main():
    p = ConversationPreview()
    hashes = p.source_hashes(SOURCES)
    report = p.rpc('ext.nexus.conversationResultsContract', isolateId=p.isolate)
    cases = report.get('cases', [])
    assert (report['type'] == 'ConversationResultContractChecks' and report['fixtureOnly'] is True
            and len(cases) == 40 and report['total'] == len(cases)
            and report['storage'] == 'owned_temporary_sqlite_file'
            and all(report[k] == 0 for k in ('modelCalls', 'platformMutations', 'persistentDataMutations')))
    assert report['passed'] == sum(c['passed'] for c in cases)
    assert p.source_hashes(SOURCES) == hashes, 'Live sources changed during checks'
    report.update(executionTarget=SERIAL, runtime='existing_debug_preview_hot_reload',
                  notFinalApkSignOff=True, baseApkSha256=apk_sha256(), liveSourceSha256=hashes)
    write_json(ROOT / 'local/temp/u05-conversation-results-contract-20261019.json', report)
    print('Conversation results: %s/%s' % (report['passed'], report['total']))
    for case in cases:
        if not case['passed']:
            print('FAILED: %s (%s)' % (case['name'], case.get('error', 'assertion')))
    return 0 if report['passed'] == report['total'] else 1


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        print('Conversation results unavailable: ' + type(error).__name__ + '; no endpoint/auth printed.')
        raise SystemExit(2)
