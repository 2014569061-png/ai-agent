"""Production speech sheet, owned in-memory source; never starts a real microphone/model."""
import json,re,subprocess,urllib.parse,urllib.request,xml.etree.ElementTree as ET
from pathlib import Path
from launch_emulator_debug import adb,ADB,SERIAL
from emulator_driver_support import snapshot,restore,write_json,ensure_debug_app
ROOT=Path(__file__).resolve().parents[1]
def rpc(mode):
    m=json.loads((ROOT/'local/android-preview/vm-service.json').read_text());assert m['deviceId']==SERIAL
    u=urllib.parse.urlsplit(m['wsUri']);assert u.scheme=='ws' and u.hostname=='127.0.0.1' and not u.query and not u.fragment and not u.username
    base=urllib.parse.urlunsplit(('http',u.netloc,u.path[:-2],'',''))
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self,*a):raise RuntimeError('Redirect denied')
    op=urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect())
    def vm(method,**args):
        with op.open(base+method+'?'+urllib.parse.urlencode(args),timeout=30) as response:env=json.load(response)
        assert 'error' not in env
        return env['result']
    main=next(i['id'] for i in vm('getVM')['isolates'] if i['name']=='main')
    result=vm('ext.nexus.speechCaptureFixture',isolateId=main,mode=mode)
    assert result['fixtureOnly'] and result['modelCalls']==0 and result['externalActions']==0 and result['realMicrophoneStarts']==0
    return result
def nodes():
    adb('shell','uiautomator','dump','/sdcard/nexus-speech-fixture.xml')
    return list(ET.fromstring(adb('shell','cat','/sdcard/nexus-speech-fixture.xml')).iter('node'))
def visible(label):return any(label in n.get('text','') or label in n.get('content-desc','') for n in nodes())
def bounds(node):return list(map(int,re.findall(r'\d+',node.get('bounds',''))))
def swipe_up():
    candidates=[n for n in nodes() if n.get('scrollable')=='true' and len(bounds(n))==4]
    assert candidates
    n=max(candidates,key=lambda n:(bounds(n)[2]-bounds(n)[0])*(bounds(n)[3]-bounds(n)[1]))
    x1,y1,x2,y2=bounds(n);x=(x1+x2)//2
    adb('shell','input','swipe',str(x),str(y1+(y2-y1)*3//4),str(x),str(y1+(y2-y1)//4),'350')
def tap(label):
    for attempt in range(4):
        for n in nodes():
            if any(value==label or value.startswith(label+'\n') for value in (n.get('text',''),n.get('content-desc',''))):
                x1,y1,x2,y2=bounds(n)
                if x2>x1 and y2>y1:
                    adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));return
        if attempt<3:swipe_up()
    raise RuntimeError('Owned speech fixture control missing')
def capture(name):
    p=subprocess.run([ADB,'-s',SERIAL,'exec-out','screencap','-p'],capture_output=True,timeout=30)
    assert p.returncode==0 and p.stdout.startswith(b'\x89PNG')
    (ROOT/'local/temp'/name).write_bytes(p.stdout)
