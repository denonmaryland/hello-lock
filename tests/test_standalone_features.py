"""Feature persistence and privacy checks, using disposable profiles only."""
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
plan = runpy.run_path(str(ROOT / 'bin/lock_plan.py'))
config = runpy.run_path(str(ROOT / 'bin/hello-config'))


class LockChoices(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.profile = self.base / 'profile'; self.profile.mkdir()
        self.file = self.profile / 'config.json'
        self.env = dict(os.environ, HELLO_LOCK_CONFIG_DIR=str(self.profile), XDG_STATE_HOME=str(self.base / 'state'))

    def invoke(self, session):
        response = subprocess.run([str(ROOT / 'bin/hello-config'), 'lock-plan', session], env=self.env,
                                  capture_output=True, text=True, timeout=5)
        self.assertEqual(response.returncode, 0, response.stderr)
        return json.loads(response.stdout)

    def test_rotation_once_per_session_and_preserves_config(self):
        self.file.write_text(json.dumps({'weather': False, 'future': 'keep', 'presetMode': 'cycle', 'selectedPreset': 'a',
            'brandingPresets': [{'id': k, 'name': k, 'branding': {'logo': k + '.svg'}} for k in ('a','b')]}))
        original = self.file.read_bytes()
        first = self.invoke('a' * 32)
        self.assertEqual(first['preset'], 'b'); self.assertFalse(first['reused'])
        same = self.invoke('a' * 32)
        self.assertEqual(same['preset'], 'b'); self.assertTrue(same['reused'])
        self.assertEqual(self.invoke('b' * 32)['preset'], 'a')
        self.assertEqual(self.file.read_bytes(), original)
        for path in (self.base / 'state/hello-lock-standalone').iterdir():
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_malformed_presets_ignored_and_custom_parts_retained(self):
        self.file.write_text(json.dumps({'presetMode': 'cycle', 'brandingPresets': [None, {'id':'invalid'},
            {'id':'parts','name':'Two parts','branding': {'symbol':'@radar','symbolParts':['one.svg','two.svg']}}]}))
        choice = self.invoke('a' * 32)
        self.assertEqual(choice['preset'], 'parts')
        self.assertEqual(choice['branding']['symbolParts'], ['one.svg','two.svg'])
        self.assertEqual(choice['symbol'], '')

    def test_shuffle_bags_do_not_repeat_before_exhaustion(self):
        state = {}
        value = {'symbol':'@shuffle', 'typingEffect':'shuffle', 'typingSound':'shuffle'}
        symbols, effects = ['a','b','c'], ['cells','pulse','liquid']
        picks = []
        for n in range(3):
            state, choice = plan['select'](value, state, str(n), symbols, effects, config['validate_presets'])
            picks.append(choice)
        self.assertEqual({p['symbol'] for p in picks}, {'@a','@b','@c'})
        self.assertEqual({p['effect'] for p in picks}, set(effects))
        _, choice = plan['select'](value, state, 'next', symbols, effects, config['validate_presets'])
        self.assertNotEqual(choice['symbol'], picks[-1]['symbol'])
        self.assertNotEqual(choice['effect'], picks[-1]['effect'])

    def test_bad_state_and_symlinks_fail_without_replacing_data(self):
        self.invoke('a' * 32)
        root = self.base / 'state/hello-lock-standalone'
        state = next(root.glob('*.json')); state.write_text('broken')
        response = subprocess.run([str(ROOT/'bin/hello-config'),'lock-plan','b'*32], env=self.env, capture_output=True)
        self.assertNotEqual(response.returncode, 0); self.assertEqual(state.read_text(), 'broken')
        state.unlink(); outside=self.base/'keep';outside.write_text('keep');state.symlink_to(outside)
        response = subprocess.run([str(ROOT/'bin/hello-config'),'lock-plan','b'*32], env=self.env, capture_output=True)
        self.assertNotEqual(response.returncode, 0); self.assertEqual(outside.read_text(), 'keep')

    def test_profiles_do_not_share_a_rotation_cursor(self):
        self.invoke('a' * 32)
        other = self.base/'other';other.mkdir()
        with patch.dict(os.environ, dict(self.env, HELLO_LOCK_CONFIG_DIR=str(other))):
            result = subprocess.run([str(ROOT/'bin/hello-config'),'lock-plan','b'*32], capture_output=True)
        self.assertEqual(result.returncode,0)
        self.assertEqual(len(list((self.base/'state/hello-lock-standalone').glob('*.json'))),2)


class StandaloneWeather(unittest.TestCase):
    def test_requires_explicit_profile_opt_in_and_no_weather_overrides_it(self):
        with tempfile.TemporaryDirectory() as directory:
            profile=Path(directory); file=profile/'config.json'
            with patch.dict(os.environ, HELLO_LOCK_CONFIG_DIR=directory):
                helper=runpy.run_path(str(ROOT/'bin/hello-status'))
                namespace=helper['weather_allowed'].__globals__
                with patch.dict(namespace, STANDALONE=True):
                    for value in ({}, {'weather':False}, {'weather':'true'}):
                        file.write_text(json.dumps(value));self.assertFalse(helper['weather_allowed']())
                    file.write_text('{"weather":true}')
                    self.assertTrue(helper['weather_allowed']())
                    with patch.dict(namespace, WEATHER=False): self.assertFalse(helper['weather_allowed']())

    def test_standalone_location_never_reads_omarchy_and_encodes_input(self):
        helper=runpy.run_path(str(ROOT/'bin/hello-status'))
        namespace=helper['weather_query'].__globals__
        with patch.dict(namespace, STANDALONE=True, LOCATION='Town & Co/?x=1', UNIT='metric'), patch('builtins.open', side_effect=AssertionError('Unexpected Omarchy read')):
            self.assertEqual(helper['weather_query'](), 'Town%20%26%20Co%2F%3Fx%3D1')
            self.assertEqual(helper['weather_unit'](), 'metric')

    def test_sound_and_status_are_not_authentication_dependencies(self):
        core=(ROOT/'standalone/lock.qml').read_text()
        extras=(ROOT/'standalone/Extras.qml').read_text()
        self.assertNotIn('entered',extras); self.assertNotIn('password',extras.lower())
        self.assertIn('function onTypingSoundRequested()', core)
        self.assertIn('function edited()', extras)
        self.assertIn('active: root.everSecure',core)
        self.assertNotIn('releaseAuthenticated', extras)


if __name__ == '__main__': unittest.main()
