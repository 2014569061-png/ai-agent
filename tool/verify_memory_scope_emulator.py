"""Fixed contract checks executed in the emulator's precompiled Dart code."""
from pathlib import Path

from emulator_contract_support import contract_main, run_contract

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / 'local/temp/major-memory-scope-emulator-contract-20261019.json'


def main():
    return run_contract(
        ROOT, REPORT,
        method='ext.nexus.memoryScopeContract',
        result_type='MemoryScopeContractChecks',
        expected_cases=28,
        timeout=15,
    )


if __name__ == '__main__':
    raise SystemExit(contract_main(main))
