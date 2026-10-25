"""Real OS AssistStructure transport from a dedicated debug-only literal page.

No user page/accounts, microphone or model. Original assistant is restored.
"""
import json, hashlib, traceback
from pathlib import Path
from launch_emulator_debug import adb, SERIAL, main as launch_debug
from verify_assistant_role_ui_emulator import rpc as role_rpc, current_pid, PACKAGE
from verify_assistant_entry_ui_emulator import rpc, settle
from verify_speech_capture_ui_emulator import tap, visible, nodes, capture
import emulator_driver_support as support
ROOT=Path(__file__).resolve().parents[1]

# Prefer the baseline-proven restore over the bare role/settings one.
snapshot=support.snapshot
restore=support.restore

def select_assistant():
    role_rpc('open');assert visible('默认系统助手')
    tap('选择默认助手');tap('Default digital assistant app');tap('NEXUS Debug')
    labels={n.get('text','') for n in nodes()}
    for label in ['Use app','Set default','Allow','OK','使用应用','设为默认','允许','确定']:
        if label in labels:tap(label);break
    for _ in range(4):
        if visible('默认系统助手'):break
        adb('shell','input','keyevent','KEYCODE_BACK')
    tap('刷新状态');status=role_rpc()['status']
    assert status['connected'] and not status['contextCollection'] and status['contextDisabledFlags']==3
    role_rpc('close')
    return status

def fixture_page(*,secure=False,large=False):
    adb('shell','am','start','-W','-n',PACKAGE+'/com.nexusagent.app.AssistantContextFixtureActivity',
        # Only this owned literal fixture's dedicated .contextfixture task.
        # Otherwise Android reuses its old root activity and ignores new extras.
        '-f','0x10008000',
        '--ez','secure',str(secure).lower(),'--ez','large',str(large).lower())
    assert visible('nexus_context_fixture_public')
    adb('shell','input','keyevent','KEYCODE_ASSIST')
    assert visible('NEXUS 系统助手') and visible('读取本页文字（仅本次）')
    assert not visible('核对文字并带入助手')

def read_and_transfer():
    tap('读取本页文字（仅本次）')
    for _ in range(4):
        if visible('核对文字并带入助手'):break
    assert visible('核对文字并带入助手')
    assert role_rpc()['status']['contextDisabledFlags']==3
    tap('核对文字并带入助手')
    for _ in range(5):
        result=rpc('takeNativeContext')
        if result['nativeContextReceived']:break
        visible('隔离外部入口验收')
    assert result['nativeContextReceived'] and result['nativePublicTextPresent'] and result['nativePasswordExcluded']
    assert result['nativeSourcePackage']==PACKAGE and 0<result['nativeTextLength']<=8000
    assert visible('检查本次页面文字') and visible(PACKAGE)
    assert rpc()['stages']==0
    return result

def main():
    assert adb('emu','avd','name').splitlines()[0]=='Nexus_Preview_API_36'
    previous=snapshot();owned=False
    report={'executionTarget':SERIAL,'fixtureOnly':True,'modelCalls':0,'microphoneStarts':0,'userDatabaseWrites':0,
      'apkSha256':hashlib.sha256((ROOT/'build/app/outputs/flutter-apk/app-debug.apk').read_bytes()).hexdigest(),
      'originalDeviceStateRestored':False}
    try:
        # A previous round's permission restore can leave the endpoint dead.
        support.ensure_debug_app(lambda: rpc())
        report['phase']='select'
        report['selected']=select_assistant()
        rpc('open');owned=True;assert visible('隔离外部入口验收')
        report['phase']='normal'
        fixture_page();report['normal']=read_and_transfer()
        assert not report['normal']['nativeTruncated']
        rpc('focusReviewEnd');adb('shell','input','text','_reviewed');adb('shell','input','keyevent','KEYCODE_BACK')
        tap('加入当前草稿');reviewed=settle()
        assert reviewed['stages']==1 and reviewed['draft'].startswith('existing_fixture_draft\n\n[系统页面文字')
        assert '_reviewed' in reviewed['draft'] and 'NEXUS_PASSWORD_MUST_NOT_BE_CAPTURED' not in reviewed['draft']
        capture('major-assistant-context-reviewed-20261019.png')
        report['reviewed']=reviewed
        rpc('close');owned=False;rpc('open');owned=True;assert visible('隔离外部入口验收')
        report['phase']='secure'
        fixture_page(secure=True);tap('读取本页文字（仅本次）')
        for _ in range(4):
            if visible('没有可读取的页面文字'):break
        assert visible('没有可读取的页面文字') and not visible('核对文字并带入助手')
        assert role_rpc()['status']['contextDisabledFlags']==3
        tap('关闭');adb('shell','am','start','-W','-n',PACKAGE+'/com.nexusagent.app.MainActivity')
        protected=settle();assert not protected['nativeContextReceived'] and protected['stages']==0
        report['securePageDenied']=True
        report['phase']='large'
        fixture_page(large=True);report['large']=read_and_transfer();assert report['large']['nativeTruncated']
        tap('丢弃此输入');assert settle()['stages']==0
        report['phase']='cancel'
        fixture_page();tap('关闭')
        adb('shell','am','start','-W','-n',PACKAGE+'/com.nexusagent.app.MainActivity')
        cancelled=settle();assert cancelled['pending']==0 and cancelled['stages']==0
        report['cancelWithoutReading']=True
        assert not role_rpc()['status']['contextCollection']
        report['passed']=True
    except Exception as error:
        frame=traceback.extract_tb(error.__traceback__)[-1]
        report['failure']={'type':type(error).__name__,'file':Path(frame.filename).name,'line':frame.lineno}
        raise
    finally:
        try:
            if owned and current_pid():
                if visible('NEXUS 系统助手'):tap('关闭')
                adb('shell','am','start','-W','-n',PACKAGE+'/com.nexusagent.app.MainActivity')
                rpc('close')
        finally:
            try:
                report['restore']=restore(previous);report['originalDeviceStateRestored']=True
                launch_debug()
            finally:
                support.write_json(ROOT/'local/temp/major-assistant-context-ui-20261019.json',report)
    print('Real one-shot AssistStructure, source/password filter, secure denial, bounded review passed; original role restored.')

if __name__=='__main__':
    try:main()
    except Exception as error:
        line=traceback.extract_tb(error.__traceback__)[-1].lineno
        print('Assistant context UI failed: '+type(error).__name__+' at driver line '+str(line)+'; private UI/endpoint not printed.')
        raise SystemExit(1)
