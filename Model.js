.pragma library

var MAX_TEXT_LENGTH = 160

var SCREENSHOT_MODES = {
  smart: true,
  fullscreen: true,
  windows: true,
  scroll: true
}

var WEBCAM_SIZES = {
  smaller: true,
  larger: true,
  reset: true,
  small: true,
  medium: true,
  large: true
}

var TOOL_COMMANDS = {
  ocr: "omarchy-capture-text",
  qr: "omarchy-capture-qr",
  color: "pkill hyprpicker || hyprpicker -a",
  transcode: "omarchy-transcode"
}

// Neutralize markup-like characters and control bytes before passing text
// to any shared tooltip or notification sink.
function sanitizeText(value, maxLen) {
  var limit = maxLen > 0 ? maxLen : MAX_TEXT_LENGTH
  var s = String(value === undefined || value === null ? "" : value)
  s = s.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, "")
  s = s.replace(/[<>]/g, "")
  s = s.replace(/\s+/g, " ").trim()
  if (s.length > limit) s = s.slice(0, limit - 1) + "…"
  return s
}

function buildScreenshotCommand(mode, annotate) {
  var key = String(mode || "")
  if (!SCREENSHOT_MODES[key]) return ""
  var cmd = "omarchy-capture-screenshot " + key
  if (annotate === true) cmd += " --editor=overlay"
  return cmd
}

function buildRecordCommand(opts) {
  var o = opts || {}
  if (o.stop === true) {
    return "omarchy-capture-screenrecording --stop-recording"
  }
  var cmd = "omarchy-capture-screenrecording"
  if (o.fullscreen === true) cmd += " --fullscreen"
  if (o.desktopAudio === true) cmd += " --with-desktop-audio"
  if (o.micAudio === true) cmd += " --with-microphone-audio"
  if (o.webcam === true && o.hasWebcam === true) cmd += " --with-webcam"
  return cmd
}

function buildWebcamResizeCommand(sizeArg) {
  var key = String(sizeArg || "")
  if (!WEBCAM_SIZES[key]) return ""
  return "omarchy-capture-webcam-resize " + key
}

function buildToolCommand(toolId) {
  var key = String(toolId || "")
  return TOOL_COMMANDS[key] || ""
}

// POSIX-safe folder open commands: avoids sourcing user-dirs.dirs and requires
// an absolute path before calling mkdir/xdg-open to prevent flag injection.
function buildOpenFolderCommand(kind) {
  if (kind === "screenshots") {
    return "dir=\"${OMASNAP_SCREENSHOT_DIR:-${OMARCHY_SCREENSHOT_DIR:-$HOME/Pictures/Screenshots}}\"; case \"$dir\" in /*) mkdir -p -- \"$dir\" && xdg-open \"$dir\" ;; esac"
  }
  if (kind === "videos") {
    return "videos=\"$(xdg-user-dir VIDEOS 2>/dev/null || true)\"; dir=\"${OMARCHY_SCREENRECORD_DIR:-${videos:-$HOME/Videos}}\"; case \"$dir\" in /*) mkdir -p -- \"$dir\" && xdg-open \"$dir\" ;; esac"
  }
  return ""
}

// Cursor slots:
//  0..3  = screenshots (2x2)
//  4..7  = recording option toggles (2x2, visible only when !recording)
//  8     = record start/stop button (full width)
//  9..12 = utility tools (2x2)
// 13..14 = quick folder links (2x1)
function moveCursor(currentIndex, dx, dy, recording) {
  var idx = typeof currentIndex === "number" ? currentIndex : 0
  if (recording && idx >= 4 && idx <= 7) idx = 8

  if (dx !== 0) {
    if (idx >= 0 && idx <= 3) return (idx % 2 === 0) ? idx + 1 : idx - 1
    if (!recording && idx >= 4 && idx <= 7) return (idx % 2 === 0) ? idx + 1 : idx - 1
    if (idx >= 9 && idx <= 12) return ((idx - 9) % 2 === 0) ? idx + 1 : idx - 1
    if (idx === 13 || idx === 14) return idx === 13 ? 14 : 13
    return idx
  }

  if (dy > 0) {
    if (idx === 0 || idx === 1) return idx + 2
    if (idx === 2 || idx === 3) return recording ? 8 : idx + 2
    if (idx === 4 || idx === 5) return idx + 2
    if (idx === 6 || idx === 7) return 8
    if (idx === 8) return 9
    if (idx === 9 || idx === 10) return idx + 2
    if (idx === 11 || idx === 12) return idx === 11 ? 13 : 14
    return idx === 13 ? 0 : 1
  }

  if (dy < 0) {
    if (idx === 0 || idx === 1) return idx === 0 ? 13 : 14
    if (idx === 2 || idx === 3) return idx - 2
    if (idx === 4 || idx === 5) return idx - 2
    if (idx === 6 || idx === 7) return idx - 2
    if (idx === 8) return recording ? 2 : 6
    if (idx === 9 || idx === 10) return 8
    if (idx === 11 || idx === 12) return idx - 2
    if (idx === 13 || idx === 14) return idx === 13 ? 11 : 12
  }

  return idx
}
