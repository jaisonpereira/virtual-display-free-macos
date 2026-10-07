#!/usr/bin/env python3
"""Requires a logged-in macOS desktop. An explicit ID enables physical mirroring."""
import json
import subprocess
import sys
import time
from pathlib import Path

binary = Path(__file__).resolve().parents[1] / 'build/virtual-display-free-macos.app/Contents/MacOS/virtual-display-free-macos'

def displays():
    return json.loads(subprocess.check_output([str(binary), '--list-displays'], text=True))

before = displays()
target = int(sys.argv[1]) if len(sys.argv) > 1 else None
interrupt = '--interrupt' in sys.argv
if target:
    original = next(d for d in before if d['id'] == target)
    assert not original['builtIn'] and original['mirrorOf'] == 0, 'Destino deve estar estendido e ser externo.'

command = [str(binary), '--headless', '--duration', '8']
if target:
    command += ['--mirror', str(target)]
process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
try:
    deadline = time.monotonic() + 6
    while time.monotonic() < deadline:
        current = displays()
        virtuals = [d for d in current if d['vendor'] == 0xF0F0 and d['product'] == 0x5644]
        if virtuals and (not target or next(d for d in current if d['id'] == target)['mirrorOf'] == virtuals[0]['id']):
            break
        if process.poll() is not None:
            stdout, stderr = process.communicate()
            raise AssertionError(f'Processo encerrou durante criação: {stdout}\n{stderr}')
        time.sleep(0.15)
    assert len(virtuals) == 1, 'Tela virtual ausente.'
    virtual = virtuals[0]
    assert (virtual['width'], virtual['height']) == (1920, 1080), virtual
    if target:
        mirrored = next(d for d in current if d['id'] == target)
        assert mirrored['mirrorOf'] == virtual['id'], current
        assert (mirrored['width'], mirrored['height']) == (1920, 1080), mirrored
    # A second instance must fail without disturbing the first one.
    duplicate = subprocess.run([str(binary), '--headless', '--duration', '1'], capture_output=True, text=True, timeout=5)
    assert duplicate.returncode == 1, duplicate
    if interrupt:
        process.terminate()
    stdout, stderr = process.communicate(timeout=12)
    assert process.returncode == 0, (stdout, stderr)
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        after = displays()
        if not any(d['vendor'] == 0xF0F0 for d in after):
            break
        time.sleep(0.15)
    assert not any(d['vendor'] == 0xF0F0 for d in after), after
    if target:
        restored = next(d for d in after if d['id'] == target)
        fields = ('width', 'height', 'mirrorOf', 'x', 'y', 'main')
        assert tuple(restored[f] for f in fields) == tuple(original[f] for f in fields), restored
    for original_display in before:
        if original_display['builtIn']:
            restored = next(d for d in after if d['id'] == original_display['id'])
            assert restored == original_display, (original_display, restored)
    print('Criação, resolução, instância única, encerramento e restauração passaram.')
    print(stdout.strip())
finally:
    if process.poll() is None:
        process.terminate()
        process.communicate(timeout=10)
