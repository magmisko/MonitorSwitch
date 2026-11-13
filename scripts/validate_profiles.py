#!/usr/bin/env python3
"""Validate contributed monitor profiles; no third-party packages required."""
import json
import re
import sys
from pathlib import Path


def validate(catalog):
    def require(condition, message):
        if not condition:
            raise ValueError(message)

    def integer(value, low, high):
        return type(value) is int and low <= value <= high

    require(isinstance(catalog, dict) and type(catalog.get('schemaVersion')) is int and catalog.get('schemaVersion') == 1,
            'schemaVersion must be 1')
    monitors = catalog.get('monitors')
    require(isinstance(monitors, list) and bool(monitors), 'monitors must be a nonempty list')
    ids, devices = set(), set()
    for monitor in monitors:
        require(isinstance(monitor, dict), 'Each monitor must be an object')
        ident = monitor.get('id')
        require(isinstance(ident, str) and re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', ident), 'Invalid profile id')
        require(ident not in ids, 'Duplicate profile id: ' + ident)
        ids.add(ident)
        manufacturer, product = monitor.get('manufacturer'), monitor.get('productID')
        require(isinstance(manufacturer, str) and bool(manufacturer.strip()), ident + ': missing manufacturer')
        require(integer(product, 1, 65535), ident + ': productID must be an integer from 1 to 65535')
        require((manufacturer, product) not in devices, ident + ': duplicate manufacturer/productID')
        devices.add((manufacturer, product))
        require(isinstance(monitor.get('name'), str) and bool(monitor['name'].strip()), ident + ': missing name')
        ports = monitor.get('ports')
        require(isinstance(ports, list) and 1 <= len(ports) <= 9, ident + ': add 1–9 ports')
        codes, names = set(), set()
        for port in ports:
            require(isinstance(port, dict), ident + ': invalid port')
            name, code = port.get('name'), port.get('code')
            require(isinstance(name, str) and bool(name.strip()), ident + ': missing port name')
            require(integer(code, 1, 65535), ident + ': invalid port code')
            require(code not in codes and name not in names, ident + ': duplicate port name or code')
            codes.add(code)
            names.add(name)
        controls = monitor.get('controls')
        require(isinstance(controls, list) and all(isinstance(c, str) for c in controls), ident + ': controls must be a list')
        require(len(controls) == len(set(controls)) and set(controls) <= {'brightness', 'volume'}, ident + ': only brightness and volume controls are supported')
        require(isinstance(monitor.get('verification'), str) and bool(monitor['verification'].strip()), ident + ': describe hardware verification')


if __name__ == '__main__':
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / 'monitors.json'
    try:
        data = json.loads(path.read_text())
        validate(data)
    except (OSError, ValueError, TypeError) as error:
        print('Profile validation failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
    print('Validated {} monitor profiles.'.format(len(data['monitors'])))
