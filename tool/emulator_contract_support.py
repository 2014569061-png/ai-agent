"""Shared transport and validation for fixed Android debug contract checks."""
import json
import urllib.parse
import urllib.request


class VerificationFailure(RuntimeError):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        raise VerificationFailure('Debug redirect denied')


def request_contract(root, method, *, timeout=15):
    """Read a fixed extension using the approved emulator's loopback endpoint."""
    metadata = json.loads(
        (root / 'local/android-preview/vm-service.json').read_text(encoding='utf-8'))
    if metadata.get('deviceId') != 'emulator-5554':
        raise VerificationFailure('Only approved emulator is permitted')
    uri = urllib.parse.urlsplit(metadata['wsUri'])
    if (uri.scheme != 'ws' or uri.hostname != '127.0.0.1' or uri.username or
            uri.password or uri.query or uri.fragment or not uri.path.endswith('/ws')):
        raise VerificationFailure('Invalid local debug endpoint')
    base = urllib.parse.urlunsplit(('http', uri.netloc, uri.path[:-2], '', ''))
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())

    def vm(rpc_method, **params):
        url = base + rpc_method + ('?' + urllib.parse.urlencode(params) if params else '')
        with opener.open(url, timeout=timeout) as response:
            raw = response.read(2 * 1024 * 1024 + 1)
        if len(raw) > 2 * 1024 * 1024:
            raise VerificationFailure('Debug response exceeds limit')
        envelope = json.loads(raw)
        if envelope.get('error'):
            raise VerificationFailure('Debug RPC failed: ' + rpc_method)
        return envelope['result']

    vm_info = vm('getVM')
    isolate = next(row['id'] for row in vm_info['isolates'] if row['name'] == 'main')
    report = vm(method, isolateId=isolate)
    return metadata, report


def run_contract(root, report_path, *, method, result_type, expected_cases,
                 timeout=15):
    metadata, report = request_contract(root, method, timeout=timeout)
    cases = report.get('cases')
    if (report.get('type') != result_type or
            report.get('fixtureOnly') is not True or not isinstance(cases, list) or
            len(cases) != expected_cases or
            any(not isinstance(row, dict) or not isinstance(row.get('passed'), bool)
                for row in cases) or
            report.get('modelCalls') != 0 or report.get('platformMutations') != 0):
        raise VerificationFailure('Unexpected emulator test result')
    passed = sum(row['passed'] for row in cases)
    if report.get('passed') != passed or report.get('total') != len(cases):
        raise VerificationFailure('Inconsistent emulator result counts')
    report['executionTarget'] = metadata['deviceId']
    report['executionMode'] = (
        'Fixed debug checks executed in Android Dart isolate; not host flutter test suite')
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Emulator contract checks: {passed}/{len(cases)}; no model calls or platform mutations.')
    return 0 if passed == len(cases) else 1


def contract_main(main):
    """Keep diagnostic output free of VM endpoint credentials."""
    try:
        return main()
    except Exception as error:
        reason = str(error) if isinstance(error, VerificationFailure) else type(error).__name__
        print('Emulator verification unavailable: ' + reason + '; endpoint/auth not printed.')
        return 2
