import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('validator', ROOT / 'scripts/validate_profiles.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class ProfileValidationTests(unittest.TestCase):
    def setUp(self):
        self.catalog = json.loads((ROOT / 'monitors.json').read_text())

    def test_shipped_profiles_are_valid(self):
        validator.validate(self.catalog)

    def test_boolean_is_not_a_schema_version(self):
        self.catalog['schemaVersion'] = True
        with self.assertRaisesRegex(ValueError, 'schemaVersion'):
            validator.validate(self.catalog)

    def test_same_device_cannot_select_conflicting_profiles(self):
        duplicate = copy.deepcopy(self.catalog['monitors'][0])
        duplicate['id'] = 'conflicting-profile'
        self.catalog['monitors'].append(duplicate)
        with self.assertRaisesRegex(ValueError, 'duplicate manufacturer/productID'):
            validator.validate(self.catalog)

    def test_boolean_is_not_a_hardware_identifier(self):
        self.catalog['monitors'][0]['productID'] = True
        with self.assertRaises(ValueError):
            validator.validate(self.catalog)

    def test_duplicate_port_codes_are_rejected(self):
        ports = self.catalog['monitors'][0]['ports']
        ports[1]['code'] = ports[0]['code']
        with self.assertRaisesRegex(ValueError, 'duplicate port'):
            validator.validate(self.catalog)

    def test_unsafe_arbitrary_vcp_controls_cannot_be_added(self):
        self.catalog['monitors'][0]['controls'].append('power')
        with self.assertRaisesRegex(ValueError, 'only brightness and volume'):
            validator.validate(self.catalog)

    def test_verification_is_required(self):
        self.catalog['monitors'][0].pop('verification')
        with self.assertRaisesRegex(ValueError, 'hardware verification'):
            validator.validate(self.catalog)


if __name__ == '__main__':
    unittest.main()
