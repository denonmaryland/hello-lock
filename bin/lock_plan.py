"""Private standalone lock choices, dispatched only through hello-config.

A session nonce is retained across backend restarts. Call only after compositor
confirmation: previews and failed lock acquisition never advance this state.
"""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import random
import re
import stat

BRANDING = {'brand': '', 'logo': '', 'symbol': '', 'symbolParts': [], 'tintLogo': True,
            'wordmarkText': '', 'wordmarkStyle': 'blocks'}
FAMILIES = ('pulse', 'phase', 'flux', 'grain', 'drift', 'circuit')
ALIASES = dict(wood='pulse', clay='phase', rubber='flux', felt='grain', relay='circuit', pluck='drift')


def draw(pool, bag, previous):
    remaining = [name for name in bag if name in pool] if isinstance(bag, list) else []
    if not remaining:
        remaining = list(pool)
        random.SystemRandom().shuffle(remaining)
        if len(remaining) > 1 and remaining[0] == previous:
            remaining[0], remaining[-1] = remaining[-1], remaining[0]
    return remaining[0], remaining[1:]


def select(config, history, session, symbols, effects, validate):
    if history.get('session') == session and isinstance(history.get('plan'), dict):
        return history, history['plan']
    pool, ids = [], set()
    for item in config.get('brandingPresets', []) if isinstance(config.get('brandingPresets'), list) else []:
        try: validate([item])
        except (ValueError, TypeError): continue
        if item['id'] not in ids:
            ids.add(item['id']); pool.append(item)
    mode = config.get('presetMode', 'manual')
    key = json.dumps([mode, config.get('selectedPreset', ''), [p['id'] for p in pool]])
    previous = history.get('preset', '') if history.get('key') == key else config.get('selectedPreset', '')
    chosen, preset = config, ''
    if pool and mode in ('cycle', 'shuffle'):
        if mode == 'cycle':
            index = next((i for i, p in enumerate(pool) if p['id'] == previous), -1)
            entry = pool[(index + 1) % len(pool)]
        else:
            candidates = [p for p in pool if len(pool) == 1 or p['id'] != previous]
            entry = random.SystemRandom().choice(candidates)
        chosen, preset = entry['branding'], entry['id']
    branding = {k: chosen.get(k) if chosen.get(k) is not None else v for k, v in BRANDING.items()}
    result = dict(history)
    plan = {'branding': branding, 'preset': preset}
    # Each bag is drawn once per confirmed lock, and all displays share it.
    sound = config.get('typingSound', 'shuffle')
    sound = ALIASES.get(sound, sound) if isinstance(sound, str) else 'shuffle'
    for kind, names, asked in (('symbol', symbols, '' if branding['symbolParts'] else branding['symbol']),
                               ('effect', effects, config.get('typingEffect', 'cells')),
                               ('sound', list(FAMILIES), sound)):
        if asked in ('shuffle', '@shuffle') and names:
            pick, remaining = draw(names, history.get(kind + 'Bag', []), history.get(kind, ''))
            result[kind + 'Bag'] = remaining
        else:
            pick = asked
        if kind == 'effect' and pick not in names and pick != 'off': pick = 'cells'
        if kind == 'sound' and pick not in FAMILIES and pick != 'off': pick = 'pulse'
        if kind == 'symbol' and branding['symbolParts']: pick = ''
        plan[kind] = '@' + pick if kind == 'symbol' and asked in ('shuffle', '@shuffle') and pick else pick
        result[kind] = pick
    result.update(session=session, plan=plan, key=key, preset=preset)
    return result, plan


def private(path, directory=False):
    info = path.lstat()
    if info.st_uid != os.getuid() or info.st_mode & 0o077 or not (stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode)):
        raise ValueError('Standalone lock history must be owned and private')


def run(config_dir, session, validate, write):
    if not re.fullmatch('[a-f0-9]{32}', session): raise ValueError('Invalid lock session identifier')
    config = Path(config_dir) / 'config.json'
    try:
        if config.stat().st_size > 4 * 1024 * 1024: raise ValueError('Oversized configuration')
        value = json.loads(config.read_text())
        if not isinstance(value, dict): raise ValueError('Configuration must be an object')
    except FileNotFoundError: value = {}
    state_base = Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state')
    if not state_base.is_absolute(): raise ValueError('XDG_STATE_HOME must be absolute')
    directory = state_base / 'hello-lock-standalone'
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    private(directory, True)
    profile = hashlib.sha256(str(Path(config_dir).absolute()).encode()).hexdigest()
    lock = directory / (profile + '.lock')
    descriptor = os.open(lock, os.O_NOFOLLOW | os.O_CREAT | os.O_RDWR, 0o600)
    try:
        info = os.fstat(descriptor)
        if info.st_uid != os.getuid() or info.st_mode & 0o077 or not stat.S_ISREG(info.st_mode):
            raise ValueError('Unsafe standalone lock history lock')
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        path = directory / (profile + '.json')
        try:
            private(path)
            if path.stat().st_size > 65536: raise ValueError('Oversized lock history')
            history = json.loads(path.read_text())
            if not isinstance(history, dict): raise ValueError('Invalid lock history')
        except FileNotFoundError: history = {}
        source = Path(__file__).resolve().parent.parent
        symbols = sorted(p.stem for p in (source / 'symbols').glob('*.svg') if re.fullmatch('[a-z0-9-]+', p.stem))
        effects = sorted(p.stem for p in (source / 'typing').glob('*.qml') if re.fullmatch('[a-z0-9-]+', p.stem) and p.stem != 'off')
        updated, plan = select(value, history, session, symbols, effects, validate)
        if updated != history: write(str(path), json.dumps(updated))
        return dict(plan, reused=history.get('session') == session)
    finally: os.close(descriptor)
