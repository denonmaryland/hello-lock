import QtQuick
import QtQuick.Effects
import "Icons.js" as Icons

// 04 · Typing: the lock screen with the real typing effect (typing/<name>.qml)
// on the logo, hosted as LockView and the setup's demo host it. "Type" and
// "Clear" (and the scrubber) feed it pretend keystroke counts: never any real
// input. With Shuffle selected each new run previews the next effect.
Item {
  id: stage
  property Item s: null
  readonly property string effectId: s.typingPreview === "shuffle" ? "cells" : s.typingPreview
  readonly property var effectInfo: s.typingEffects.filter(function(e) { return e.id === effectId })[0] || ({ label: effectId })
  readonly property var shufflePool: s.typingEffects.map(function(e) { return e.id }).filter(function(id) { return id !== "off" && id !== "shuffle" })
  readonly property int maxKeys: 12
  property int typed: 6
  property Loader effectLoader: null
  readonly property Item effect: effectLoader && effectLoader.status === Loader.Ready ? effectLoader.item : null
  readonly property var legends: ({
    cells: ["NEWEST CELLS", "Flash, then settle", "FULL LOGO", "At 12 characters"],
    scanline: ["BEAM", "Burns line by line", "FULL LOGO", "At 12 characters"],
    liquid: ["SURFACE", "Rises every key", "FULL LOGO", "At 12 characters"],
    decrypt: ["SLICES", "Snap into place", "FULL LOGO", "At 12 characters"],
    equalizer: ["BARS", "Rise and fall", "FULL LOGO", "At 12 characters"],
    sweep: ["METER", "Left to right", "FULL LOGO", "At 12 characters"],
    pulse: ["RIPPLE", "Every keystroke", "FILL", "None"],
    off: ["MOTION", "None", "LOGO", "Always still"]
  })
  readonly property var legend: legends[effectId] || legends.cells

  function key(delta) {
    typed = Math.max(0, Math.min(maxKeys, typed + delta))
    if (effect) effect.keystroke(typed, delta)
  }
  function type() {
    if (keyTimer.running) return
    if (typed >= maxKeys) clear()
    // Shuffle: a fresh run shows the next effect, as a new lock would.
    if (s.typingEffect === "shuffle" && typed === 0) {
      var i = shufflePool.indexOf(effectId)
      s.typingPreview = shufflePool[(i + 1) % shufflePool.length]
    }
    key(1)
    keyTimer.start()
  }
  function clear() {
    keyTimer.stop()
    if (typed > 0) key(-typed)
  }
  function seek(fraction) {
    keyTimer.stop()
    var n = Math.round(fraction * maxKeys)
    while (typed < n) key(1)
    while (typed > n) key(-1)
  }
  Timer {
    id: keyTimer
    interval: 120
    repeat: true
    onTriggered: { stage.key(1); if (stage.typed >= stage.maxKeys) stop() }
  }

  Column {
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -6
    spacing: 22

    ScreenFrame {
      bar: false
      lockStyle: true
      LockMock {
        anchors.fill: parent
        anchors.bottomMargin: 30
        logoSource: stage.s.logoPreview
        logoTinted: stage.s.logoTinted
        version: stage.s.previewVersion
        showClock: stage.s.clock
        dots: stage.typed
        typing: keyTimer.running
        glow: 0
        logo: effectLogo
      }

      Transport {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
        label: stage.effectInfo.label
        detail: keyTimer.running ? "Typing" : "Previewing"
        progress: stage.typed / stage.maxKeys
        time: stage.typed + " / " + stage.maxKeys + " keys"
        seekable: true
        onSeek: function(f) { stage.seek(f) }
        ActionButton {
          kind: "primary"
          implicitHeight: 34
          icon: Icons.keyboard
          text: "Type"
          onClicked: stage.type()
        }
        ActionButton {
          implicitHeight: 34
          icon: Icons.backspace
          text: "Clear"
          onClicked: stage.clear()
        }
      }
    }

    Placard {
      title: stage.effectInfo.label
      subtitle: "TYPING EFFECT · IN PREVIEW"
      legend: [
        { label: "SELECTED", value: stage.s.typingEffect === "shuffle" ? "Shuffle each lock" : stage.effectInfo.label },
        { label: stage.legend[0], value: stage.legend[1], lit: true },
        { label: stage.legend[2], value: stage.legend[3] }
      ]
    }
  }

  // The logo as the lock screen draws it while you type: a dim base, the
  // host's glow, and the effect on top. A missing or broken effect file
  // just leaves the plain logo.
  Component {
    id: effectLogo
    Item {
      id: host
      readonly property bool tinted: stage.s.logoTinted

      Image {
        id: previewImage
        anchors.fill: parent
        source: Theme.fileUrl(stage.s.logoPreview, stage.s.previewVersion)
        fillMode: Image.PreserveAspectFit
        sourceSize.width: Math.round(width * 1.5)
        cache: false
        visible: false
        layer.enabled: true
      }
      Item {
        id: silhouette
        anchors.fill: parent
        visible: false
        layer.enabled: true
        MultiEffect { anchors.fill: parent; source: previewImage; brightness: host.tinted ? 1 : 0 }
      }
      // The logo at full brightness and final colour: the effect's source.
      Item {
        id: fullLogo
        anchors.fill: parent
        visible: false
        layer.enabled: true
        MultiEffect {
          anchors.fill: parent
          source: silhouette
          autoPaddingEnabled: false
          colorization: host.tinted ? 1 : 0
          colorizationColor: Theme.lockText
        }
      }
      // Padded, so the glow and shadow have room (as LockView does it).
      ShaderEffectSource {
        id: padded
        readonly property real pad: Math.round(host.height * 0.3)
        x: -pad
        y: -pad
        width: host.width + pad * 2
        height: host.height + pad * 2
        sourceItem: silhouette
        sourceRect: Qt.rect(-pad, -pad, width, height)
        visible: false
      }
      MultiEffect {
        anchors.fill: padded
        source: padded
        autoPaddingEnabled: false
        visible: fx.item !== null && previewImage.status === Image.Ready
        opacity: fx.item ? fx.item.glowLevel * 0.9 : 0
        blurEnabled: true
        blur: 1
        blurMax: 48
        colorization: 1
        colorizationColor: Theme.accent
      }
      MultiEffect {
        anchors.fill: padded
        source: padded
        autoPaddingEnabled: false
        visible: previewImage.status === Image.Ready
        opacity: fx.item ? fx.item.baseOpacity : 1
        colorization: host.tinted ? 1 : 0
        colorizationColor: Theme.lockText
        shadowEnabled: true
        shadowColor: Theme.accent
        shadowOpacity: 0.35
        shadowBlur: 1
      }
      Loader {
        id: fx
        anchors.fill: parent
        active: stage.effectId !== "off" && stage.effectId !== ""
        source: active ? Qt.resolvedUrl("../typing/" + stage.effectId + ".qml") : ""
        Component.onCompleted: stage.effectLoader = fx
        onStatusChanged: if (status === Loader.Error) console.warn("hello-lock settings: typing effect " + stage.effectId + " failed to load")
        onLoaded: {
          item.source = fullLogo
          item.inkRect = Qt.binding(function() {
            return Qt.rect((previewImage.width - previewImage.paintedWidth) / 2, (previewImage.height - previewImage.paintedHeight) / 2,
                           previewImage.paintedWidth, previewImage.paintedHeight)
          })
          item.level = Qt.binding(function() { return Math.min(stage.typed, 12) / 12 })
          item.typedLength = Qt.binding(function() { return stage.typed })
          item.holding = false
          item.reducedMotion = Qt.binding(function() { return Theme.calm })
          item.accent = Qt.binding(function() { return Theme.accent })
          item.logoColor = Qt.binding(function() { return Theme.lockText })
          item.errorColor = Qt.binding(function() { return Theme.alert })
          item.reset()
          // Bring a new effect to the current count, a key at a time.
          for (var i = 1; i <= stage.typed; i++) item.keystroke(i, 1)
        }
      }
    }
  }
}
