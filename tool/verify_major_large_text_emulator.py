"""Fixed isolated UI sampling, not a host business-test suite or TalkBack audit."""
import re,subprocess
import launch_emulator_debug as e
import verify_global_search_ui_emulator as search
import verify_artifact_ui_emulator as artifact

def screenshot(name):
    result=subprocess.run([e.ADB,'-s',e.SERIAL,'exec-out','screencap','-p'],capture_output=True,timeout=30)
    assert result.returncode==0 and result.stdout.startswith(b'\x89PNG')
    (e.ROOT/f'local/temp/{name}-20261019.png').write_bytes(result.stdout)
    print('Saved synthetic large-text UI: '+name)

def joined(helper):
    return '\n'.join(n.get('text','')+' '+n.get('content-desc','') for n in helper.nodes())

def main():
    assert e.adb('emu','avd','name').splitlines()[0]=='Nexus_Preview_API_36'
    old_font=e.adb('shell','settings','get','system','font_scale').strip()
    density=e.adb('shell','wm','density')
    override=re.search(r'Override density:\s*(\d+)',density)
    search_open=artifact_open=detail=False
    try:
        e.adb('shell','settings','put','system','font_scale','1.6')
        e.adb('shell','wm','density','480')
        # The verified AVD is 1080 pixels wide: density 480 gives 360dp.
        assert '480' in e.adb('shell','wm','density')
        search.rpc('open-search');search_open=True
        assert 'Early source conversation' in joined(search)
        screenshot('major-search-font16-width360')
        search.tap('项目与日期筛选',True)
        node=next(n for n in search.nodes() if n.get('class')=='android.widget.EditText')
        x1,y1,x2,y2=map(int,re.findall(r'\d+',node.get('bounds','')))
        e.adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2))
        assert '项目与日期筛选' in joined(search)
        screenshot('major-search-font16-width360-keyboard')
        e.adb('shell','input','keyevent','4')
        search.rpc('close');search_open=False
        artifact.rpc('open');artifact_open=True
        assert 'sample.txt' in joined(artifact) and 'missing.txt' in joined(artifact)
        screenshot('major-artifact-font16-width360')
        artifact.tap('sample.txt',True);detail=True
        assert '副本完整' in joined(artifact)
        screenshot('major-artifact-detail-font16-width360')
        e.adb('shell','input','keyevent','4');detail=False
        artifact.rpc('close');artifact_open=False
    finally:
        if detail:e.adb('shell','input','keyevent','4')
        if artifact_open:artifact.rpc('close')
        if search_open:search.rpc('close')
        if old_font in ('null',''):e.adb('shell','settings','delete','system','font_scale')
        else:e.adb('shell','settings','put','system','font_scale',old_font)
        e.adb('shell','wm','density',override.group(1) if override else 'reset')
        print('Emulator display settings and owned fixtures restored')

if __name__=='__main__':main()
