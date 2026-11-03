import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property bool watch: false
  // Sway has no animation setting. Unknown/failed queries prefer calm motion.
  property bool calm: true
  function refresh() {
    if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") && !query.running) query.running = true
  }
  Process {
    id: query
    command: ["timeout", "1", "hyprctl", "-j", "getoption", "animations:enabled"]
    stdout: StdioCollector { id: output; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) { root.calm = true; return }
      try {
        var value = JSON.parse(output.text)
        root.calm = typeof value.bool === "boolean" ? !value.bool : value.int !== 1
      } catch (e) { root.calm = true }
    }
  }
  Timer { interval: 10000; repeat: true; running: root.watch; onTriggered: root.refresh() }
  Component.onCompleted: refresh()
}
