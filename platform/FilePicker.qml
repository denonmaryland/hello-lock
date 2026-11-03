import QtQuick
import QtQuick.Dialogs

Item {
  id: picker
  signal chosen(string path)
  signal canceled()
  function open() { dialog.open() }
  FileDialog {
    id: dialog
    title: "Choose your logo"
    nameFilters: ["Images (*.svg *.png *.jpg *.jpeg *.webp)"]
    onAccepted: {
      var url = String(selectedFile)
      if (url.indexOf("file://") === 0) picker.chosen(decodeURIComponent(url.slice(7)))
      else picker.canceled()
    }
    onRejected: picker.canceled()
  }
}
