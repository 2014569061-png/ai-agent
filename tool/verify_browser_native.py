"""Fixed native WebView fixture; no model calls or arbitrary website inputs."""
import json
from pathlib import Path

from emulator_contract_support import VerificationFailure, contract_main, request_contract


def main():
    root = Path(__file__).resolve().parents[1]
    metadata, report = request_contract(root, 'ext.nexus.browserContract', timeout=40)
    cases = report.get('cases', [])
    if (report.get('type') != 'BrowserNativeContract' or
            report.get('fixtureOnly') is not True or report.get('modelCalls') != 0 or
            report.get('networkRequests') != 0 or report.get('platformMutations') !=
            'temporary WebView profiles and packaged DOM only' or
            not isinstance(cases, list) or
            any(not isinstance(c, dict) or not isinstance(c.get('passed'), bool) for c in cases)):
        raise VerificationFailure('Unexpected browser fixture result')
    passed = sum(c['passed'] for c in cases)
    if report.get('total') != len(cases) or report.get('passed') != passed:
        raise VerificationFailure('Inconsistent browser fixture counts')
    report['executionTarget'] = metadata['deviceId']
    target = root / 'local/temp/eta-browser-20261020/native-contract.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Native WebView fixture: {passed}/{len(cases)}; expected 23; no model calls.')
    for case in cases:
        if not case['passed']:
            print('Failed:', case['name'], case.get('code', case.get('errorType', '')))
    return 0 if passed == len(cases) == 23 else 1


if __name__ == '__main__':
    raise SystemExit(contract_main(main))
