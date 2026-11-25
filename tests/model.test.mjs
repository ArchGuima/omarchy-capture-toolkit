import test from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import vm from "node:vm"
import path from "node:path"
import { fileURLToPath } from "node:url"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const modelPath = path.resolve(__dirname, "../Model.js")

// Load QML .pragma library JS in an isolated VM context
const rawSource = fs.readFileSync(modelPath, "utf8").replace(/^\s*\.pragma\s+library\s*\r?\n/, "")
const sandbox = {}
vm.runInNewContext(rawSource, sandbox, { filename: "Model.js" })

test("sanitizeText strips markup, control chars, and enforces length limit", () => {
  assert.equal(
    sandbox.sanitizeText('<img src="https://example.invalid/tracker">Hello\x00\x07\nWorld', 80),
    'img src="https://example.invalid/tracker"Hello World'
  )
  assert.equal(sandbox.sanitizeText("<b>Alert</b>", 80), "bAlert/b")
  assert.equal(sandbox.sanitizeText("abcdefghij", 5), "abcd…")
  assert.equal(sandbox.sanitizeText(null, 20), "")
})

test("settings parsing and normalization enforce allowlists and bounds", () => {
  const parsed = sandbox.parseSettings(JSON.stringify({
    annotateMode: true,
    recDesktopAudio: false,
    recMicAudio: true,
    recFullscreen: true,
    recWebcam: true,
    recFps: 30,
    recResolution: "720p",
    recWebcamSize: "large"
  }))
  assert.deepEqual({ ...parsed }, {
    annotateMode: true,
    recDesktopAudio: false,
    recMicAudio: true,
    recFullscreen: true,
    recWebcam: true,
    recFps: 30,
    recResolution: "720p",
    recWebcamSize: "large"
  })

  // Malicious or invalid values fall back to safe defaults
  const sanitized = sandbox.parseSettings(JSON.stringify({
    annotateMode: "yes",
    recFullscreen: 1,
    recFps: "30; id",
    recResolution: "9999p; rm -rf /",
    recWebcamSize: "$(whoami)"
  }))
  assert.equal(sanitized.annotateMode, false)
  assert.equal(sanitized.recFullscreen, false)
  assert.equal(sanitized.recFps, 60)
  assert.equal(sanitized.recResolution, "auto")
  assert.equal(sanitized.recWebcamSize, "medium")

  // Corrupt, array, or oversized payloads fall back cleanly
  assert.deepEqual({ ...sandbox.parseSettings("{bad json") }, { ...sandbox.defaultSettings() })
  assert.deepEqual({ ...sandbox.parseSettings("[1, 2, 3]") }, { ...sandbox.defaultSettings() })
  assert.deepEqual({ ...sandbox.parseSettings("x".repeat(5000)) }, { ...sandbox.defaultSettings() })
})

test("prototype chain keys are rejected across all allowlists", () => {
  for (const protoKey of ["toString", "constructor", "__proto__", "valueOf", "hasOwnProperty"]) {
    assert.equal(sandbox.buildScreenshotCommand(protoKey, false), "")
    assert.equal(sandbox.buildWebcamResizeCommand(protoKey), "")
    assert.equal(sandbox.buildToolCommand(protoKey), "")
    assert.equal(sandbox.normalizeResolution(protoKey), "auto")
    assert.equal(sandbox.normalizeWebcamSize(protoKey), "medium")
    assert.equal(sandbox.normalizeFps(protoKey), 60)
  }
})

test("fileUrlToPath and resolveSettingsPath reject traversal, non-file URLs, and invalid paths", () => {
  assert.equal(
    sandbox.fileUrlToPath("file:///home/user/my%20plugins/scripts/record-with-fps.sh"),
    "/home/user/my plugins/scripts/record-with-fps.sh"
  )
  assert.equal(
    sandbox.fileUrlToPath("file://localhost/home/user/scripts/record-with-fps.sh"),
    "/home/user/scripts/record-with-fps.sh"
  )
  assert.equal(sandbox.fileUrlToPath("https://example.com/evil.sh"), "")
  assert.equal(sandbox.fileUrlToPath("file:///home/user/../etc/passwd"), "")
  assert.equal(sandbox.fileUrlToPath("file:///home/user/%E0%A4%A"), "")
  assert.equal(sandbox.fileUrlToPath("file:///home/user/bad%0Aline.sh"), "")

  assert.equal(
    sandbox.resolveSettingsPath("/custom/state/", "/home/user", "capture-toolkit-settings.json"),
    "/custom/state/omarchy/capture-toolkit-settings.json"
  )
  assert.equal(
    sandbox.resolveSettingsPath("relative/state", "/home/user/", "capture-toolkit-settings.json"),
    "/home/user/.local/state/omarchy/capture-toolkit-settings.json"
  )
  assert.equal(sandbox.resolveSettingsPath("", "", "capture-toolkit-settings.json"), "")
  assert.equal(sandbox.resolveSettingsPath("/tmp/../etc", "/tmp/../etc", "capture-toolkit-settings.json"), "")
  assert.equal(sandbox.resolveSettingsPath("/state", "/home/user", "../escape.json"), "")
})

