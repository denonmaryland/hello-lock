import QtQuick
import Quickshell.Wayland

// The fail-closed cover's keyboard-shortcuts-inhibit request (issue #2).
// Hyprland answers it for its focused surface only, so Service.qml keeps the
// keyboard on the cover; `active` is true while the cover has the keyboard.
Item {
  id: guard
  property QtObject window: null
  readonly property bool active: inhibitor.active

  ShortcutInhibitor {
    id: inhibitor
    window: guard.window
    enabled: guard.window !== null
  }
}
