import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('usage', Path(__file__).resolve().parents[1] / 'scripts/measure_usage.py')
usage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(usage)


class PerformanceBudgetTests(unittest.TestCase):
    def healthy(self):
        return dict(app_and_helpers_cpu_percent=0.1, app_footprint_peak_mib=25,
                    app_footprint_start_mib=24, app_footprint_end_mib=25, trace=[])

    def test_healthy_idle_passes(self):
        self.assertEqual(usage.budget_failures(self.healthy(), True), [])

    def test_cpu_regression_fails(self):
        data = self.healthy()
        data['app_and_helpers_cpu_percent'] = 8
        self.assertTrue(usage.budget_failures(data, True))

    def test_sustained_spikes_fail_even_with_low_mean(self):
        data = self.healthy()
        data['trace'] = [dict(cpu_percent=10) for _ in range(3)]
        self.assertTrue(usage.budget_failures(data, True))

    def test_memory_not_released_fails(self):
        data = self.healthy()
        data['app_footprint_end_mib'] = 50
        self.assertTrue(usage.budget_failures(data, False))

    def test_unexpected_large_footprint_fails(self):
        data = self.healthy()
        data['app_footprint_peak_mib'] = 2048
        self.assertTrue(usage.budget_failures(data, False))

    def test_active_use_is_not_judged_by_idle_cpu_limit(self):
        data = self.healthy()
        data['app_and_helpers_cpu_percent'] = 8
        self.assertEqual(usage.budget_failures(data, False), [])


if __name__ == '__main__':
    unittest.main()