def main():
    assert adb('emu','avd','name').splitlines()[0]=='Nexus_Preview_API_36'
    previous=snapshot()
    write_json(ROOT/'local/temp/major-speech-capture-before-20261019.json',previous)
    # Defined before the round so the finally block can still report a failure.
    report={'fixtureOnly':True,'executionTarget':SERIAL,'modelCalls':0,'realMicrophoneStarts':0,'passed':False,
      'apkSha256':__import__('hashlib').sha256((ROOT/'build/app/outputs/flutter-apk/app-debug.apk').read_bytes()).hexdigest()}
    ensure_debug_app(lambda:rpc('inspect'))
    rpc('open')
    try:
        assert visible('隔离验收 · 语音输入')
        tap('打开隔离语音');tap('点击/按住说话');assert visible('正在录音')
        rpc('cover');assert visible('隔离语音遮盖层')
        covered=rpc('inspect');assert covered['coverVisible'] and covered['cancels']>=1 and covered['resultText'] is None
        capture('major-speech-ui-covered-20261019.png')
        rpc('uncover');tap('取消，不发送');assert visible('没有提交语音文字')
        tap('打开隔离语音');tap('点击/按住说话');rpc('late');assert not visible('OBSOLETE VOICE TEXT')
        rpc('result');assert visible('转写待确认')
        preview=rpc('inspect');assert preview['resultText'] is None and not preview['autoSend']
        rpc('focusEnd');adb('shell','input','text','_edited');assert visible('fixture voice draft_edited')
        adb('shell','input','keyevent','KEYCODE_BACK');tap('使用文字')
        edited=rpc('inspect');assert edited['resultText']=='fixture voice draft_edited' and not edited['autoSend']
        capture('major-speech-ui-edited-20261019.png')
        tap('打开隔离语音');tap('本次最终转写后自动发送');tap('点击/按住说话');rpc('result')
        assert visible('仅记录自动发送意图')
        auto=rpc('inspect');assert auto['resultText']=='fixture voice draft' and auto['autoSend']
        assert auto['submissionAllowed']
        rpc('preexistingEntry');tap('打开隔离语音');tap('本次最终转写后自动发送')
        tap('点击/按住说话');rpc('result')
        pending_voice=rpc('inspect')
        assert pending_voice['autoSend'] and not pending_voice['submissionAllowed'] and pending_voice['pendingEntry']
        tap('打开隔离语音');tap('本次最终转写后自动发送');tap('点击/按住说话')
        rpc('drainExistingEntry');rpc('result')
        drained_voice=rpc('inspect')
        assert drained_voice['autoSend'] and not drained_voice['submissionAllowed'] and not drained_voice['pendingEntry']
        rpc('unavailable');tap('打开隔离语音');assert visible('当前设备端识别不可用')
        rpc('focusEnd');adb('shell','input','text','fixture_typed_fallback');assert visible('fixture_typed_fallback')
        adb('shell','input','keyevent','KEYCODE_BACK');tap('使用文字')
        fallback=rpc('inspect');assert fallback['resultText']=='fixture_typed_fallback' and fallback['starts']==0 and fallback['permissionRequests']==0
        capture('major-speech-ui-fallback-20261019.png')
        rpc('available');tap('打开隔离语音');tap('点击/按住说话');tap('任务');assert visible('隔离任务页')
        hidden=rpc('inspect');assert hidden['phase']=='idle' and hidden['cancels']>=1
        rpc('lateCurrent');assert rpc('inspect')['transcript']==''
        rpc('assistantLink');assert visible('语音输入');assert not visible('OBSOLETE VOICE TEXT')
        tap('取消，不发送');assert visible('隔离验收 · 语音输入')
        baseline=rpc('inspect')['entryCount']
        rpc('busyOn');tap('任务');rpc('promptLink');assert visible('入口等待忙碌结束')
        deferred=rpc('inspect');assert deferred['pendingPrompt']=='fixture_entry_1' and deferred['entryCount']==baseline
        rpc('busyOff');assert visible('入口预填：fixture_entry_1')
        tap('打开隔离未保存页');assert visible('隔离未保存编辑页');tap('任务');rpc('secondPromptLink')
        assert visible('隔离未保存编辑页');blocked=rpc('inspect');assert blocked['pendingPrompt']=='fixture_entry_2'
        adb('shell','input','keyevent','KEYCODE_BACK');assert visible('隔离未保存编辑页')
        capture('major-entry-ui-unsaved-preserved-20261019.png')
        tap('确认离开隔离页');assert visible('入口预填：fixture_entry_2')
        revealed=rpc('inspect');assert not revealed['pendingEntry'] and revealed['entryCount']==baseline+2
        report.update(passed=True,
          checks=['production_sheet','cover_revokes_capture_without_popping_cover','cancel_no_send','old_result_rejected',
            'final_result_waits_confirmation','editable_transcript','opt_in_auto_send_intent_only','unavailable_typed_fallback','tab_hide_cancels_capture','warm_entry_selects_assistant',
            'busy_entry_retained','unsaved_nested_route_not_popped','pending_entry_consumed_only_after_visible'],
          covered=covered,preview=preview,edited=edited,auto=auto,pending_voice=pending_voice,drained_voice=drained_voice,
          fallback=fallback,hidden=hidden,deferred=deferred,blocked=blocked,revealed=revealed)
        print('Production speech UI fixture passed; editable confirmation, cancellation, covered route and typed fallback; no real microphone/model.')
    finally:
        try:
            rpc('close')
        finally:
            try:
                report['restore']=restore(previous)
                report['originalDeviceStateRestored']=True
                ensure_debug_app(lambda:rpc('inspect'))
                report['appAliveAfterRestore']=True
            finally:
                write_json(ROOT/'local/temp/major-speech-capture-ui-20261019.json',report)
if __name__=='__main__':
    try:main()
    except Exception as error:
        print('Speech UI fixture failed: '+type(error).__name__+'; no private UI or endpoint printed.')
        raise SystemExit(1)