test("parseDepsOutput detects gsr, wf-recorder fallback, missing recorder, and hyprpicker", () => {
  assert.deepEqual({ ...sandbox.parseDepsOutput("gsr=1\nwfr=0\nhyprpicker=1\n") }, {
    recorderBackend: "gsr",
    hasRecorder: true,
    supportsResolution: true,
    hasHyprpicker: true
  })
  assert.deepEqual({ ...sandbox.parseDepsOutput("gsr=0\nwfr=1\nhyprpicker=0\n") }, {
    recorderBackend: "wfr",
    hasRecorder: true,
    supportsResolution: false,
    hasHyprpicker: false
  })
  assert.deepEqual({ ...sandbox.parseDepsOutput("gsr=0\nwfr=0\nhyprpicker=1\n") }, {
    recorderBackend: "none",
    hasRecorder: false,
    supportsResolution: false,
    hasHyprpicker: true
  })
  assert.deepEqual({ ...sandbox.parseDepsOutput("unexpected garbage") }, {
    recorderBackend: "none",
    hasRecorder: false,
    supportsResolution: false,
    hasHyprpicker: false
  })
})

test("cycle helpers and badge formatting", () => {
  assert.equal(sandbox.cycleFps(60), 30)
  assert.equal(sandbox.cycleFps(30), 60)
  assert.equal(sandbox.cycleFps("bad"), 30)

  assert.equal(sandbox.cycleResolution("auto"), "480p")
  assert.equal(sandbox.cycleResolution("480p"), "720p")
  assert.equal(sandbox.cycleResolution("720p"), "1080p")
  assert.equal(sandbox.cycleResolution("1080p"), "auto")

  assert.equal(sandbox.cycleWebcamSize("small"), "medium")
  assert.equal(sandbox.cycleWebcamSize("medium"), "large")
  assert.equal(sandbox.cycleWebcamSize("large"), "small")

  assert.equal(sandbox.formatRecordBadge("auto", 60, "Auto"), "AUTO · 60 FPS")
  assert.equal(sandbox.formatRecordBadge("720p", 30, "Auto"), "720p · 30 FPS")
  assert.equal(sandbox.formatRecordBadge("auto", 30, "<b>Auto</b>"), "BAUTO/B · 30 FPS")
})

test("buildScreenshotCommand enforces mode allowlist", () => {
  assert.equal(sandbox.buildScreenshotCommand("smart", false), "omarchy-capture-screenshot smart")
  assert.equal(sandbox.buildScreenshotCommand("fullscreen", true), "omarchy-capture-screenshot fullscreen --editor=overlay")
  assert.equal(sandbox.buildScreenshotCommand("windows", false), "omarchy-capture-screenshot windows")
  assert.equal(sandbox.buildScreenshotCommand("scroll", true), "omarchy-capture-screenshot scroll --editor=overlay")

  assert.equal(sandbox.buildScreenshotCommand("smart; rm -rf /", false), "")
  assert.equal(sandbox.buildScreenshotCommand("$(id)", true), "")
  assert.equal(sandbox.buildScreenshotCommand("", false), "")
})

test("buildRecordCommand defaults to region and builds safe flags for fullscreen, FPS, resolution, and webcam size", () => {
  assert.equal(
    sandbox.buildRecordCommand({ stop: true }),
    "omarchy-capture-screenrecording --stop-recording"
  )

  // Default 60 FPS with fullscreen enabled
  assert.equal(
    sandbox.buildRecordCommand({
      fullscreen: true,
      desktopAudio: true,
      micAudio: true,
      webcam: true,
      hasWebcam: true,
      webcamSize: "large",
      resolution: "1080p",
      fps: 60,
      fpsScriptPath: "/home/user/.config/omarchy/plugins/test/scripts/record-with-fps.sh"
    }),
    "omarchy-capture-screenrecording --fullscreen --with-desktop-audio --with-microphone-audio --with-webcam --webcam-size=large --resolution=1920x1080"
  )

  // Default region mode (fullscreen false) at 30 FPS routes through safely quoted helper script
  assert.equal(
    sandbox.buildRecordCommand({
      fullscreen: false,
      desktopAudio: true,
      resolution: "480p",
      fps: 30,
      fpsScriptPath: "/home/user/my's/scripts/record-with-fps.sh"
    }),
    "'/home/user/my'\\''s/scripts/record-with-fps.sh' 30 --with-desktop-audio --resolution=854x480"
  )

  // 720p maps to 1280x720; Auto omits --resolution
  assert.equal(
    sandbox.buildRecordCommand({ resolution: "720p", fps: 60 }),
    "omarchy-capture-screenrecording --resolution=1280x720"
  )
  assert.equal(
    sandbox.buildRecordCommand({ resolution: "auto", fps: 60 }),
    "omarchy-capture-screenrecording"
  )

  // Invalid FPS, resolution, webcamSize, or unsafe script path are rejected/ignored
  assert.equal(
    sandbox.buildRecordCommand({
      webcam: true,
      hasWebcam: false,
      webcamSize: "small; id",
      resolution: "1080p; id",
      fps: 30,
      fpsScriptPath: "relative/path.sh"
    }),
    "omarchy-capture-screenrecording"
  )
  assert.equal(
    sandbox.buildRecordCommand({
      fps: 30,
      fpsScriptPath: "/tmp/bad\npath.sh"
    }),
    "omarchy-capture-screenrecording"
  )
})

