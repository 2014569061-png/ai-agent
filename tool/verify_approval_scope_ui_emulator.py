"""Fixed foreground emulator UI actions; all business fixtures run in Android."""
import json,re,subprocess,urllib.parse,urllib.request,xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
from launch_emulator_debug import adb,ADB,SERIAL
from emulator_driver_support import snapshot,restore,write_json,ensure_debug_app,apk_sha256

def rpc(mode):
    m=json.loads((ROOT/'local/android-preview/vm-service.json').read_text()); assert m['deviceId']==SERIAL
    u=urllib.parse.urlsplit(m['wsUri']); assert u.scheme=='ws' and u.hostname=='127.0.0.1' and not u.query and not u.fragment and not u.username
    base=urllib.parse.urlunsplit(('http',u.netloc,u.path[:-2],'',''))
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self,*a):raise RuntimeError('Redirect denied')
    op=urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect())
    def vm(method,**args):
        with op.open(base+method+'?'+urllib.parse.urlencode(args),timeout=30) as r: env=json.load(r)
        assert 'error' not in env
        return env['result']
    main=next(i['id'] for i in vm('getVM')['isolates'] if i['name']=='main')
    result=vm('ext.nexus.approvalScopeFixture',isolateId=main,mode=mode)
    assert result['fixtureOnly'] and result['modelCalls']==0 and result['externalActions']==0
    return result

def nodes():
    adb('shell','uiautomator','dump','/sdcard/nexus-approval-fixture.xml')
    return list(ET.fromstring(adb('shell','cat','/sdcard/nexus-approval-fixture.xml')).iter('node'))
def visible(label):return any(label in n.get('text','') or label in n.get('content-desc','') for n in nodes())
def tap(label):
    for n in nodes():
        if label in (n.get('text',''),n.get('content-desc','')):
            x1,y1,x2,y2=map(int,re.findall(r'\d+',n.get('bounds','')))
            adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));return
    raise RuntimeError('Fixed fixture control not found')
def capture(name):
    p=subprocess.run([ADB,'-s',SERIAL,'exec-out','screencap','-p'],capture_output=True,timeout=30)
    assert p.returncode==0 and p.stdout.startswith(b'\x89PNG')
    (ROOT/'local/temp'/name).write_bytes(p.stdout)
def main():
    assert adb('emu','avd','name').splitlines()[0]=='Nexus_Preview_API_36'
    report={'fixtureOnly':True,'executionTarget':SERIAL,'modelCalls':0,'externalActions':0,'apkSha256':apk_sha256(),
      'passed':False,'checks':['production_sheet_opened','old_sheet_removed_without_popping_cover','stale_ui_rejected','handshake_scope_cleaned','plan_only_grant','no_global_permission_write','correction_revokes_plan_cache']}
    previous=None
    try:
        ensure_debug_app(lambda:rpc('inspect'))
        previous=snapshot()
        write_json(ROOT/'local/temp/major-approval-scope-before-20261019.json',previous)
        rpc('open')
        assert visible('隔离验收 · 持久审批')
        tap('打开隔离审批');assert visible('本计划允许')
        capture('major-approval-scope-before-correction-20261019.png')
        rpc('cover');assert visible('隔离遮盖层')
        rpc('correct');assert visible('隔离遮盖层')
        rpc('uncover');assert visible('隔离审批状态：reject') and not visible('本计划允许')
        first=rpc('inspect');assert first['decision']=='reject' and first['pendingRows']==0 and first['scopeRows']==0 and first['planGrantRows']==0
        capture('major-approval-scope-invalidated-20261019.png')
        tap('打开隔离审批');assert visible('本计划允许');tap('本计划允许')
        assert visible('隔离审批状态：allowSession')
        granted=rpc('inspect');assert granted['planTrusted'] and granted['planGrantRows']==1 and granted['globalSessionGrants']==0 and granted['globalPersistentGrants']==0
        rpc('correct');revoked=rpc('inspect');assert not revoked['planTrusted'] and revoked['planVersion']==3
        capture('major-approval-scope-plan-trust-20261019.png')
        report.update(invalidated=first,granted=granted,revoked=revoked,passed=True)
    except Exception as error:
        report['failure']=type(error).__name__
        raise
    finally:
        try:
            rpc('close')
        except Exception as error:
            report['closeFailure']=type(error).__name__
        finally:
            if previous is None:
                report['restore']={'skipped':'no baseline snapshot was taken'}
            else:
                try:
                    report['restore']=restore(previous)
                    report['originalDeviceStateRestored']=True
                    try:
                        ensure_debug_app(lambda:rpc('inspect'))
                        report['appAliveAfterRestore']=True
                    except Exception as error:
                        report['appRelaunchFailure']=type(error).__name__
                except Exception as error:
                    report['restoreFailure']=type(error).__name__
            write_json(ROOT/'local/temp/major-approval-scope-ui-20261019.json',report)
    print('Production approval UI fixture passed: scope invalidation, covered route, plan-only grant, no global permission writes.')
if __name__=='__main__':
    try:main()
    except Exception as error:
        print('Approval UI fixture failed: '+type(error).__name__+'; no private UI or endpoint printed.')
        raise SystemExit(1)
