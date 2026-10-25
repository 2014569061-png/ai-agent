"""Production transcript/plan widgets, scoped real file actions; synthetic DB."""
from emulator_driver_support import ROOT, SERIAL, adb, apk_sha256, write_json
from verify_conversation_results_emulator import ConversationPreview, SOURCES
from verify_artifact_actions_ui_emulator import nodes, label, text_present, wait_for, capture
from verify_result_action_approval_ui_emulator import tap


def no_text(*values):
    assert not any(any(v in label(n) for v in values) for n in nodes())


def sharesheet():
    wait_for(lambda rows: any(n.get('package') == 'com.android.intentresolver' and
             n.get('resource-id', '').endswith('content_preview_filename') and
             label(n) == 'ChatResultA.txt' for n in rows))


def main():
    p = ConversationPreview()
    report = dict(passed=False, fixtureOnly=True, executionTarget=SERIAL,
                  modelCalls=0, recipientsChosen=0, realUserDataMutations=0,
                  runtime='existing_debug_preview_hot_reload', notFinalApkSignOff=True,
                  baseApkSha256=apk_sha256(), liveSourceSha256=p.source_hashes(SOURCES), checks=[])
    opened = False
    try:
        p.conversation_fixture('open'); opened = True
        text_present('隔离聊天结果 · a')
        text_present('ChatResultA.txt')
        no_text('PrivateResultB.txt')
        capture('u05-chat-results-timeline-20261019.png')
        report['checks'].append('production_transcript_shows_only_current_conversation_results')
        tap('ChatResultA.txt', contains=True)
        text_present('结果卡详情')
        tap('预览文件')
        text_present('CHAT_RESULT_SYNTHETIC_CONTENT')
        capture('u05-chat-results-preview-20261019.png')
        adb('shell','input','keyevent','4')
        text_present('预览文件已完成')
        tap('分享文件')
        text_present('需要确认后才能执行')
        tap('确认执行')
        text_present('把文件交给系统分享（仅本次）')
        tap('确认执行')
        sharesheet()
        capture('u05-chat-results-share-20261019.png')
        adb('shell','input','keyevent','4')
        text_present('已取消系统分享，未确认交付')
        meta = p.conversation_fixture('inspect')
        assert meta['pending'] == 0 and sum(a['attempts'] for a in meta['actions']) == 2
        report['checks'].append('chat_detail_reuses_verified_preview_and_durable_approval_real_share')
        adb('shell','input','keyevent','4')
        text_present('隔离聊天结果 · a')
        tap('查看本轮结果')
        text_present('本轮已保存结果')
        text_present('ChatResultA.txt')
        no_text('OlderResultA.txt', 'PrivateResultB.txt')
        capture('u05-chat-results-plan-20261019.png')
        report['checks'].append('production_plan_entry_filters_exact_task_and_run')
        adb('shell','input','keyevent','4')
        text_present('隔离聊天结果 · a')
        p.conversation_fixture('lateResult')
        text_present('LateResultA.txt')
        report['checks'].append('visible_running_transcript_refreshes_newly_saved_result')
        tap('切换会话')
        text_present('隔离聊天结果 · b')
        text_present('PrivateResultB.txt')
        no_text('ChatResultA.txt', 'OlderResultA.txt', 'LateResultA.txt')
        capture('u05-chat-results-switched-20261019.png')
        report['checks'].append('conversation_switch_drops_old_cards_before_new_async_load')
        tap('切换会话')
        text_present('隔离聊天结果 · a')
        # New result may put the original lower down: inspect it via the plan's
        # exact run entry, with one extra saved file still in this run.
        tap('查看本轮结果')
        text_present('ChatResultA.txt')
        tap('ChatResultA.txt', contains=True)
        text_present('结果卡详情')
        tap('分享文件')
        text_present('需要确认后才能执行')
        tap('确认执行')
        text_present('把文件交给系统分享（仅本次）')
        p.conversation_fixture('switchWhileDetail')
        tap('确认执行')
        text_present('权限已撤销或不足')
        meta = p.conversation_fixture('inspect')
        assert meta['pending'] == 0 and sum(a['attempts'] for a in meta['actions']) == 2
        assert not any(n.get('package') == 'com.android.intentresolver' for n in nodes())
        report['checks'].append('source_conversation_switch_blocks_pending_share_without_platform_dispatch')
        p.conversation_fixture('close'); opened = False
        p.conversation_fixture('open'); opened = True
        text_present('ChatResultA.txt')
        tap('ChatResultA.txt', contains=True)
        text_present('结果卡详情')
        tap('分享文件'); text_present('需要确认后才能执行')
        tap('确认执行'); text_present('把文件交给系统分享（仅本次）')
        p.conversation_fixture('deleteTask')
        tap('确认执行')
        text_present('操作记录不存在')
        meta = p.conversation_fixture('inspect')
        assert meta['pending'] == 0 and all(a['attempts'] == 0 for a in meta['actions'])
        report['checks'].append('deleted_source_task_revokes_approved_action_no_recreation')
        p.conversation_fixture('close'); opened = False
        p.conversation_fixture('open'); opened = True
        p.conversation_fixture('emptyMessages')
        text_present('今天想构建什么？')
        text_present('本会话已保存结果')
        text_present('ChatResultA.txt')
        no_text('PrivateResultB.txt')
        capture('u05-chat-results-empty-messages-20261019.png')
        report['checks'].append('empty_message_conversation_shows_residual_saved_results')
        p.conversation_fixture('normalMessages')
        text_present('隔离结果时间线，不调用模型。')
        p.conversation_fixture('seedPage')
        text_present('PageOld10.txt')
        p.conversation_fixture('scrollBottom')
        text_present('加载更早结果')
        no_text('PageOld01.txt')
        tap('加载更早结果')
        p.conversation_fixture('scrollBottom')
        text_present('PageOld01.txt')
        p.conversation_fixture('scrollTop')
        p.conversation_fixture('breakRead')
        tap('刷新会话结果')
        text_present('结果读取失败，可重试；不会影响聊天或执行动作')
        text_present('重试读取结果')
        p.conversation_fixture('restoreRead')
        tap('重试读取结果')
        no_text('结果读取失败，可重试；不会影响聊天或执行动作')
        text_present('OlderResultA.txt')
        capture('u05-chat-results-pagination-recovery-20261019.png')
        report['checks'].append('pagination_loads_older_results_and_read_error_recovers')
        p.conversation_fixture('largeText')
        text_present('本会话已保存结果')
        text_present('ChatResultA.txt')
        meta = p.conversation_fixture('inspect')
        assert meta.get('uiErrors', 0) == 0
        capture('u05-chat-results-large-text-20261019.png')
        p.conversation_fixture('normalText')
        p.conversation_fixture('backgroundPause')
        no_text('BackgroundResumedA.txt')
        p.conversation_fixture('foregroundResume')
        text_present('BackgroundResumedA.txt')
        meta = p.conversation_fixture('inspect')
        assert meta.get('uiErrors', 0) == 0
        report['checks'].append('large_text_scale_and_lifecycle_resume_refresh_results')
        p.conversation_fixture('showTools')
        text_present('查看产出结果')
        capture('u05-chat-results-tool-timeline-20261019.png')
        tap('查看产出结果')
        text_present('本轮已保存结果')
        text_present('ChatResultA.txt')
        no_text('OlderResultA.txt', 'PrivateResultB.txt')
        adb('shell','input','keyevent','4')
        p.conversation_fixture('hideTools')
        report['checks'].append('tool_activity_timeline_inline_entry_opens_scoped_results')
        report['passed'] = True
    except Exception as error:
        report['failure'] = type(error).__name__
        capture('u05-chat-results-failure-20261019.png')
        raise
    finally:
        if opened:
            if any(n.get('package') == 'com.android.intentresolver' for n in nodes()):
                adb('shell','input','keyevent','4')
            p.conversation_fixture('close')
        write_json(ROOT / 'local/temp/u05-conversation-results-ui-20261019.json', report)
    print('Conversation results UI: 11/11 isolated scenarios passed; no models or recipients.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Conversation results UI failed: ' + type(error).__name__ + '; no endpoint/auth printed.')
        raise SystemExit(1)
