"""Audio policy checks in disposable config roots; no real sound or session lock."""
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
import wave

ROOT = Path(os.environ.get("HELLO_LOCK_TEST_ROOT", Path(__file__).resolve().parents[1]))
FAMILIES = ("pulse", "phase", "flux", "grain", "drift", "circuit")


class TypingSoundPolicy(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.conf = self.directory / "config/hello-lock"
        self.conf.mkdir(parents=True)
        bindir = self.directory / "bin"
        bindir.mkdir()
        for name, script in {
            "date": 'printf "%s\\n" "$HELLO_TEST_HOUR"',
            "wpctl": 'printf "Volume: 0.95 %s\\n" "$HELLO_TEST_MUTE"',
            "pw-play": 'touch "$HELLO_TEST_PLAYER"',
        }.items():
            path = bindir / name
            path.write_text("#!/bin/sh\n" + script + "\n")
            path.chmod(0o700)
        self.env = dict(os.environ, XDG_CONFIG_HOME=str(self.directory / "config"),
                        PATH=str(bindir) + ":" + os.environ["PATH"], HELLO_TEST_HOUR="12",
                        HELLO_TEST_MUTE="", HELLO_TEST_PLAYER=str(self.directory / "player"))

    def policy(self):
        result = subprocess.run([str(ROOT / "bin/hello-sound"), "--policy"], env=self.env,
                                capture_output=True, text=True, timeout=5, check=True)
        self.assertFalse((self.directory / "player").exists(), "policy never starts playback")
        return json.loads(result.stdout)

    def test_quiet_hour_boundaries_and_disabled_hours(self):
        for start, end in ((23, 7), (9, 17), (12, 12)):
            (self.conf / "sound.conf").write_text("QUIET_START=%s\nQUIET_END=%s\n" % (start, end))
            for hour in (0, 6, 7, 8, 9, 12, 16, 17, 22, 23):
                with self.subTest(start=start, end=end, hour=hour):
                    self.env["HELLO_TEST_HOUR"] = "%02d" % hour
                    quiet = start <= hour < end if start < end else hour >= start or hour < end
                    self.assertEqual(self.policy()["enabled"], not quiet or start == end)
        (self.conf / "sound.conf").write_text("QUIET_START=\nQUIET_END=\n")
        self.assertTrue(self.policy()["enabled"])

    def test_muting_marker_and_volume(self):
        self.assertEqual(self.policy(), {"enabled": True, "volume": 0.5})
        self.env["HELLO_TEST_MUTE"] = "[MUTED]"
        self.assertFalse(self.policy()["enabled"])
        self.env["HELLO_TEST_MUTE"] = ""
        marker = self.conf / "sounds-off"
        marker.touch()
        self.assertFalse(self.policy()["enabled"])
        marker.unlink()
        (self.conf / "sound.conf").write_text("VOLUME=0\n")
        self.assertEqual(self.policy()["volume"], 0)
        (self.conf / "sound.conf").write_text("VOLUME=9\n")
        self.assertEqual(self.policy()["volume"], 1)

    def test_typing_choice_persists_without_changing_other_preferences(self):
        config = self.conf / "config.json"
        config.write_text('{"weather":false,"futureSetting":"keep"}')
        for choice in ("off", "shuffle", *FAMILIES):
            subprocess.run([str(ROOT / "bin/hello-config"), "save", json.dumps({"typingSound": choice})],
                           env=self.env, capture_output=True, check=True, timeout=5)
            self.assertEqual(json.loads(config.read_text()),
                             {"weather": False, "futureSetting": "keep", "typingSound": choice})


class TypingSoundAssets(unittest.TestCase):
    def test_bundled_samples_are_short_soft_and_ready_for_qt(self):
        fingerprints = set()
        for name in FAMILIES:
            for variation in range(1, 4):
                path = ROOT / "sounds" / ("type-%s-%d.wav" % (name, variation))
                with self.subTest(sound=path.name), wave.open(str(path)) as audio:
                    self.assertEqual((audio.getframerate(), audio.getnchannels(), audio.getsampwidth()), (48000, 1, 2))
                    self.assertTrue(0.09 <= audio.getnframes() / 48000 <= 0.15)
                    raw = audio.readframes(audio.getnframes())
                    samples = struct.unpack("<%dh" % (len(raw) // 2), raw)
                    self.assertEqual((samples[0], samples[-1]), (0, 0), "no hard edge at start/end")
                    self.assertLessEqual(max(abs(x) for x in samples), 8192, "-12 dBFS peak cap")
                    self.assertGreater(math.sqrt(sum(x*x for x in samples) / len(samples)), 500)
                    fingerprints.add(raw)
        self.assertEqual(len(fingerprints), 18, "all articulations are distinct")


class CueSoundAssets(unittest.TestCase):
    # Event timing is tied to the animations, so the lengths must not drift.
    LENGTHS = {"lock": 0.9, "error": 0.28, "unlock-short": 0.42, "unlock-coin": 1.5,
               "unlock-assemble": 1.58, "unlock-scan": 1.4, "unlock-glitch": 1.42,
               "unlock-heartbeat": 1.72, "unlock-orbit": 1.52, "unlock-monolith": 1.45,
               "unlock-particles": 1.6, "unlock-warp": 1.2, "unlock-split": 1.28,
               "unlock-pixels": 1.75, "unlock-legendary": 3.0}

    def test_cues_keep_animation_lengths_and_peak_cap(self):
        for name, length in self.LENGTHS.items():
            path = ROOT / "sounds" / (name + ".wav")
            with self.subTest(sound=path.name), wave.open(str(path)) as audio:
                self.assertEqual((audio.getframerate(), audio.getnchannels(), audio.getsampwidth()), (48000, 2, 2))
                self.assertAlmostEqual(audio.getnframes() / 48000, length, places=3)
                raw = audio.readframes(audio.getnframes())
                samples = struct.unpack("<%dh" % (len(raw) // 2), raw)
                self.assertEqual(samples[:2] + samples[-2:], (0, 0, 0, 0), "no hard edge at start/end")
                self.assertLessEqual(max(abs(x) for x in samples), 16423, "-6 dBFS peak cap")
                # Loudest 100 ms (stereo frames) must beat every typing sample's RMS.
                block = 4800 * 2
                loudest = max(math.sqrt(sum(x * x for x in samples[i:i + block]) / block)
                              for i in range(0, len(samples) - block + 1, block // 2))
                self.assertGreater(loudest, self.typing_rms(), "confirmation cues sit above typing")

    @staticmethod
    def typing_rms():
        levels = []
        for name in FAMILIES:
            for variation in range(1, 4):
                with wave.open(str(ROOT / "sounds" / ("type-%s-%d.wav" % (name, variation)))) as audio:
                    raw = audio.readframes(audio.getnframes())
                samples = struct.unpack("<%dh" % (len(raw) // 2), raw)
                levels.append(math.sqrt(sum(x * x for x in samples) / len(samples)))
        return max(levels)

    def test_every_unlock_variant_has_a_cue(self):
        splash = (ROOT / "UnlockSplash.qml").read_text()
        for name in self.LENGTHS:
            if name.startswith("unlock-") and name not in ("unlock-short", "unlock-legendary"):
                self.assertIn('"%s"' % name[len("unlock-"):], splash)