test("buildWebcamResizeCommand enforces allowlist", () => {
  assert.equal(sandbox.buildWebcamResizeCommand("smaller"), "omarchy-capture-webcam-resize smaller")
  assert.equal(sandbox.buildWebcamResizeCommand("reset"), "omarchy-capture-webcam-resize reset")
  assert.equal(sandbox.buildWebcamResizeCommand("larger"), "omarchy-capture-webcam-resize larger")
  assert.equal(sandbox.buildWebcamResizeCommand("larger && id"), "")
})

test("buildToolCommand enforces allowlist", () => {
  assert.equal(sandbox.buildToolCommand("ocr"), "omarchy-capture-text")
  assert.equal(sandbox.buildToolCommand("qr"), "omarchy-capture-qr")
  assert.equal(sandbox.buildToolCommand("color"), "pkill hyprpicker || hyprpicker -a")
  assert.equal(sandbox.buildToolCommand("transcode"), "omarchy-transcode")
  assert.equal(sandbox.buildToolCommand("evil; id"), "")
})

test("buildOpenFolderCommand uses POSIX-safe path validation without sourcing files", () => {
  const shots = sandbox.buildOpenFolderCommand("screenshots")
  const vids = sandbox.buildOpenFolderCommand("videos")
  assert.ok(shots.includes("mkdir -p --"))
  assert.ok(vids.includes("xdg-user-dir VIDEOS"))
  assert.ok(!vids.includes("source "))
  assert.equal(sandbox.buildOpenFolderCommand("other"), "")
})

test("moveCursor navigates idle, webcam-size, and recording layouts cleanly", () => {
  // Idle without webcam size active:
  // 0 -> 2 -> 4 (FPS) -> 6 (Res) -> 10 (Audio) -> 12 (Fullscreen) -> 17 (Record) -> 18 (Tools) -> 20 -> 22 -> 0
  assert.equal(sandbox.moveCursor(0, 0, 1, false, false), 2)
  assert.equal(sandbox.moveCursor(2, 0, 1, false, false), 4)
  assert.equal(sandbox.moveCursor(4, 0, 1, false, false), 6)
  assert.equal(sandbox.moveCursor(6, 0, 1, false, false), 10)
  assert.equal(sandbox.moveCursor(10, 0, 1, false, false), 12)
  assert.equal(sandbox.moveCursor(12, 0, 1, false, false), 17)
  assert.equal(sandbox.moveCursor(17, 0, 1, false, false), 18)
  assert.equal(sandbox.moveCursor(18, 0, 1, false, false), 20)
  assert.equal(sandbox.moveCursor(20, 0, 1, false, false), 22)
  assert.equal(sandbox.moveCursor(22, 0, 1, false, false), 0)

  // Idle WITH webcam size active: 12 -> 14 (Cam S) -> 17 (Record)
  assert.equal(sandbox.moveCursor(12, 0, 1, false, true), 14)
  assert.equal(sandbox.moveCursor(14, 1, 0, false, true), 15)
  assert.equal(sandbox.moveCursor(16, 1, 0, false, true), 14)
  assert.equal(sandbox.moveCursor(14, 0, 1, false, true), 17)
  assert.equal(sandbox.moveCursor(17, 0, -1, false, true), 14)

  // Horizontal wrapping across 4-column resolution row
  assert.equal(sandbox.moveCursor(6, 1, 0, false, false), 7)
  assert.equal(sandbox.moveCursor(9, 1, 0, false, false), 6)
  assert.equal(sandbox.moveCursor(6, -1, 0, false, false), 9)

  // Recording skips all idle option rows (4..16)
  assert.equal(sandbox.moveCursor(2, 0, 1, true, false), 17)
  assert.equal(sandbox.moveCursor(17, 0, -1, true, false), 2)
  assert.equal(sandbox.moveCursor(6, 0, 1, true, false), 18)
})
