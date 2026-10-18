#!/usr/bin/env python3
"""Run a Release bundle built with integration_test/desktop_stress_test.dart."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading


def run(bundle, output, timeout):
    bundle = bundle.resolve()
    output.mkdir(parents=True, exist_ok=True)
    output = output.resolve()
    trace = output / 'presentations.csv'
    trace.write_text('')  # The engine appends to this file.
    with tempfile.TemporaryDirectory(prefix='aetheria-desktop-stress-') as temporary:
        env = os.environ.copy()
        env.pop('AETHERIA_FRAME_CAPTURE', None)
        env.update(
            GDK_BACKEND='wayland', AETHERIA_PRESENTATION_TRACE=str(trace),
            XDG_CONFIG_HOME=temporary + '/config',
            XDG_DATA_HOME=temporary + '/data',
            XDG_CACHE_HOME=temporary + '/cache',
        )
        process = subprocess.Popen(
            [str(bundle / 'aetheria')], cwd=temporary, env=env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        timer = threading.Timer(timeout, process.kill)
        timer.start()
        report = None
        passed = False
        try:
            with (output / 'run.log').open('w') as log:
                for line in process.stdout:
                    log.write(line)
                    log.flush()
                    if 'AETHERIA_STRESS ' in line:
                        report = json.loads(line.split('AETHERIA_STRESS ', 1)[1])
                    if 'All tests passed!' in line:
                        passed = True
                        break
                    if 'Some tests failed.' in line:
                        break
        finally:
            timer.cancel()
            # Only terminate the process created for this run. The user's
            # normal application and its data directories are independent.
            if process.poll() is None:
                process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            process.stdout.close()
        if not passed or report is None:
            raise RuntimeError(f'Stress test did not complete; see {output / "run.log"}')
        (output / 'report.json').write_text(
            json.dumps({'desktop_stress': report}, indent=2) + '\n',
        )
    print(f'Stress test completed: {output / "report.json"}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('--output', type=Path, default=Path('build/desktop_stress_release'))
    parser.add_argument('--timeout', type=float, default=90)
    args = parser.parse_args()
    run(args.bundle, args.output, args.timeout)


if __name__ == '__main__':
    main()
