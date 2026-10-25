"""Read-only snapshots and explicit UI actions for the existing Android preview.
Run from Bash: python tool/mobile_ui_probe.py --serial emulator-5554 snapshot --name home
Settings changes are backed up under local/temp and can be undone with restore.
"""
import argparse
from datetime import datetime, timezone
import json
import pathlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
EVIDENCE = ROOT / 'local' / 'temp' / 'mcp-ui-5da85d5e'
ADB = ROOT / 'local' / 'android-sdk' / 'platform-tools' / 'adb.exe'
sys.stdout.reconfigure(encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    sub = parser.add_subparsers(dest='action', required=True)
    for action in ['snapshot', 'tap', 'back', 'swipe', 'configure', 'restore']:
        item = sub.add_parser(action)
        item.add_argument('--name', default=action)
        if action == 'tap':
            item.add_argument('label')
            item.add_argument('--contains', action='store_true')
            item.add_argument('--index', type=int, help='Explicit zero-based occurrence when the observed label repeats.')
            item.add_argument('--scroll', action='store_true', help='Scroll down at most eight times to find the explicit label.')
        if action == 'swipe':
            item.add_argument('coordinates', nargs=4, type=int)
        if action == 'configure':
            item.add_argument('--font', type=float, choices=[1, 1.3, 1.6, 2])
            item.add_argument('--rotation', type=int, choices=[0, 1])
            item.add_argument('--night', choices=['yes', 'no'])
            item.add_argument('--density', type=int)
    args = parser.parse_args()

    def adb(*values):
        return subprocess.run([str(ADB), '-s', args.serial, *map(str, values)],
                              capture_output=True, check=True, timeout=30).stdout

    def text(*values):
        return adb(*values).decode('utf-8', errors='replace').strip()

    if text('shell', 'getprop', 'ro.kernel.qemu') != '1':
        raise RuntimeError('Only an Android emulator is allowed; physical devices are excluded.')
    avd = text('emu', 'avd', 'name').splitlines()[0]
    if avd != 'Nexus_Preview_API_36':
        raise RuntimeError('Unexpected AVD: ' + avd)
    if args.action in ('tap', 'back', 'swipe'):
        focus = next((line for line in text('shell', 'dumpsys', 'window').splitlines()
                      if 'mCurrentFocus=' in line), '')
        if 'com.nexusagent.app.debug/' not in focus:
            raise RuntimeError('Refusing UI input outside the debug app: ' + focus.strip())
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    if not re.fullmatch(r'[A-Za-z0-9._-]+', args.name):
        raise ValueError('The evidence name must be a simple filename.')

    def hierarchy():
        adb('shell', 'rm', '-f', '/sdcard/nexus-mcp-ui.xml')
        dumped = text('shell', 'uiautomator', 'dump', '/sdcard/nexus-mcp-ui.xml')
        if 'dumped to:' not in dumped:
            raise RuntimeError('No fresh UI hierarchy was produced: ' + dumped)
        root = ET.fromstring(adb('shell', 'cat', '/sdcard/nexus-mcp-ui.xml'))
        nodes = []
        for node in root.iter('node'):
            a = node.attrib
            label = a.get('text') or a.get('content-desc') or a.get('hint')
            if not label and a.get('class') == 'android.widget.EditText':
                label = '[text input]'
            if label:
                nodes.append({'label': '[password]' if a.get('password') == 'true' else label,
                              'bounds': a.get('bounds'), 'class': a.get('class'),
                              'clickable': a.get('clickable') == 'true',
                              'enabled': a.get('enabled') == 'true'})
        viewport = list(map(int, re.findall(r'\d+', root.find('node').get('bounds'))))
        if len(viewport) != 4:
            raise RuntimeError('Unexpected viewport bounds.')
        return root.get('rotation'), nodes, viewport

    state_file = EVIDENCE / 'original-settings.json'
    if args.action == 'configure':
        if args.density is not None and not 320 <= args.density <= 800:
            raise ValueError('Density must be between 320 and 800.')
        if not state_file.exists() or json.loads(state_file.read_text()).get('restored'):
            density = text('shell', 'wm', 'density')
            override = re.search(r'Override density:\s*(\d+)', density)
            state = {key: text('shell', 'settings', 'get', 'system', key)
                     for key in ['font_scale', 'accelerometer_rotation', 'user_rotation']}
            state['density_override'] = override.group(1) if override else None
            night = re.search(r'Night mode:\s*(yes|no|auto|custom)', text('shell', 'cmd', 'uimode', 'night'))
            if not night:
                raise RuntimeError('Cannot back up the original night mode.')
            state['night'] = night.group(1)
            state_file.write_text(json.dumps(state), encoding='utf-8')
        if args.font is not None:
            adb('shell', 'settings', 'put', 'system', 'font_scale', args.font)
        if args.rotation is not None:
            adb('shell', 'settings', 'put', 'system', 'accelerometer_rotation', 0)
            adb('shell', 'settings', 'put', 'system', 'user_rotation', args.rotation)
            adb('shell', 'wm', 'user-rotation', 'lock', args.rotation)
        if args.night is not None:
            adb('shell', 'cmd', 'uimode', 'night', args.night)
        if args.density is not None:
            adb('shell', 'wm', 'density', args.density)
    elif args.action == 'restore':
        state = json.loads(state_file.read_text(encoding='utf-8'))
        for key in ['font_scale', 'user_rotation', 'accelerometer_rotation']:
            value = state[key]
            adb('shell', 'settings', 'delete' if value == 'null' else 'put',
                'system', key, *([] if value == 'null' else [value]))
        adb('shell', 'cmd', 'uimode', 'night', state['night'])
        adb('shell', 'wm', 'density', state['density_override'] or 'reset')
        adb('shell', 'wm', 'user-rotation',
            'lock' if state['accelerometer_rotation'] == '0' else 'free',
            *([state['user_rotation']] if state['accelerometer_rotation'] == '0' else []))
        state['restored'] = True
        state_file.write_text(json.dumps(state), encoding='utf-8')
    elif args.action == 'tap':
        for attempt in range(9):
            _, nodes, viewport = hierarchy()
            matches = [n for n in nodes if n['enabled'] and
                       (args.label in n['label'] if args.contains else args.label == n['label'])]
            if matches or not args.scroll or attempt == 8:
                break
            x0, y0, x1, y1 = viewport
            x = x0 + int((x1 - x0) * 0.8)
            adb('shell', 'input', 'swipe', x, y0 + int((y1-y0)*0.8),
                x, y0 + int((y1-y0)*0.38), 500)
        clickable = [n for n in matches if n['clickable']]
        matches = clickable or matches
        if args.index is not None:
            if args.index < 0 or args.index >= len(matches):
                raise RuntimeError('Explicit tap occurrence is out of range.')
            matches = [matches[args.index]]
        if len(matches) != 1:
            raise RuntimeError('Tap must match exactly one node: ' + json.dumps(matches, ensure_ascii=False))
        x1, y1, x2, y2 = map(int, re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', matches[0]['bounds']).groups())
        adb('shell', 'input', 'tap', (x1+x2)//2, (y1+y2)//2)
    elif args.action == 'back':
        adb('shell', 'input', 'keyevent', 'KEYCODE_BACK')
    elif args.action == 'swipe':
        adb('shell', 'input', 'swipe', *args.coordinates, 500)

    rotation, nodes, viewport = hierarchy()
    image = EVIDENCE / (args.name + '.png')
    image_bytes = adb('exec-out', 'screencap', '-p')
    image.write_bytes(image_bytes)
    image_size = [int.from_bytes(image_bytes[16:20], 'big'), int.from_bytes(image_bytes[20:24], 'big')]
    evidence = {'serial': args.serial, 'avd': avd, 'rotation': rotation,
                'captured_at_utc': datetime.now(timezone.utc).isoformat(), 'viewport': viewport,
                'image_size': image_size,
                'image': str(image), 'nodes': nodes}
    (EVIDENCE / (args.name + '.json')).write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in evidence.items() if k != 'nodes'}, ensure_ascii=False))
    for node in nodes:
        label = node['label'].replace('\n', ' / ')
        print(label[:280] + (f'… ({len(label)} chars)' if len(label) > 280 else ''),
              '|', node['bounds'], '| click:', node['clickable'])


if __name__ == '__main__':
    main()
