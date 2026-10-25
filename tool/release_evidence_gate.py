"""Fail-closed local APK release gate. Never runs devices or model calls.
Evidence is a reviewed local assertion, not cryptographic authorization.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

REQUIRED = ('static_analysis', 'agent_regression', 'approval_security',
            'arm64_runtime', 'background_recovery', 'accessibility', 'performance')


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def contained(root, name):
    path = (root / name).resolve()
    path.relative_to(root.resolve())
    return path


def validate(root, apk, evidence, certificate):
    errors = []
    def require(ok, reason):
        if not ok:
            errors.append(reason)
    require(evidence.get('schema') == 1, 'unsupported_schema')
    require(evidence.get('apkSha256') == digest(apk), 'apk_mismatch')
    require(bool(certificate) and evidence.get('certificateSha256') == certificate,
            'certificate_mismatch')
    require(evidence.get('channel') == 'private-apk', 'channel_not_reviewed')
    require(evidence.get('blockers') == [], 'open_or_missing_blockers')
    sources = evidence.get('sourceSha256', {})
    require(isinstance(sources, dict) and bool(sources), 'missing_sources')
    if isinstance(sources, dict):
        # All production Dart sources must be present, not just a convenient subset.
        actual = {p.relative_to(root).as_posix() for p in (root / 'lib').rglob('*.dart')}
        native = root / 'android/app/src/main'
        actual.update(p.relative_to(root).as_posix() for p in native.rglob('*')
                      if p.is_file() and p.suffix in ('.kt', '.java', '.xml'))
        actual.update(name for name in ('pubspec.yaml', 'pubspec.lock',
                      'android/app/build.gradle.kts', 'android/build.gradle.kts',
                      'android/settings.gradle.kts') if (root / name).is_file())
        require(bool(actual) and actual.issubset(sources), 'incomplete_dart_sources')
        for name, expected in sources.items():
            try:
                path = contained(root, name)
                require(path.is_file() and digest(path) == expected, 'source_mismatch:' + name)
            except (ValueError, OSError, TypeError):
                errors.append('invalid_source_path')
    gates = evidence.get('gates', {})
    if not isinstance(gates, dict):
        gates = {}
    for name in REQUIRED:
        gate = gates.get(name, {})
        if not isinstance(gate, dict):
            gate = {}
        require(gate.get('status') == 'passed', 'gate_not_passed:' + name)
        require(gate.get('apkSha256') == evidence.get('apkSha256'), 'gate_apk_mismatch:' + name)
        require(bool(gate.get('reviewedBy')) and bool(gate.get('verifiedAt')), 'missing_review:' + name)
        try:
            path = contained(root, gate.get('report', ''))
            require(path.is_file() and digest(path) == gate.get('reportSha256'), 'report_mismatch:' + name)
            if path.suffix.lower() == '.json' and path.is_file():
                report = json.loads(path.read_text(encoding='utf-8-sig'))
                require(report.get('passed') is True, 'report_not_passed:' + name)
                require(report.get('sourcesUnchanged') is not False, 'report_sources_changed:' + name)
                require(not report.get('errorType') and not report.get('fixtureCleanupFailed'),
                        'report_error:' + name)
        except (ValueError, OSError, TypeError, AttributeError):
            errors.append('invalid_report:' + name)
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', required=True)
    parser.add_argument('--evidence', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--apksigner', default='apksigner')
    args = parser.parse_args()
    root = Path.cwd().resolve()
    result = {'schema': 1, 'releaseReady': False, 'errors': []}
    try:
        apk = contained(root, args.apk)
        evidence = json.loads(contained(root, args.evidence).read_text(encoding='utf-8-sig'))
        commit = subprocess.run(['git', 'rev-parse', 'HEAD'], capture_output=True,
                                text=True, timeout=10, check=True).stdout.strip()
        result['gitCommit'] = commit
        if evidence.get('gitCommit') != commit:
            raise ValueError('git_commit_mismatch')
        # Certificate is measured from the APK, never trusted from the evidence alone.
        check = subprocess.run([args.apksigner, 'verify', '--print-certs', str(apk)],
                               capture_output=True, text=True, timeout=60, check=True)
        if 'CN=Android Debug' in check.stdout or 'androiddebugkey' in check.stdout.lower():
            raise ValueError('debug_certificate')
        certs = [line.split(':', 1)[1].strip().lower() for line in check.stdout.splitlines()
                 if line.startswith('Signer #1 certificate SHA-256 digest:')]
        if len(certs) != 1:
            raise ValueError('missing_certificate')
        result['apkSha256'] = digest(apk)
        result['certificateSha256'] = certs[0]
        result['errors'] = validate(root, apk, evidence, certs[0])
        result['releaseReady'] = not result['errors']
    except Exception as error:
        # Do not print signing output, credentials, arbitrary exceptions or paths.
        result['errors'].append('gate_failed:' + type(error).__name__)
    output = contained(root, args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('releaseReady=' + str(result['releaseReady']).lower())
    return 0 if result['releaseReady'] else 1


if __name__ == '__main__':
    sys.exit(main())
