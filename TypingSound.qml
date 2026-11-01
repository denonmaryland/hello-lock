import QtQuick
import QtMultimedia
import Quickshell.Io
import "TypingSounds.js" as TypingSounds

// Loaded independently: missing QtMultimedia or a WAV must never affect locking.
// This component receives only an edit pulse, never text, keys or length.
Item {
  id: root
  property string pluginDir: ""
  property string family: "pulse"
  property bool engaged: false
  property bool allowed: false
  property real volume: 0
  property int nextVoice: 0
  property real lastTick: 0
  property real policyValidUntil: 0
  readonly property bool validFamily: TypingSounds.families.indexOf(family) >= 0
  readonly property int readyVoices: {
    var count = 0
    for (var i = 0; i < voices.count; i++) {
      var voice = voices.itemAt(i)
      if (voice && voice.effect.status === SoundEffect.Ready) count++
    }
    return count
  }

  function stop() {
    for (var i = 0; i < voices.count; i++) {
      var voice = voices.itemAt(i)
      if (voice) voice.effect.stop()
    }
    lastTick = 0
  }

  function refreshPolicy() {
    if (!engaged || policyProc.running) return
    policyProc.running = true
  }

  onEngagedChanged: {
    allowed = false
    policyValidUntil = 0
    if (engaged) refreshPolicy()
    else stop()
  }
  onFamilyChanged: stop()
  onAllowedChanged: if (!allowed) stop()
  Component.onCompleted: refreshPolicy()

  // Three preloaded articulations. Never interrupt a ringing voice, queue a
  // backlog or start a process per key; excess auto-repeat pulses are dropped.
  function play() {
    if (!engaged || !allowed || !validFamily || volume <= 0) return false
    var now = Date.now()
    if (now > policyValidUntil) return false
    if (now - lastTick < 35) return false
    for (var i = 0; i < voices.count; i++) {
      var index = (nextVoice + i) % voices.count
      var voice = voices.itemAt(index)
      if (!voice || voice.effect.status !== SoundEffect.Ready || voice.effect.playing) continue
      voice.effect.play()
      nextVoice = (index + 1) % voices.count
      lastTick = now
      return true
    }
    return false
  }

  Repeater {
    id: voices
    model: 3
    Item {
      required property int index
      property alias effect: effect
      SoundEffect {
        id: effect
        source: root.validFamily ? Qt.resolvedUrl("sounds/type-" + root.family + "-" + (index + 1) + ".wav") : ""
        volume: root.volume
        muted: !root.engaged || !root.allowed
        loops: 1
      }
    }
  }

  // Use the existing helper's policy, including the off marker and quiet
  // hours. Poll only while engaged, independent of typing; fail silent.
  Timer {
    interval: 1000
    repeat: true
    running: root.engaged
    onTriggered: root.refreshPolicy()
  }
  Process {
    id: policyProc
    command: [root.pluginDir + "/bin/hello-sound", "--policy"]
    stdout: StdioCollector { id: policyOutput; waitForEnd: true }
    onExited: function(code) {
      if (!root.engaged || code !== 0) { root.allowed = false; return }
      try {
        var policy = JSON.parse(policyOutput.text)
        if (typeof policy.volume !== "number" || !isFinite(policy.volume)) { root.allowed = false; return }
        root.volume = Math.max(0, Math.min(1, policy.volume))
        root.policyValidUntil = Date.now() + 2500
        root.allowed = policy.enabled === true
      } catch (e) { root.allowed = false }
    }
  }
}
