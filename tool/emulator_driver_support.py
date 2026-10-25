"""Shared support for the emulator UI drivers.

Two defects used to be duplicated across the drivers, so they are fixed here once:

- Reports were written with ``Path.write_text(...)`` and no ``encoding``, so on
  Windows the Chinese drafts inside them landed as GBK and a later UTF-8 read
  failed.  Plus the historical reports themselves were GBK, so reading one back
  raised ``UnicodeDecodeError`` and looked like a business failure.
- ``verify_assistant_role_ui_emulator`` snapshotted/restored the role holders and
  three secure settings but *not* the runtime permissions the role grants.  The
  round therefore left ``RECORD_AUDIO`` granted.  A brute ``pm revoke`` of
  everything is also wrong: it would destroy authorizations the user already
  had.  So we snapshot the real per-permission state, restore only the entries
  this round actually changed, and prove the restore against the snapshot.

Nothing here starts a microphone, a real model call or a user-database write.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

from launch_emulator_debug import ROOT, SERIAL, adb

PACKAGE = 'com.nexusagent.app.debug'
APK = ROOT / 'build/app/outputs/flutter-apk/app-debug.apk'
VM_METADATA = ROOT / 'local/android-preview/vm-service.json'
_ROLE = 'android.app.role.ASSISTANT'
_SECURE_KEYS = ('assistant', 'voice_interaction_service', 'voice_recognition_service')

# `dumpsys package <pkg>` prints runtime permissions as
#   android.permission.RECORD_AUDIO: granted=false, flags=[ USER_SET|...]
_PERM_LINE = re.compile(r'\s*(android\.permission\.[A-Z0-9_]+):\s*granted=(true|false)(?:,\s*flags=\[([^\]]*)\])?')


def write_json(path, payload):
    """Write a report as UTF-8 regardless of the Windows ANSI code page."""
    text = json.dumps(payload, ensure_ascii=False, indent=2)
    Path(path).write_text(text + '\n', encoding='utf-8')


def read_json(path):
    """Read a report, tolerating the GBK files written before this fix.

    Historical reports must stay byte-identical; if both decodings fail the
    error names the file and the byte length instead of looking like a failed
    business assertion.
    """
    data = Path(path).read_bytes()
    for encoding in ('utf-8-sig', 'utf-8', 'gb18030'):
        try:
            return json.loads(data.decode(encoding))
        except (UnicodeDecodeError, json.JSONDecodeError):
            continue
    raise ValueError('Unreadable report %s (%d bytes); kept original bytes' % (path, len(data)))


def runtime_permissions():
    """Exact granted/flag state of every runtime permission of the debug package."""
    text = adb('shell', 'dumpsys', 'package', PACKAGE)
    markers = ('runtime permissions:', 'install permissions:', 'declared permissions:')
    section = None
    perms = {}
    for raw in text.splitlines():
        stripped = raw.strip()
        if stripped in markers:
            section = stripped
            continue
        if section != 'runtime permissions:':
            continue
        match = _PERM_LINE.match(raw)
        if not match:
            continue
        name, granted, flags = match.group(1), match.group(2), match.group(3) or ''
        is_user_set = any(flag.strip() == 'USER_SET' for flag in flags.split('|'))
        perms[name] = {'granted': granted == 'true', 'userSet': is_user_set}
    return perms


def snapshot():
    """Everything a UI round may mutate, captured *before* the round starts."""
    try:
        app_pid = adb('shell', 'pidof', PACKAGE)
    except RuntimeError:
        # Revoking a runtime permission can legitimately stop the app. A
        # missing PID must not prevent us proving permission restoration.
        if not device_online():
            raise
        app_pid = ''
    return {
        'holders': adb('shell', 'cmd', 'role', 'get-role-holders', _ROLE).splitlines(),
        'settings': {key: adb('shell', 'settings', 'get', 'secure', key) for key in _SECURE_KEYS},
        'permissions': runtime_permissions(),
        'appPid': app_pid,
    }


def _restore_secure(previous):
    for key, value in previous['settings'].items():
        if adb('shell', 'settings', 'get', 'secure', key) == value:
            continue
        if value == 'null':
            # `settings delete` takes only the key; a trailing value makes adb
            # answer "Too many arguments".
            adb('shell', 'settings', 'delete', 'secure', key)
        else:
            adb('shell', 'settings', 'put', 'secure', key, value)


def _restore_holders(previous):
    current = adb('shell', 'cmd', 'role', 'get-role-holders', _ROLE).splitlines()
    for holder in current:
        if holder not in previous['holders']:
            adb('shell', 'cmd', 'role', 'remove-role-holder', _ROLE, holder)
    for holder in previous['holders']:
        if holder not in current:
            adb('shell', 'cmd', 'role', 'add-role-holder', _ROLE, holder)


def _restore_permissions(previous):
    """Restore only what this round changed, and only with a baseline proof.

    `pm reset-permissions` clears every permission decision of the package and
    drops the USER_SET flag; `pm revoke` alone cannot re-add USER_SET.  For a
    baseline of "denied, USER_SET" the faithful inverse is reset-then-revoke.
    """
    baseline = previous['permissions']
    current = runtime_permissions()
    changed = []
    for name, want in baseline.items():
        have = current.get(name)
        if have == want:
            continue
        changed.append({'permission': name, 'before': want, 'during': have})
        if want['granted']:
            adb('shell', 'pm', 'grant', PACKAGE, name)
        else:
            if want['userSet']:
                adb('shell', 'pm', 'reset-permissions', PACKAGE)
            adb('shell', 'pm', 'revoke', PACKAGE, name)
    return changed


def restore(previous):
    """Undo this round's device changes and assert the result equals the baseline."""
    _restore_secure(previous)
    _restore_holders(previous)
    changed = _restore_permissions(previous)
    _restore_secure(previous)
    _restore_holders(previous)
    now = snapshot()
    for key in ('holders', 'settings', 'permissions'):
        if now[key] != previous[key]:
            raise RuntimeError('Emulator restore mismatch in %s' % key)
    # Revoking a runtime permission can finish a live process; a snapshot PID
    # difference is expected here and is reported, not hidden.
    return {'permissionsRestoredCount': len(changed),
            'permissionsChangedDuringRound': changed,
            'appProcessRestarted': now['appPid'] != previous['appPid']}


