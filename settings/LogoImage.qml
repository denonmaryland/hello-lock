import QtQuick
import QtQuick.Effects

// A logo or symbol image fitted into its box: recoloured to `color` when
// `tinted` (any logo, black, white or coloured, becomes a solid silhouette),
// drawn as-is otherwise. `source2` is the inner part of a two-part custom
// symbol, drawn on top. Paths may be files or an in-memory wordmark.
Item {
  id: logo
  property string source: ""
  property string source2: ""
  property bool tinted: true
  property color color: Theme.lockText
  property int version: 0
  readonly property int status: image.status
  readonly property real aspect: image.implicitHeight > 0 ? image.implicitWidth / image.implicitHeight : 0
  readonly property real paintedWidth: image.paintedWidth
  readonly property real paintedHeight: image.paintedHeight

  Image {
    id: image
    anchors.fill: parent
    source: Theme.fileUrl(logo.source, logo.version)
    fillMode: Image.PreserveAspectFit
    sourceSize: Qt.size(Math.max(16, Math.round(logo.width * 2)), Math.max(16, Math.round(logo.height * 2)))
    asynchronous: true
    cache: false
    smooth: true
    visible: !logo.tinted
  }
  MultiEffect {
    anchors.fill: image
    source: image
    visible: logo.tinted && image.status === Image.Ready
    brightness: 1
    colorization: 1
    colorizationColor: logo.color
  }
  Image {
    id: image2
    anchors.fill: parent
    source: logo.source2 ? Theme.fileUrl(logo.source2, logo.version) : ""
    fillMode: Image.PreserveAspectFit
    sourceSize: image.sourceSize
    asynchronous: true
    cache: false
    visible: !logo.tinted && logo.source2 !== ""
  }
  MultiEffect {
    anchors.fill: image2
    source: image2
    visible: logo.tinted && logo.source2 !== "" && image2.status === Image.Ready
    brightness: 1
    colorization: 1
    colorizationColor: logo.color
  }
}
