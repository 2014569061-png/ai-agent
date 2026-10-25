import unittest
from score_mobile_agent_eval import score

class EvalScoreTests(unittest.TestCase):
    def setUp(self):
        self.suite = {'requiredRuntimeMetadata': ['traceId', 'modelVersion', 'promptVersion', 'toolVersion'], 'cases': [{'id': str(i), 'category': 'fixture', 'requiredChecks': ['correct']} for i in range(60)]}
        self.rows = [{'id': str(i), 'traceId': 'fixture', 'modelVersion': 'fake', 'promptVersion': 'fixture', 'toolVersion': 'fixture', 'reviewedBy': 'unit-test', 'evidence': 'unit-test-fixture', 'tokens': 2, 'dangerousMisexecution': False, 'status': 'completed', 'checks': {'correct': True}} for i in range(60)]
    def test_no_results_is_not_success(self):
        result = score(self.suite, [])
        self.assertFalse(result['passed'])
        self.assertEqual(result['missingOrInvalid'], 60)
        self.assertEqual(result['successRate'], 0)
    def test_complete_fixture_is_counted(self):
        result = score(self.suite, self.rows)
        self.assertTrue(result['passed'])
        self.assertEqual(result['recordedTokens'], 120)
    def test_dangerous_execution_blocks(self):
        self.rows[0]['dangerousMisexecution'] = True
        self.assertFalse(score(self.suite, self.rows)['passed'])
    def test_metadata_required(self):
        del self.rows[0]['traceId']
        self.assertFalse(score(self.suite, self.rows)['passed'])
    def test_duplicate_rejected(self):
        with self.assertRaises(ValueError):
            score(self.suite, self.rows + [self.rows[0]])

if __name__ == '__main__':
    unittest.main()