def apk_sha256():
    """Hash of the on-disk APK this round must be attributable to."""
    digest = hashlib.sha256()
    with APK.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def device_online():
    """True when the configured emulator serial is present and usable.

    The emulator can exit mid-round (it did on 2026-10-19 18:2x).  Without this
    check ``adb`` raises ``RuntimeError('Emulator ADB operation failed')`` and
    the UI drivers reported it as a business failure with a meaningless
    "driver line 19"; callers now fail with an explicit offline message.
    """
    try:
        output = adb('devices')
    except RuntimeError:
        return False
    return any(
        line.split()[0] == SERIAL and line.strip().endswith('device')
        for line in output.splitlines()[1:]
        if line.strip()
    )


def app_pid():
    """Current PID of the debug package, or None when it is not running."""
    try:
        text = adb('shell', 'pidof', PACKAGE).strip()
    except RuntimeError:
        # pidof exits 1 when the process is gone; a dead *device* is a
        # different failure and must not be reported as "app not running".
        if not device_online():
            raise
        return None
    return int(text.split()[0]) if text else None


def ensure_debug_app(probe, attempts=3):
    """Relaunch the debug app until its VM-service metadata answers ``probe``.

    Restoring the permission baseline revokes permissions, which can kill the
    live process; right after that the metadata file points at a dead PID and
    every RPC fails with a bare ``URLError``.  That looked like a failed
    business assertion in the interrupted round, so it is repaired here instead.
    """
    from launch_emulator_debug import main as launch_debug
    if not device_online():
        raise RuntimeError('Emulator offline: %s missing from adb devices' % SERIAL)
    last = None
    for _ in range(attempts):
        pid = app_pid()
        metadata = None
        try:
            metadata = read_json(VM_METADATA)
        except (OSError, ValueError):
            metadata = None
        if pid is None or not metadata or metadata.get('appPid') != pid:
            try:
                launch_debug()
            except Exception as error:  # noqa: BLE001 - reported below
                last = error
                continue
        try:
            probe()
            return True
        except Exception as error:  # noqa: BLE001 - reported below
            last = error
            try:
                launch_debug()
            except Exception as relaunch_error:  # noqa: BLE001
                last = relaunch_error
    raise RuntimeError('Debug app RPC unavailable: %s' % type(last).__name__)


def utf8_streams():
    """Make this process' stdout/stderr UTF-8 even on a GBK console."""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding='utf-8', errors='replace')
        except (AttributeError, ValueError):
            pass
