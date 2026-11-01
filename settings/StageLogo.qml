import QtQuick
import "Icons.js" as Icons

// 02 · Logo: the lock screen with the configured logo or wordmark, tinted as
// it will be. The transport switches an image between the theme's colours
// and its own (the same setting as "Match my theme colors").
Item {
  id: stage
  property Item s: null
  readonly property bool image: s.logoChoice === "image"
  readonly property bool wordmark: s.logoChoice === "wordmark"
  readonly property string fileName: s.imagePath ? s.imagePath.split("/").pop() : ""
  readonly property string tintHex: String(Theme.lockText).toUpperCase()

  function setTint(on) {
    if (!image || s.tintLogo === on) return
    s.tintLogo = on
    s.save({ tintLogo: on })
  }

  Column {
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -6
    spacing: 22

    ScreenFrame {
      bar: false
      lockStyle: true
      LockMock {
        id: mock
        anchors.fill: parent
        anchors.bottomMargin: 30
        logoSource: stage.s.logoPreview
        logoTinted: stage.s.logoTinted
        version: stage.s.previewVersion
        showClock: stage.s.clock
      }
      UiText {
        visible: stage.s.logoPreview === ""
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -40
        text: stage.s.wordmarkError ? "Can't draw that wordmark" : "Type a wordmark to see it here"
        color: Theme.muted
      }

      Transport {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
        scrubber: false
        label: stage.image ? (stage.s.tintLogo ? "Tinted to" : "Original colors") : "Always tinted"
        detail: stage.image && !stage.s.tintLogo ? "from the file" : "theme text · " + stage.tintHex
        // Theme colours or the logo's own (images only).
        Rectangle {
          height: 34
          width: compareRow.implicitWidth + 6
          radius: 9
          color: Theme.deep
          border.width: 1
          border.color: Theme.a(Theme.line, 0.6)
          opacity: stage.image ? 1 : 0.45
          Row {
            id: compareRow
            x: 3
            y: 3
            spacing: 3
            Repeater {
              model: [{ on: true, label: "Theme colors" }, { on: false, label: "Logo's own" }]
              Rectangle {
                id: compare
                required property var modelData
                readonly property bool selected: (stage.image ? stage.s.tintLogo : true) === modelData.on
                height: 26
                width: compareLabel.implicitWidth + 37
                radius: 6
                color: selected ? Theme.a(Theme.accent, 0.14) : compareMouse.containsMouse && stage.image ? Theme.a(Theme.line, 0.35) : "transparent"
                border.width: selected ? 1 : 0
                border.color: Theme.a(Theme.accent, 0.7)
                Behavior on color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
                Rectangle {
                  x: 11
                  anchors.verticalCenter: parent.verticalCenter
                  width: 8
                  height: 8
                  radius: 3
                  border.width: 1
                  border.color: Theme.a(Theme.muted, 0.4)
                  color: compare.modelData.on ? Theme.lockText : "transparent"
                  gradient: compare.modelData.on ? null : ownSwatch
                  Gradient {
                    id: ownSwatch
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Theme.accent }
                    GradientStop { position: 1; color: Theme.alert }
                  }
                }
                UiText {
                  id: compareLabel
                  x: 26
                  anchors.verticalCenter: parent.verticalCenter
                  text: compare.modelData.label
                  font.weight: compare.selected ? Font.DemiBold : Font.Medium
                  color: compare.selected ? Theme.accent : Theme.muted
                }
                MouseArea {
                  id: compareMouse
                  anchors.fill: parent
                  enabled: stage.image
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: stage.setTint(compare.modelData.on)
                }
              }
            }
          }
        }
      }
    }

    Placard {
      title: stage.wordmark ? (stage.s.wordmarkText.trim().toUpperCase() || "Wordmark")
        : stage.image ? (stage.s.brand.trim().toUpperCase() || stage.fileName.replace(/\.[^.]*$/, "") || "Your image")
        : "Omarchy"
      subtitle: stage.wordmark ? "WORDMARK · " + stage.s.wordmarkStyle.toUpperCase() + " STYLE"
        : stage.image ? "IMAGE · " + stage.fileName.toUpperCase()
        : "OMARCHY LOGO · BUILT IN"
      legend: [
        { label: "SOURCE", value: stage.wordmark ? "Your wordmark" : stage.image ? "Your image" : "Omarchy logo" },
        { label: "COLOR", value: stage.s.logoTinted ? "Matches theme" : "Logo's own", lit: true },
        { label: "WHILE TYPING", value: stage.s.typingEffect === "off" ? "Stays still"
          : stage.s.typingEffect === "shuffle" ? "A new effect each lock"
          : stage.s.typingEffects.filter(function(e) { return e.id === stage.s.typingEffect })[0].label + " fills it" }
      ]
    }
  }
}
