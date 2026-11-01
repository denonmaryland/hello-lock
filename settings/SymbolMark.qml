import QtQuick

// The unlock symbol as the splash shows it: in the theme's foreground (unless
// it is an untinted logo) over a soft accent halo. `halo` fades the glow.
Item {
  id: mark
  property string source: ""
  property string source2: ""
  property bool tinted: true
  property color color: Theme.fg
  property color glowColor: Theme.accent
  property real halo: 1
  property real haloScale: 1
  property int version: 0
  width: 150
  height: 150

  Glow {
    anchors.centerIn: parent
    width: Math.max(mark.width, mark.height) * 2 * mark.haloScale
    height: width
    color: mark.glowColor
    opacity: mark.halo
    strength: 0.22
    midStrength: 0.07
    mid: 0.54
    reach: 0.96
  }
  LogoImage {
    anchors.fill: parent
    source: mark.source
    source2: mark.source2
    tinted: mark.tinted
    color: mark.color
    version: mark.version
  }
}
