import QtQuick
import Quickshell
import Quickshell.Io

// Ordinary desktop content/input witness. Never records text or key identities.
ShellRoot {
  id: root
  property bool inputSeen: false
  FloatingWindow {
    id: window
    visible: true
    width: 1280; height: 800
    color: "#00ff11"
    title: "Hello Lock guest desktop witness"
    Item {
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) { root.inputSeen = true; event.accepted = true }
    }
  }
  IpcHandler {
    target: "witness"
    function status(): string { return JSON.stringify({inputSeen: root.inputSeen}) }
    function reset(): string { root.inputSeen = false; return "ok" }
    function quit(): string { Qt.quit(); return "ok" }
  }
}
