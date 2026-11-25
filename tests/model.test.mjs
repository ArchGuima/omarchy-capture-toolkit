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

test("buildScreenshotCommand enforces mode allowlist", () => {
  assert.equal(sandbox.buildScreenshotCommand("smart", false), "omarchy-capture-screenshot smart")
  assert.equal(sandbox.buildScreenshotCommand("fullscreen", true), "omarchy-capture-screenshot fullscreen --editor=overlay")
  assert.equal(sandbox.buildScreenshotCommand("windows", false), "omarchy-capture-screenshot windows")
  assert.equal(sandbox.buildScreenshotCommand("scroll", true), "omarchy-capture-screenshot scroll --editor=overlay")

  // Reject command injection and unknown modes
  assert.equal(sandbox.buildScreenshotCommand("smart; rm -rf /", false), "")
  assert.equal(sandbox.buildScreenshotCommand("$(id)", true), "")
  assert.equal(sandbox.buildScreenshotCommand("", false), "")
})

test("buildRecordCommand builds safe flags and gates webcam on hasWebcam", () => {
  assert.equal(
    sandbox.buildRecordCommand({ stop: true }),
    "omarchy-capture-screenrecording --stop-recording"
  )
  assert.equal(
    sandbox.buildRecordCommand({ fullscreen: true, desktopAudio: true, micAudio: true, webcam: true, hasWebcam: true }),
    "omarchy-capture-screenrecording --fullscreen --with-desktop-audio --with-microphone-audio --with-webcam"
  )
  assert.equal(
    sandbox.buildRecordCommand({ webcam: true, hasWebcam: false }),
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

test("moveCursor navigates idle and recording layouts cleanly", () => {
  // Idle: down through screenshots -> toggles -> record -> tools -> folders -> wrap
  assert.equal(sandbox.moveCursor(0, 0, 1, false), 2)
  assert.equal(sandbox.moveCursor(2, 0, 1, false), 4)
  assert.equal(sandbox.moveCursor(4, 0, 1, false), 6)
  assert.equal(sandbox.moveCursor(6, 0, 1, false), 8)
  assert.equal(sandbox.moveCursor(8, 0, 1, false), 9)
  assert.equal(sandbox.moveCursor(13, 0, 1, false), 0)

  // Recording: skips hidden toggle slots 4..7
  assert.equal(sandbox.moveCursor(2, 0, 1, true), 8)
  assert.equal(sandbox.moveCursor(8, 0, -1, true), 2)
  assert.equal(sandbox.moveCursor(5, 0, 1, true), 9)

  // Horizontal movement in 2-column rows
  assert.equal(sandbox.moveCursor(0, 1, 0, false), 1)
  assert.equal(sandbox.moveCursor(4, 1, 0, false), 5)
  assert.equal(sandbox.moveCursor(9, 1, 0, false), 10)
  assert.equal(sandbox.moveCursor(13, 1, 0, false), 14)
})
