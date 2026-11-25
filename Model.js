.pragma library

var MAX_TEXT_LENGTH = 160
var MAX_SETTINGS_BYTES = 4096

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

var WEBCAM_INITIAL_SIZES = ["small", "medium", "large"]

var WEBCAM_INITIAL_SIZE_MAP = {
  small: true,
  medium: true,
  large: true
}

var FPS_OPTIONS = [30, 60]

var FPS_MAP = {
  30: true,
  60: true
}

var RESOLUTION_OPTIONS = ["auto", "480p", "720p", "1080p"]

var RESOLUTION_MAP = {
  auto: "",
  "480p": "854x480",
  "720p": "1280x720",
  "1080p": "1920x1080"
}

var TOOL_COMMANDS = {
  ocr: "omarchy-capture-text",
  qr: "omarchy-capture-qr",
  color: "pkill hyprpicker || hyprpicker -a",
  transcode: "omarchy-transcode"
}

function hasOwn(obj, key) {
  return obj !== null && obj !== undefined && Object.prototype.hasOwnProperty.call(obj, key)
}

function defaultSettings() {
  return {
    annotateMode: false,
    recDesktopAudio: true,
    recMicAudio: false,
    recFullscreen: false,
    recWebcam: false,
    recFps: 60,
    recResolution: "auto",
    recWebcamSize: "medium"
  }
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

function normalizeFps(value) {
  var n = Number(value)
  return (isFinite(n) && hasOwn(FPS_MAP, String(n))) ? n : 60
}

function normalizeResolution(value) {
  var key = String(value || "").toLowerCase()
  return hasOwn(RESOLUTION_MAP, key) ? key : "auto"
}

function normalizeWebcamSize(value) {
  var key = String(value || "").toLowerCase()
  return hasOwn(WEBCAM_INITIAL_SIZE_MAP, key) ? key : "medium"
}

function parseDepsOutput(rawText) {
  var lines = String(rawText === undefined || rawText === null ? "" : rawText).split(/\r?\n/)
  var hasGsr = false
  var hasWfr = false
  var hasHyprpicker = false
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "gsr=1") hasGsr = true
    else if (line === "wfr=1") hasWfr = true
    else if (line === "hyprpicker=1") hasHyprpicker = true
  }
  var recorderBackend = hasGsr ? "gsr" : (hasWfr ? "wfr" : "none")
  return {
    recorderBackend: recorderBackend,
    hasRecorder: recorderBackend !== "none",
    supportsResolution: recorderBackend === "gsr",
    hasHyprpicker: hasHyprpicker
  }
}

function normalizeSettings(raw) {
  var defaults = defaultSettings()
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return defaults
  return {
    annotateMode: typeof raw.annotateMode === "boolean" ? raw.annotateMode : defaults.annotateMode,
    recDesktopAudio: typeof raw.recDesktopAudio === "boolean" ? raw.recDesktopAudio : defaults.recDesktopAudio,
    recMicAudio: typeof raw.recMicAudio === "boolean" ? raw.recMicAudio : defaults.recMicAudio,
    recFullscreen: typeof raw.recFullscreen === "boolean" ? raw.recFullscreen : defaults.recFullscreen,
    recWebcam: typeof raw.recWebcam === "boolean" ? raw.recWebcam : defaults.recWebcam,
    recFps: normalizeFps(raw.recFps),
    recResolution: normalizeResolution(raw.recResolution),
    recWebcamSize: normalizeWebcamSize(raw.recWebcamSize)
  }
}

function parseSettings(rawText) {
  var text = String(rawText === undefined || rawText === null ? "" : rawText)
  if (!text || text.length > MAX_SETTINGS_BYTES) return defaultSettings()
  try {
    return normalizeSettings(JSON.parse(text))
  } catch (e) {
    return defaultSettings()
  }
}

function serializeSettings(settings) {
  return JSON.stringify(normalizeSettings(settings), null, 2) + "\n"
}

function cycleFps(current) {
  return normalizeFps(current) === 60 ? 30 : 60
}

function cycleResolution(current) {
  var key = normalizeResolution(current)
  var idx = RESOLUTION_OPTIONS.indexOf(key)
  return RESOLUTION_OPTIONS[(idx + 1) % RESOLUTION_OPTIONS.length]
}

function cycleWebcamSize(current) {
  var key = normalizeWebcamSize(current)
  var idx = WEBCAM_INITIAL_SIZES.indexOf(key)
  return WEBCAM_INITIAL_SIZES[(idx + 1) % WEBCAM_INITIAL_SIZES.length]
}

function formatRecordBadge(resolution, fps, autoLabel) {
  var resKey = normalizeResolution(resolution)
  var resText = resKey === "auto"
    ? sanitizeText(autoLabel || "AUTO", 20).toUpperCase()
    : resKey
  var safeFps = normalizeFps(fps)
  return resText + " · " + safeFps + " FPS"
}

function isSafeAbsolutePath(value) {
  var s = String(value || "")
  if (s.length < 2 || s.charAt(0) !== "/") return false
  if (/[\x00-\x1F\x7F]/.test(s)) return false
  if (/(^|\/)\.\.(\/|$)/.test(s)) return false
  return true
}

