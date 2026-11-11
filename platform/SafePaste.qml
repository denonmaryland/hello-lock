import QtQuick
import Quickshell.Io
import "SafeTyping.js" as SafeTyping

// Paste for SafeTyping fields. Qt's own paste reads the clipboard in the
// shell with no size limit; this asks bin/hello-paste instead, which runs
// wl-paste in its own process, reads at most 4096 bytes within one second,
// and prints one clean line (or nothing). The text is inserted when it
// arrives, if the same field still has the keyboard.
Process {
  id: paste
  property Item target: null
  // bin/ beside platform/, found from this file so no plugin path is needed.
  readonly property string helper: decodeURIComponent(
    Qt.resolvedUrl("../bin/hello-paste").toString().replace(/^file:\/\//, ""))

  // The text goes in once both the output and the exit code are in, in
  // whichever order they come.
  property int code: -1
  property bool done: false
  property string pasted: ""

  function into(field) {
    if (running || !field) return
    target = field
    code = -1; done = false; pasted = ""
    command = [helper]
    running = true
  }

  function finish() {
    if (code < 0 || !done) return
    var field = target
    target = null
    if (code === 0 && field && field.activeFocus && field.enabled)
      SafeTyping.insertText(field, pasted)
  }

  stdout: StdioCollector {
    waitForEnd: true
    onStreamFinished: { paste.pasted = String(text || ""); paste.done = true; paste.finish() }
  }
  onExited: function(exitCode) { paste.code = exitCode; paste.finish() }
}
