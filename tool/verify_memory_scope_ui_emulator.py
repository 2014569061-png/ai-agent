"""Fixed emulator-only UI fixture transport. No host business tests."""
import json, sys, urllib.parse, urllib.request, re, subprocess
import xml.etree.ElementTree as ET
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tool'))
from launch_emulator_debug import adb, ADB, SERIAL

def rpc(mode):
    metadata = json.loads((ROOT / 'local/android-preview/vm-service.json').read_text())
    assert metadata['deviceId'] == SERIAL
    uri = urllib.parse.urlsplit(metadata['wsUri'])
    assert uri.scheme == 'ws' and uri.hostname == '127.0.0.1' and uri.path.endswith('/ws')
    base = urllib.parse.urlunsplit(('http', uri.netloc, uri.path[:-2], '', ''))
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self,*args): raise RuntimeError('Redirect denied')
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect())
    def vm(method, **params):
        with opener.open(base + method + ('?' + urllib.parse.urlencode(params) if params else ''), timeout=30) as response:
            envelope = json.loads(response.read(2*1024*1024))
        assert 'error' not in envelope, 'Debug RPC failed'
        return envelope['result']
    main = next(i['id'] for i in vm('getVM')['isolates'] if i['name'] == 'main')
    result = vm('ext.nexus.memoryScopeFixture', isolateId=main, mode=mode)
    assert result.get('fixtureOnly') is True
    print('Isolated fixture: ' + mode)

def nodes():
    adb('shell','uiautomator','dump','/sdcard/nexus-jobs-fixture.xml')
    return list(ET.fromstring(adb('shell','cat','/sdcard/nexus-jobs-fixture.xml')).iter('node'))

def tap(label, prefix=False):
    for node in nodes():
        for attr in ['text','content-desc']:
            text=node.get(attr,'')
            if text==label or (prefix and text.startswith(label)):
                x1,y1,x2,y2=map(int,re.findall(r'\d+',node.get('bounds','')))
                adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2))
                print('Fixture control tapped: '+label)
                return
    raise RuntimeError('Fixture control not found')

def main():
    assert adb('emu','avd','name').splitlines()[0]=='Nexus_Preview_API_36'
    mode=sys.argv[1]
    if mode in ['open','mutate','inspect','close']: rpc(mode)
    elif mode=='edit': tap('编辑')
    elif mode=='draft':
        node=next(n for n in nodes() if n.get('class')=='android.widget.EditText')
        x1,y1,x2,y2=map(int,re.findall(r'\d+',node.get('bounds','')))
        # This fixed ASCII marker is one word; long-press selects it completely.
        # Hardware MOVE_END/Ctrl+A are ignored by this emulator IME, so never assume selection.
        x, y = str(x1+min(120,(x2-x1)//3)), str(y1+min(55,(y2-y1)//4))
        adb('shell','input','swipe',x,y,x,y,'1200')
        adb('shell','input','text','EDITOR_DRAFT_MARKER')
        assert any(n.get('class')=='android.widget.EditText' and n.get('text')=='EDITOR_DRAFT_MARKER' for n in nodes()), 'Exact synthetic draft was not entered'
        print('Exact synthetic editor draft entered')
    elif mode=='save':tap('保存')
    elif mode=='cancel':tap('取消')
    elif mode=='discard':tap('放弃修改')
    elif mode=='capture':
        joined='\n'.join(n.get('text','')+' '+n.get('content-desc','') for n in nodes())
        assert any(n.get('class')=='android.widget.EditText' and n.get('text')=='EDITOR_DRAFT_MARKER' for n in nodes()) and '草稿仍在此处' in joined
        result=subprocess.run([ADB,'-s',SERIAL,'exec-out','screencap','-p'],capture_output=True,timeout=30)
        assert result.returncode==0 and result.stdout.startswith(b'\x89PNG')
        target=ROOT/'local/temp/major-memory-scope-editor-conflict-20261019.png'
        target.write_bytes(result.stdout)
        print('Stale editor retained draft; screenshot: '+target.name)
    else: raise RuntimeError('Unknown fixed fixture action')

if __name__=='__main__':
    try: main()
    except Exception as error:
        print('Fixture unavailable: '+type(error).__name__+'; endpoint/auth and UI contents not printed.')
        raise SystemExit(1)
