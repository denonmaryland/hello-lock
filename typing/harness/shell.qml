import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

// Test bench for typing effects (see ../README.md). Not loaded by the plugin.
// HL_EFFECT = path to an effect .qml, HL_LOGO = logo image, HL_REDUCED = 1.
ShellRoot {
  id: shell
  readonly property string effectPath: Quickshell.env("HL_EFFECT") || ""
  readonly property string logoPath: Quickshell.env("HL_LOGO") || "/usr/share/omarchy/logo.svg"
  readonly property bool reduced: Quickshell.env("HL_REDUCED") === "1"
  readonly property bool tint: Quickshell.env("HL_TINT") !== "0"

  PanelWindow {
    id: win
    anchors.top: true
    margins.top: 120
    implicitWidth: 1000
    implicitHeight: 420
    color: "#0f1a2c"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "hello-lock-fx-harness"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property color accent: "#7aa2f7"
    readonly property color logoColor: "#dbe4f5"
    readonly property color errorColor: "#f7768e"

    Text {
      x: 14; y: 10
      text: "fx: " + shell.effectPath.split("/").pop() + (shell.reduced ? "  (reduced motion)" : "") + "   typed " + bench.typed + (fx.item && fx.item.busy ? "  busy" : "")
      color: "#6f86a8"; font.family: "Share Tech Mono"; font.pixelSize: 13
    }

    Item {
      id: box
      anchors.centerIn: parent
      width: parent.width * 0.78
      height: parent.height * 0.5

      Image {
        id: logoImage
        anchors.fill: parent
        source: "file://" + shell.logoPath
        fillMode: Image.PreserveAspectFit
        sourceSize.width: 1200
        visible: false
        layer.enabled: true
      }
      // The full-brightness, tinted logo handed to the effect as `source`.
      Item {
        id: fullLogo
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Item {
          id: silhouette
          anchors.fill: parent
          visible: false
          layer.enabled: true
          MultiEffect { anchors.fill: parent; source: logoImage; brightness: shell.tint ? 1 : 0 }
        }
        MultiEffect {
          anchors.fill: parent
          source: silhouette
          colorization: shell.tint ? 1 : 0
          colorizationColor: win.logoColor
        }
      }

      // Host glow and base logo, as LockView draws them.
      MultiEffect {
        anchors.fill: parent
        source: fullLogo
        opacity: fx.item ? fx.item.glowLevel * 0.9 : 0
        blurEnabled: true; blur: 1; blurMax: 48
        colorization: 1; colorizationColor: win.accent
      }
      MultiEffect {
        anchors.fill: parent
        source: fullLogo
        opacity: fx.item ? fx.item.baseOpacity : 1
      }

      Loader {
        id: fx
        anchors.fill: parent
        source: shell.effectPath ? "file://" + shell.effectPath : ""
        onLoaded: {
          item.source = fullLogo
          item.inkRect = Qt.binding(function() { return Qt.rect(logoImage.x + (logoImage.width - logoImage.paintedWidth) / 2, logoImage.y + (logoImage.height - logoImage.paintedHeight) / 2, logoImage.paintedWidth, logoImage.paintedHeight) })
          item.level = Qt.binding(function() { return bench.holding ? 1 : Math.min(bench.typed, 12) / 12 })
          item.typedLength = Qt.binding(function() { return bench.typed })
          item.holding = Qt.binding(function() { return bench.holding })
          item.reducedMotion = shell.reduced
          item.accent = win.accent
          item.logoColor = win.logoColor
          item.errorColor = win.errorColor
          item.reset()
        }
      }
    }

    // Password field stand-in.
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 26
      width: 240; height: 32; radius: 16
      color: "#162238"
      border.color: bench.failed ? win.errorColor : "#33476a"
      Text {
        anchors.centerIn: parent
        text: bench.holding ? "Checking…" : bench.failed ? "ACCESS DENIED" : "•".repeat(bench.typed)
        color: bench.failed ? win.errorColor : win.logoColor
        font.pixelSize: 14
      }
    }

    QtObject {
      id: bench
      property int typed: 0
      property bool holding: false
      property bool failed: false
      property int step: 0
      // [delay ms, action]
      readonly property var script: [
        [700, "t"], [160, "t"], [160, "t"], [160, "t"], [160, "t"], [160, "t"],
        [160, "t"], [160, "t"], [160, "t"], [160, "t"], [160, "t"], [160, "t"],
        [500, "b"], [130, "b"], [130, "b"], [300, "t"], [160, "t"], [160, "t"],
        [450, "submit"], [700, "fail"], [1300, "t"], [160, "t"], [160, "t"],
        [160, "t"], [160, "t"], [600, "clear"], [1100, "quit"]
      ]
      function run(action) {
        var e = fx.item
        if (action === "t") { failed = false; typed += 1; if (e) e.keystroke(typed, 1) }
        else if (action === "b") { typed -= 1; if (e) e.keystroke(typed, -1) }
        else if (action === "clear") { var n = typed; typed = 0; if (e) e.keystroke(0, -n) }
        else if (action === "submit") { holding = true; if (e) e.submit() }
        else if (action === "fail") { holding = false; typed = 0; failed = true; if (e) e.fail() }
        else if (action === "quit") Qt.quit()
      }
    }
    Timer {
      id: tick
      running: fx.status === Loader.Ready
      interval: bench.script[bench.step][0]
      onTriggered: {
        bench.run(bench.script[bench.step][1])
        if (bench.step < bench.script.length - 1) { bench.step += 1; restart() }
      }
    }
    Timer { running: fx.status === Loader.Error; interval: 1500; onTriggered: Qt.quit() }
  }
}
