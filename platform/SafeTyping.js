.pragma library

// Typing for text fields that never let Qt read the clipboard.
//
// A writable TextInput (and so a Controls TextField) reads the whole
// clipboard on every clipboard change, focused or not, to update canPaste.
// On Wayland that read has no size limit and runs on the shell's thread, so
// another program's clipboard offer can stall the shell or fill its memory
// (omacom/omarchy-plugin-marketplace#14051). Qt skips the read only for a
// readOnly field. So Hello Lock's Settings and Onboarding fields stay
// readOnly: true for good, and this does the editing a writable field would.
// Navigation, selection, Copy and Enter still come from TextInput itself:
// readOnly keeps them. Paste goes through bin/hello-paste (SafePaste.qml),
// which reads at most a few KB outside the shell.
//
// Use: readOnly: true; cursorVisible: activeFocus
//      Keys.onPressed: (event) => SafeTyping.key(field, event, paste)
// `paste` is a SafePaste (or null for no paste). Not supported: input
// methods (a readOnly field takes none), undo and redo.

// Characters a field may take: no C0/C1 controls, no format characters
// (bidi overrides, zero-width), no line or paragraph separators.
var UNSAFE = /[\u0000-\u001f\u007f-\u009f\u00ad\u061c\u180e\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff\ufff9-\ufffb]/g

function clean(s) {
  return String(s).replace(/[\r\n\t]+/g, " ").replace(UNSAFE, "")
}

// Whether `candidate` may stand in the field: its limit, then its validator
// as Qt would judge it while typing (Acceptable or Intermediate is fine,
// Invalid is not). insert() doesn't check the validator on a readOnly field,
// so the three kinds Hello Lock uses are checked here.
function allowed(field, candidate) {
  if (candidate.length > field.maximumLength) return false
  var v = field.validator
  if (!v || candidate === "") return true
  if (v.regularExpression !== undefined) {
    var re = new RegExp("^(?:" + v.regularExpression.source + ")$")
    return re.test(candidate)
  }
  if (v.bottom === undefined || v.top === undefined) return true
  var top = Number(v.top), bottom = Number(v.bottom)
  var sign = bottom < 0 ? "-?" : ""
  var whole = String(Math.floor(Math.max(Math.abs(top), Math.abs(bottom)))).length
  var number
  if (v.decimals !== undefined) {
    var places = v.decimals > 0 ? "(?:\\.\\d{0," + v.decimals + "})?" : ""
    if (!new RegExp("^" + sign + "\\d{0," + whole + "}" + places + "$").test(candidate)) return false
    number = Number(candidate.replace(/\.$/, ""))
  } else {
    if (!new RegExp("^" + sign + "\\d{1," + whole + "}$").test(candidate) && candidate !== "-") return false
    number = Number(candidate)
  }
  // Below the bottom can still grow into range ("0" before "0.5"); past the
  // top can't.
  if (isNaN(number)) return true
  return number >= 0 ? number <= top : number >= bottom
}

// Put `text` in place of start..end through the TextInput's own insert()
// and remove(), which send textEdited as typing does, then place the cursor.
function replace(field, start, end, text) {
  var current = field.text
  var candidate = current.slice(0, start) + text + current.slice(end)
  if (candidate === current || !allowed(field, candidate)) return false
  if (end > start) field.remove(start, end)
  if (text) field.insert(start, text)
  field.cursorPosition = start + text.length
  return true
}

// Insert where the cursor is, replacing the selection; as much as fits.
function insertText(field, s) {
  var text = clean(s)
  if (!text) return false
  var start = Math.min(field.selectionStart, field.selectionEnd)
  var end = Math.max(field.selectionStart, field.selectionEnd)
  if (start === end) start = end = field.cursorPosition
  var room = field.maximumLength - (field.text.length - (end - start))
  if (room <= 0) return false
  text = text.slice(0, room)
  // Don't end on half of a surrogate pair.
  if (/[\ud800-\udbff]$/.test(text)) text = text.slice(0, -1)
  return replace(field, start, end, text)
}

function erase(field, forward, word) {
  var start = Math.min(field.selectionStart, field.selectionEnd)
  var end = Math.max(field.selectionStart, field.selectionEnd)
  if (start !== end) return replace(field, start, end, "")
  var at = field.cursorPosition, text = field.text
  start = end = at
  if (forward) {
    if (at >= text.length) return false
    end = word ? at + (/^\s*\S*/.exec(text.slice(at))[0].length || 1) : at + 1
  } else {
    if (at <= 0) return false
    start = word ? at - (/\S*\s*$/.exec(text.slice(0, at))[0].length || 1) : at - 1
  }
  // Never split a surrogate pair (an emoji is two UTF-16 units).
  if (!word && !forward && start > 0 && /[\udc00-\udfff]/.test(text[start])) start--
  if (!word && forward && end < text.length && /[\udc00-\udfff]/.test(text[end])) end++
  return replace(field, start, end, "")
}

// Handle one key press. Leaves navigation, selection, Copy and Enter to the
// TextInput (event.accepted stays false), handles the rest.
function key(field, event, paste) {
  var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
  var alt = (event.modifiers & Qt.AltModifier) !== 0
  var meta = (event.modifiers & Qt.MetaModifier) !== 0
  var shift = (event.modifiers & Qt.ShiftModifier) !== 0
  if ((ctrl && event.key === Qt.Key_V) || (shift && event.key === Qt.Key_Insert)) {
    event.accepted = true
    if (paste && field.enabled) paste.into(field)
    return
  }
  if ((ctrl && event.key === Qt.Key_X) || (shift && event.key === Qt.Key_Delete)) {
    event.accepted = true
    if (field.selectedText) { field.copy(); erase(field, false, false) }
    return
  }
  if (event.key === Qt.Key_Backspace) { event.accepted = true; erase(field, false, ctrl); return }
  if (event.key === Qt.Key_Delete) { event.accepted = true; erase(field, true, ctrl); return }
  // Plain text, including AltGr and compose results. Shortcuts with Ctrl,
  // Alt or Super go on to the TextInput and the window.
  if (event.text && !ctrl && !meta && !alt && clean(event.text) === event.text) {
    event.accepted = true
    insertText(field, event.text)
  }
}
