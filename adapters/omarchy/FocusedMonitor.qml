import QtQuick
import Quickshell.Hyprland

// Optional host adapter, loaded independently of the lock service.
Item {
  readonly property string name: Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
}
