"""Source equivalence guard self-test. No network, VM or device access."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

pairs = {
    'format': {'live': 'const x = 1;', 'disk': 'const   x=1;'},
    'string': {'live': "const x = 'a b';", 'disk': "const x = 'ab';"},
    'code': {'live': 'const x = 1;', 'disk': 'const x = 2;'},
    'comment': {'live': '// keep\nconst x = 1;', 'disk': '// changed\nconst x = 1;'},
    'raw_string': {'live': "const x = r'a b';", 'disk': "const x = r'ab';"},
}
with tempfile.TemporaryDirectory() as directory:
    target = Path(directory) / 'pairs.json'
    target.write_text(json.dumps(pairs), encoding='utf-8')
    result = subprocess.run([os.environ.get('NEXUS_DART', 'dart'),
        '--packages=.dart_tool/package_config.json', 'tool/verify_source_tokens.dart', str(target)],
        capture_output=True, text=True, timeout=60, check=True)
    assert json.loads(result.stdout) == {'format': True, 'string': False, 'code': False, 'comment': False, 'raw_string': False}
print('Source equivalence guard: 5/5 passed (format-only allowed; code, strings and comments remain checked).')