function fileUrlToPath(urlValue) {
  var raw = String(urlValue || "")
  if (raw.indexOf("file://localhost/") === 0) {
    raw = raw.substring(16)
  } else if (raw.indexOf("file://") === 0) {
    raw = raw.substring(7)
  } else {
    return ""
  }
  var decoded
  try {
    decoded = decodeURIComponent(raw)
  } catch (e) {
    return ""
  }
  return isSafeAbsolutePath(decoded) ? decoded : ""
}

function resolveSettingsPath(stateHome, homeDir, filename) {
  var name = String(filename || "")
  if (!/^[a-zA-Z0-9._-]+$/.test(name) || name === "." || name === "..") return ""
  var base = ""
  if (isSafeAbsolutePath(stateHome)) {
    base = String(stateHome).replace(/\/+$/, "")
  } else if (isSafeAbsolutePath(homeDir)) {
    base = String(homeDir).replace(/\/+$/, "") + "/.local/state"
  } else {
    return ""
  }
  return base + "/omarchy/" + name
}

function shellQuote(value) {
  return "'" + String(value).replace(/'/g, "'\\''") + "'"
}

function buildScreenshotCommand(mode, annotate) {
  var key = String(mode || "")
  if (!hasOwn(SCREENSHOT_MODES, key)) return ""
  var cmd = "omarchy-capture-screenshot " + key
  if (annotate === true) cmd += " --editor=overlay"
  return cmd
}

function buildRecordCommand(opts) {
  var o = opts || {}
  if (o.stop === true) {
    return "omarchy-capture-screenrecording --stop-recording"
  }

  var flags = ""
  if (o.fullscreen === true) flags += " --fullscreen"
  if (o.desktopAudio === true) flags += " --with-desktop-audio"
  if (o.micAudio === true) flags += " --with-microphone-audio"
  if (o.webcam === true && o.hasWebcam === true) {
    flags += " --with-webcam"
    var webcamSize = normalizeWebcamSize(o.webcamSize)
    if (webcamSize !== "medium") {
      flags += " --webcam-size=" + webcamSize
    }
  }

  var resKey = normalizeResolution(o.resolution)
  var resDim = RESOLUTION_MAP[resKey]
  if (resDim) {
    flags += " --resolution=" + resDim
  }

  var fps = normalizeFps(o.fps)
  if (fps !== 60 && isSafeAbsolutePath(o.fpsScriptPath)) {
    return shellQuote(o.fpsScriptPath) + " " + fps + flags
  }

  return "omarchy-capture-screenrecording" + flags
}

function buildWebcamResizeCommand(sizeArg) {
  var key = String(sizeArg || "")
  if (!hasOwn(WEBCAM_SIZES, key)) return ""
  return "omarchy-capture-webcam-resize " + key
}

function buildToolCommand(toolId) {
  var key = String(toolId || "")
  return hasOwn(TOOL_COMMANDS, key) ? TOOL_COMMANDS[key] : ""
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
//  0..3   = screenshots (2x2)
//  4..5   = FPS selector (30 / 60, idle only)
//  6..9   = Resolution selector (Auto / 480p / 720p / 1080p, idle only)
// 10..13  = Video options (2x2: System audio, Microphone, Fullscreen, Webcam, idle only)
// 14..16  = Webcam initial size (S / M / L, idle + webcam enabled only)
// 17      = record start/stop button (full width)
// 18..21  = utility tools (2x2)
// 22..23  = quick folder links (2x1)
function activeRows(recording, showWebcamSize) {
  var rows = [
    [0, 1],
    [2, 3]
  ]
  if (!recording) {
    rows.push([4, 5])
    rows.push([6, 7, 8, 9])
    rows.push([10, 11])
    rows.push([12, 13])
    if (showWebcamSize) rows.push([14, 15, 16])
  }
  rows.push([17])
  rows.push([18, 19])
  rows.push([20, 21])
  rows.push([22, 23])
  return rows
}

function findSlot(rows, idx) {
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      if (rows[r][c] === idx) return { row: r, col: c }
    }
  }
  return null
}

function moveCursor(currentIndex, dx, dy, recording, showWebcamSize) {
  var idx = typeof currentIndex === "number" ? currentIndex : 0
  var rows = activeRows(recording === true, showWebcamSize === true)
  var pos = findSlot(rows, idx)

  if (!pos) {
    idx = (idx >= 4 && idx <= 16) ? 17 : 0
    pos = findSlot(rows, idx) || { row: 0, col: 0 }
  }

  if (dx !== 0) {
    var row = rows[pos.row]
    if (row.length <= 1) return row[0]
    var nextCol = (pos.col + (dx > 0 ? 1 : -1) + row.length) % row.length
    return row[nextCol]
  }

  if (dy !== 0) {
    var nextRowIdx = (pos.row + (dy > 0 ? 1 : -1) + rows.length) % rows.length
    var nextRow = rows[nextRowIdx]
    var currRow = rows[pos.row]
    if (nextRow.length === 1) return nextRow[0]
    if (currRow.length === 1) return nextRow[0]
    var ratio = currRow.length > 1 ? pos.col / (currRow.length - 1) : 0
    var mappedCol = Math.round(ratio * (nextRow.length - 1))
    return nextRow[Math.max(0, Math.min(nextRow.length - 1, mappedCol))]
  }

  return rows[pos.row][pos.col]
}
