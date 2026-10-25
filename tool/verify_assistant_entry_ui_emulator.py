"""UI transport only: production entry coordinator/review, memory-only fixtures."""
import json, hashlib, traceback, urllib.parse, urllib.request
from pathlib import Path
from launch_emulator_debug import adb, SERIAL
from verify_speech_capture_ui_emulator import tap, visible, capture
from emulator_driver_support import write_json, ensure_debug_app
ROOT = Path(__file__).resolve().parents[1]

def rpc(mode='inspect'):
    m=json.loads((ROOT/'local/android-preview/vm-service.json').read_text())
    assert m['deviceId']==SERIAL
    u=urllib.parse.urlsplit(m['wsUri'])
    assert u.scheme=='ws' and u.hostname=='127.0.0.1' and not u.username and not u.password and not u.query and not u.fragment and u.path.endswith('/ws')
    base=urllib.parse.urlunsplit(('http',u.netloc,u.path[:-2],'',''))
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self,*args): raise RuntimeError('Redirect denied')
    op=urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect())
    def vm(method,**params):
        with op.open(base+method+'?'+urllib.parse.urlencode(params),timeout=30) as response: envelope=json.load(response)
        assert 'error' not in envelope
        return envelope['result']
    isolate=next(i['id'] for i in vm('getVM')['isolates'] if i['name']=='main')
    result=vm('ext.nexus.assistantEntryFixture',isolateId=isolate,mode=mode)
    assert result['fixtureOnly'] and result['modelCalls']==0 and result['userDatabaseWrites']==0 and result['microphoneStarts']==0
    return result

def settle():
    # UI transport/frame synchronization; all business decisions are in Android.
    visible('隔离外部入口验收')
    return rpc()

def main():
    assert adb('emu','avd','name').splitlines()[0]=='Nexus_Preview_API_36'
    report={'executionTarget':SERIAL,'fixtureOnly':True,'modelCalls':0,'userDatabaseWrites':0,'microphoneStarts':0,
      'apkSha256':hashlib.sha256((ROOT/'build/app/outputs/flutter-apk/app-debug.apk').read_bytes()).hexdigest()}
    ensure_debug_app(lambda: rpc())
    rpc('open')
    try:
        assert visible('隔离外部入口验收')
        rpc('busyOn');tap('任务');rpc('share');assert visible('任务忙碌，输入保留')
        busy=settle();assert busy['pending']==1 and busy['reviews']==0
        rpc('busyOff');assert visible('检查分享内容')
        rpc('focusReviewEnd');adb('shell','input','text','_edited');adb('shell','input','keyevent','KEYCODE_BACK')
        tap('加入当前草稿');edited=settle()
        assert edited['stages']==1 and edited['draft']=='existing_fixture_draft\n\nfixture_share_text_edited'
        rpc('lock');rpc('share');locked=settle();assert locked['pending']==1 and locked['reviews']==1
        rpc('unlock');assert visible('检查分享内容');tap('稍后处理')
        paused=settle();assert paused['pending']==1 and not paused['ready'] and paused['reviews']==2
        assert settle()['reviews']==2
        tap('重试待处理入口');assert visible('检查分享内容');tap('丢弃此输入');assert settle()['pending']==0
        rpc('share');assert visible('检查分享内容');rpc('rewriteDraft');tap('加入当前草稿')
        changed=settle();assert changed['stages']==1 and changed['draft']=='new_user_fixture_draft' and not changed['ready']
        tap('重试待处理入口');assert visible('检查分享内容');tap('丢弃此输入')
        tap('打开隔离入口未保存页');tap('工作区');rpc('notification');assert visible('隔离入口未保存页')
        adb('shell','input','keyevent','KEYCODE_BACK');assert visible('隔离入口未保存页')
        nested=rpc();assert nested['pending']==1 and nested['navigations']==0
        capture('major-assistant-entry-unsaved-20261019.png')
        tap('保留草稿并返回');assert visible('隔离通知目标');adb('shell','input','keyevent','KEYCODE_BACK')
        assert settle()['navigations']==1
        rpc('lookupWait');rpc('notification');settle();tap('任务');rpc('lookupRelease')
        hidden=settle();assert hidden['navigations']==1 and hidden['pending']==1 and not hidden['ready']
        tap('助手');tap('重试待处理入口');assert visible('隔离通知目标');adb('shell','input','keyevent','KEYCODE_BACK')
        rpc('busyOn');rpc('approval');assert visible('隔离通知目标')
        adb('shell','input','keyevent','KEYCODE_BACK');rpc('busyOff')
        rpc('expiringContext');assert visible('检查本次页面文字')
        for _ in range(4):
            if visible('页面文字已过期或离开前台'):break
        assert visible('页面文字已过期或离开前台')
        tap('加入当前草稿');assert rpc()['stages']==1
        capture('major-assistant-entry-expired-20261019.png');tap('丢弃此输入')
        rpc('syntheticContext');assert visible('来源：隔离页面 (com.example.fixture)');tap('加入当前草稿')
        final=settle();assert final['stages']==2 and final['navigations']==3 and final['pending']==0
        assert final['draft'].startswith('new_user_fixture_draft\n\n[系统页面文字') and 'synthetic_context_review_text' in final['draft']
        capture('major-assistant-entry-reviewed-20261019.png')
        report.update(passed=True,busy=busy,locked=locked,paused=paused,changed=changed,nested=nested,hidden=hidden,final=final,
          checks=['busy_defers','unlock_gate_simulated','editable_review_appends_existing_draft','cancel_pauses_until_retry','discard_exact_entry','changed_draft_rejects_stale_confirmation','nested_unsaved_route_preserved','hidden_async_lookup_defers','notification_navigation_only','approval_navigation_while_running','expired_text_cleared','source_review_before_staging'])
    finally:
        rpc('close')
        write_json(ROOT/'local/temp/major-assistant-entry-ui-20261019.json',report)
    print('Assistant entry UI passed; production queue/review/coordinator, memory-only staging, no model/audio/user DB writes.')

if __name__=='__main__':
    try:main()
    except Exception as error:
        line=traceback.extract_tb(error.__traceback__)[-1].lineno
        print('Assistant entry UI failed: '+type(error).__name__+' at driver line '+str(line)+'; private UI/endpoint not printed.')
        raise SystemExit(1)
