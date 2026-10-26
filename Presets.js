.pragma library

// Ignore malformed entries when displaying/rotating; never rewrite the collection
// merely because it was read. The helper rejects malformed collections on writes.
function valid(p) {
  if (!p || typeof p !== "object" || typeof p.id !== "string" || !p.id.trim()
      || typeof p.name !== "string" || !p.name.trim() || p.name.length > 60
      || !p.branding || typeof p.branding !== "object" || Array.isArray(p.branding)) return false
  var b = p.branding
  var strings = ["brand", "logo", "symbol", "wordmarkText", "wordmarkStyle"]
  if (strings.some(function(k) { return b[k] !== undefined && typeof b[k] !== "string" })) return false
  if (b.tintLogo !== undefined && typeof b.tintLogo !== "boolean") return false
  if (b.symbolParts !== undefined && (!Array.isArray(b.symbolParts) || b.symbolParts.length > 2
      || b.symbolParts.some(function(v) { return typeof v !== "string" || !v.trim() }))) return false
  return true
}

function usable(items) {
  if (!Array.isArray(items)) return []
  var seen = {}
  return items.filter(function(p) {
    if (!valid(p) || Object.prototype.hasOwnProperty.call(seen, p.id)) return false
    Object.defineProperty(seen, p.id, {value: true, enumerable: true})
    return true
  })
}
