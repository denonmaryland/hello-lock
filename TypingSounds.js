.pragma library

// Sound choice is independent of keys, password length and visual effect.
var families = ["pulse", "phase", "flux", "grain", "drift", "circuit"]
// Preserve choices saved with the earlier development pack.
var aliases = {wood: "pulse", clay: "phase", rubber: "flux", felt: "grain", relay: "circuit", pluck: "drift"}

function normalize(value) {
  if (typeof value === "string" && Object.prototype.hasOwnProperty.call(aliases, value)) value = aliases[value]
  return value === "off" || value === "shuffle" || families.indexOf(value) >= 0 ? value : "shuffle"
}

function draw(remaining, previous) {
  var bag = remaining.filter(function(name) { return families.indexOf(name) >= 0 })
  if (bag.length === 0) {
    bag = families.slice()
    for (var i = bag.length - 1; i > 0; i--) {
      var j = Math.floor(Math.random() * (i + 1))
      var swap = bag[i]; bag[i] = bag[j]; bag[j] = swap
    }
    if (bag[0] === previous) { var first = bag[0]; bag[0] = bag[bag.length - 1]; bag[bag.length - 1] = first }
  }
  return { family: bag.shift(), remaining: bag }
}
