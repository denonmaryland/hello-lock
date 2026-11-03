pragma Singleton
import QtQuick

QtObject {
  property var source: null
  readonly property var font: source ? source.font : ({family: "sans-serif", body: 14, subtitle: 18})
}
