#!/usr/bin/env python3
"""Measure a real running app; UI state is set before starting the measurement."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def budget_failures(result, idle):
    failures = []
    if idle and result['app_and_helpers_cpu_percent'] > 3:
        failures.append('Idle CPU exceeds 3% of one logical core')
    streak = 0
    if idle:
        for point in result.get('trace', []):
            streak = streak + 1 if point['cpu_percent'] > 3 else 0
            if streak >= 3:
                failures.append('Idle CPU stays above 3% for at least three one-second samples')
                break
    if result['app_footprint_peak_mib'] > 128:
        failures.append('App physical footprint exceeds 128 MiB')
    if result['app_footprint_end_mib'] - result['app_footprint_start_mib'] > 8:
        failures.append('Physical footprint has not returned within 8 MiB of the initial baseline')
    return failures


def process_seconds(pid):
    try:
        raw = subprocess.check_output(['ps', '-p', str(pid), '-o', 'time='], text=True).strip()
        days = 0
        if '-' in raw:
            prefix, raw = raw.split('-', 1)
            days = int(prefix)
        total = 0.0
        for part in raw.split(':'):
            total = total * 60 + float(part)
        return days * 86400 + total
    except (subprocess.CalledProcessError, ValueError):
        return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pid', required=True, type=int)
    parser.add_argument('--phase', required=True)
    parser.add_argument('--seconds', type=int, default=15)
    parser.add_argument('--idle', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not 2 <= args.seconds <= 600:
        parser.error('Use a duration from 2 to 600 seconds')
    sampler = ROOT / 'build/measure-usage'
    if not sampler.exists():
        parser.error('First run bash scripts/build_usage_sampler.sh outside the measurement lock')
    lock = Path(os.environ.get('MKLOCK_TOOL', str(Path.home() / 'Library/Application Support/MK Locks/mklock')))
    if lock.exists() and os.environ.get('MONITORSWITCH_MEASUREMENT_LOCKED') != '1':
        os.environ['MONITORSWITCH_MEASUREMENT_LOCKED'] = '1'
        os.execv(str(lock), [str(lock), 'measure', 'MonitorSwitch: ' + args.phase, sys.executable, str(Path(__file__).resolve()), *sys.argv[1:]])
    battery = subprocess.check_output(['pmset', '-g', 'batt'], text=True)
    lid = subprocess.check_output(['ioreg', '-r', '-k', 'AppleClamshellState', '-d', '4'], text=True)
    percent = re.search(r'(\d+)%;', battery)
    if re.search(r'"AppleClamshellState"\s*=\s*Yes', lid) or ('Battery Power' in battery and percent and int(percent.group(1)) < 20):
        raise SystemExit('Measurement skipped: closed lid or battery below 20%')
    server = subprocess.run(['pgrep', '-x', 'WindowServer'], capture_output=True, text=True)
    server_pid = int(server.stdout.split()[0]) if server.returncode == 0 else None
    server_start = process_seconds(server_pid) if server_pid else None
    start = time.monotonic()
    task = subprocess.Popen([str(sampler), str(args.pid), str(args.seconds)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    prevent_sleep = subprocess.Popen(['caffeinate', '-d', '-i', '-w', str(task.pid)])
    try:
        stdout, stderr = task.communicate(timeout=args.seconds + 20)
        if task.returncode:
            raise SystemExit(stderr.strip() or 'Sampler failed')
    finally:
        if task.poll() is None:
            task.terminate()
        prevent_sleep.terminate()
        prevent_sleep.wait()
    result = json.loads(stdout)
    end = time.monotonic()
    server_end = process_seconds(server_pid) if server_pid else None
    result.update(phase=args.phase, idle=args.idle, windowserver_cpu_percent=None if server_start is None or server_end is None else round(100 * (server_end-server_start)/(end-start), 3))
    result['failures'] = budget_failures(result, args.idle)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    summary = {k: v for k, v in result.items() if k != 'trace'}
    print(json.dumps(summary, indent=2), flush=True)
    return 1 if result['failures'] else 0


if __name__ == '__main__':
    sys.exit(main())
