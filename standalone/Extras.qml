import QtQuick
import Quickshell
import Quickshell.Io

// Optional post-lock work. Never receives input, key identity or input length.
Item {
  id: root
  property string pluginDir: ""
  property string sessionId: ""
  property var config: ({})
  property bool engaged: false
  property bool calm: false
  property var plan: ({})
  property var status: null
  signal selected(var choice)

  function start() {
    planProc.command = [pluginDir + "/bin/hello-config", "lock-plan", sessionId]
    planProc.running = true
    var args = ["timeout", "3", pluginDir + "/bin/hello-status", "--standalone", "--name",
                (typeof config.name === "string" && config.name) ? config.name : (Quickshell.env("USER") || "friend")]
    if (typeof config.birthday === "string" && config.birthday) args.push("--birthday", config.birthday)
    if (config.weather !== true) args.push("--no-weather")
    if (typeof config.weatherLocation === "string" && config.weatherLocation) args.push("--location", config.weatherLocation)
    if (config.weatherUnit === "metric" || config.weatherUnit === "imperial") args.push("--unit", config.weatherUnit)
    statusProc.command = args
    statusProc.running = true
  }
  function cue(name) {
    if (config.sounds === false) return
    sound.command = [pluginDir + "/bin/hello-sound", name]
    sound.running = false
    sound.running = true
  }
  function edited() {
    if (!engaged || calm || config.sounds === false) return
    try { if (typing.item) typing.item.play() } catch (e) {}
  }
  Process { id: sound }
  Process {
    id: planProc
    stdout: StdioCollector { id: planOutput; waitForEnd: true }
    onExited: function(code) {
      deadline.stop()
      if (code !== 0) return
      try {
        var value = JSON.parse(planOutput.text)
        if (!value || !value.branding || typeof value.branding !== "object") return
        root.plan = value
        root.selected(value)
        if (root.engaged && value.reused !== true) root.cue("lock")
      } catch (e) {}
    }
  }
  Timer { id: deadline; interval: 2000; onTriggered: planProc.running = false }
  Connections { target: planProc; function onRunningChanged() { if (planProc.running) deadline.restart() } }
  Process {
    id: statusProc
    stdout: StdioCollector { id: statusOutput; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) return
      try {
        var value = JSON.parse(statusOutput.text)
        if (value && typeof value === "object" && !Array.isArray(value)) root.status = value
      } catch (e) {}
    }
  }
  Loader {
    id: typing
    active: root.config.sounds !== false && !root.calm && root.plan.sound !== undefined && root.plan.sound !== "off"
    asynchronous: true
    source: "plugin/TypingSound.qml"
    onLoaded: {
      item.pluginDir = root.pluginDir
      item.family = Qt.binding(function() { return root.plan.sound || "pulse" })
      item.engaged = Qt.binding(function() { return root.engaged })
    }
  }
}
