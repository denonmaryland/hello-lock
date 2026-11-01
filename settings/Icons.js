.pragma library

// Line icons from the Paper design, as SVG path data in a 24×24 box (circles
// and rounded rectangles written out as paths).
var user = "M8 8a4 4 0 1 0 8 0a4 4 0 1 0 -8 0M4 21c1.5-4 4.5-6 8-6s6.5 2 8 6"
var logo = "M12 3l8 4.5v9L12 21l-8-4.5v-9zM12 12l8-4.5M12 12v9M12 12L4 7.5"
var unlock = "M7 11h10a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2zM8 11V7a4 4 0 0 1 7.6-1.7"
var lock = "M7 11h10a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2zM8 11V7a4 4 0 0 1 8 0v4"
var keyboard = "M4 6h16a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2zM6 10h.01M10 10h.01M14 10h.01M18 10h.01M7 14h10"
var monitor = "M5 4h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zM8 20h8M12 16v4"
var sound = "M4 9v6h4l5 4V5L8 9zM16.5 9a4 4 0 0 1 0 6M19 6.5a8 8 0 0 1 0 11"
var layers = "M12 3l9 5-9 5-9-5zM3 13l9 5 9-5"
var cloud = "M7 18h10a4 4 0 0 0 .5-7.97A6 6 0 0 0 6 11a3.5 3.5 0 0 0 1 7z"
var close = "M6 6l12 12M18 6L6 18"
var check = "M20 6L9 17l-5-5"
var play = "M6 4l14 8-14 8z"
var pause = "M6 4h4v16H6zM14 4h4v16h-4z"
var stop = "M6 6h12v12H6z"
var calendar = "M5 5h14a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2zM3 10h18M8 3v4M16 3v4"
var shuffle = "M16 3h5v5M4 20L21 3M21 16v5h-5M15 15l6 6M4 4l5 5"
var folder = "M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"
var eye = "M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12zM9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0"
var backspace = "M21 5H9l-6 7 6 7h12a1 1 0 0 0 1-1V6a1 1 0 0 0-1-1zM12 9l6 6M18 9l-6 6"
var plus = "M12 5v14M5 12h14"
var chevronDown = "M6 9l6 6 6-6"
var caps = "M12 4l7 8h-4v6H9v-6H5z"
var expand = "M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"
var thisMachine = monitor
// Typing effects, for the effect list's thumbnails.
var effects = {
  shuffle: shuffle,
  cells: "M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z",
  scanline: "M4 6h16M4 10h16M4 14h16M4 18h9",
  liquid: "M7 4h10a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1zM6 13c2-1 4 1 6 0s4-1 6 0",
  decrypt: "M4 7h10M9 12h11M4 17h12",
  equalizer: "M5 20v-6M10 20V8M15 20v-9M20 20v-4",
  sweep: "M4 7h16a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V8a1 1 0 0 1 1-1zM12 7v10",
  pulse: "M9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0M4 12a8 8 0 1 0 16 0a8 8 0 1 0 -16 0",
  off: "M4 12a8 8 0 1 0 16 0a8 8 0 1 0 -16 0M8 12h8"
}
