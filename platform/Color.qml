pragma Singleton
import QtQuick

// The host supplies its palette. Visual components never read desktop files.
QtObject {
  property var source: null
  property color baseBackground: "#1a1b26"
  property color baseForeground: "#c0caf5"
  property color baseAccent: "#7aa2f7"
  property color baseUrgent: "#f7768e"
  readonly property color background: source ? source.background : baseBackground
  readonly property color foreground: source ? source.foreground : baseForeground
  readonly property color accent: source ? source.accent : baseAccent
  readonly property color urgent: source ? source.urgent : baseUrgent
  readonly property var lock: source ? source.lock : ({
    text: foreground, textError: urgent, borderActive: accent,
    borderError: urgent, placeholder: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.5),
    selection: Qt.rgba(accent.r, accent.g, accent.b, 0.35)
  })
}
