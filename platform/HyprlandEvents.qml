import QtQuick
import Quickshell.Hyprland

// Hyprland socket events the lock service needs (issue #2). A config reload
// clears the Lua rules and binds Hello Lock adds while a lock is requested.
Item {
  id: events
  signal configReloaded()

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") events.configReloaded()
    }
  }
}
