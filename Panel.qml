import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "archguima.capture-toolkit"
  ipcTarget: "archguima.capture-toolkit"
  manageIpc: true

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgentColor: bar ? bar.urgent : Commons.Color.urgent
  readonly property color accentColor: Commons.Color.accent
  // Alpha-based dimming works cleanly on both dark and light Omarchy themes.
  readonly property color dimColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.65)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Recording & capture state (persisted via settingsFile)
  property bool recording: false
  property bool hasWebcam: false
  // Dependency probe state (defaults optimistic until initial probe finishes)
  property bool depsChecked: false
  property string recorderBackend: "gsr"
  property bool hasRecorder: true
  property bool supportsResolution: true
  property bool hasHyprpicker: true
  property bool annotateMode: false
  property bool recDesktopAudio: true
  property bool recMicAudio: false
  property bool recFullscreen: false
  // Persisted preference is kept separate from hardware availability so async
  // webcam detection never clobbers the saved setting on shell startup.
  property bool recWebcamPref: false
  readonly property bool recWebcam: root.hasWebcam && root.recWebcamPref
  property int recFps: 60
  property string recResolution: "auto"
  property string recWebcamSize: "medium"
  property bool settingsReady: false

  readonly property bool showWebcamSizeRow: !root.recording && root.recWebcam

  readonly property string settingsPath: Model.resolveSettingsPath(
    Quickshell.env("XDG_STATE_HOME"),
    Quickshell.env("HOME"),
    "capture-toolkit-settings.json"
  )

  readonly property string fpsScriptPath: Model.fileUrlToPath(
    Qt.resolvedUrl("scripts/record-with-fps.sh")
  )

  // Pending deferred command (runs after panel closes so overlay never blocks capture)
  property string pendingCommand: ""

  // Keyboard cursor across action slots (see Model.moveCursor):
  // 0..3 = screenshots, 4..5 = FPS, 6..9 = resolution,
  // 10..13 = video options (audio, mic, fullscreen, webcam),
  // 14..16 = webcam size, 17 = record action, 18..21 = tools, 22..23 = folders
  property bool cursorActive: false
  property int cursorIndex: 0

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  readonly property string barTooltipText: Model.sanitizeText(
    root.recording ? strings.t("bar.tooltipRecording") : strings.t("bar.tooltipIdle"),
    120
  )

  readonly property string recordBadgeText: Model.formatRecordBadge(
    root.supportsResolution ? root.recResolution : "auto",
    root.recFps,
    strings.t("rec.resAuto")
  )

  readonly property string missingDepsMessage: {
    if (!root.depsChecked) return ""
    if (!root.hasRecorder && !root.hasHyprpicker) return strings.t("deps.missingBoth")
    if (!root.hasRecorder) return strings.t("rec.missingDeps")
    if (!root.hasHyprpicker) return strings.t("tip.tool.missingHyprpicker")
    return ""
  }

  readonly property var screenshotActions: [
    { id: "region", icon: "󰩭", label: strings.t("shot.region"), tip: strings.t("tip.shot.region"), mode: "smart" },
    { id: "fullscreen", icon: "󰊓", label: strings.t("shot.fullscreen"), tip: strings.t("tip.shot.fullscreen"), mode: "fullscreen" },
    { id: "window", icon: "󰖯", label: strings.t("shot.window"), tip: strings.t("tip.shot.window"), mode: "windows" },
    { id: "scroll", icon: "󰹑", label: strings.t("shot.scroll"), tip: strings.t("tip.shot.scroll"), mode: "scroll" }
  ]

  readonly property var fpsOptions: [
    { value: 30, label: "30 FPS", tip: strings.t("tip.rec.fps30"), slotIndex: 4 },
    { value: 60, label: "60 FPS", tip: strings.t("tip.rec.fps60"), slotIndex: 5 }
  ]

  readonly property var resolutionOptions: [
    { value: "auto", label: strings.t("rec.resAuto"), tip: strings.t("tip.rec.resAuto"), slotIndex: 6 },
    { value: "480p", label: "480p", tip: strings.t("tip.rec.res480"), slotIndex: 7 },
    { value: "720p", label: "720p", tip: strings.t("tip.rec.res720"), slotIndex: 8 },
    { value: "1080p", label: "1080p", tip: strings.t("tip.rec.res1080"), slotIndex: 9 }
  ]

  readonly property var webcamSizeOptions: [
    { value: "small", label: strings.t("rec.camSmall"), tip: strings.t("tip.rec.camSize"), slotIndex: 14 },
    { value: "medium", label: strings.t("rec.camMedium"), tip: strings.t("tip.rec.camSize"), slotIndex: 15 },
    { value: "large", label: strings.t("rec.camLarge"), tip: strings.t("tip.rec.camSize"), slotIndex: 16 }
  ]

  readonly property var toolActions: [
    { id: "ocr", icon: "󰴑", label: strings.t("tool.ocr"), tip: strings.t("tip.tool.ocr") },
    { id: "qr", icon: "󰐲", label: strings.t("tool.qr"), tip: strings.t("tip.tool.qr") },
    { id: "color", icon: "󰃉", label: strings.t("tool.color"), tip: strings.t("tip.tool.color") },
    { id: "transcode", icon: "󰧸", label: strings.t("tool.transcode"), tip: strings.t("tip.tool.transcode") }
  ]

  function applySettings(rawText) {
    var s = Model.parseSettings(rawText)
    root.settingsReady = false
    root.annotateMode = s.annotateMode
    root.recDesktopAudio = s.recDesktopAudio
    root.recMicAudio = s.recMicAudio
    root.recFullscreen = s.recFullscreen
    root.recWebcamPref = s.recWebcam
    root.recFps = s.recFps
    root.recResolution = s.recResolution
    root.recWebcamSize = s.recWebcamSize
    root.settingsReady = true
  }

  function saveSettings() {
    if (!root.settingsReady || root.settingsPath === "") return
    settingsFile.setText(Model.serializeSettings({
      annotateMode: root.annotateMode,
      recDesktopAudio: root.recDesktopAudio,
      recMicAudio: root.recMicAudio,
      recFullscreen: root.recFullscreen,
      recWebcam: root.recWebcamPref,
      recFps: root.recFps,
      recResolution: root.recResolution,
      recWebcamSize: root.recWebcamSize
    }))
  }

  function setAnnotateMode(v) {
    root.annotateMode = v === true
    saveSettings()
  }

  function setRecDesktopAudio(v) {
    root.recDesktopAudio = v === true
    saveSettings()
  }

  function setRecMicAudio(v) {
    root.recMicAudio = v === true
    saveSettings()
  }

  function setRecFullscreen(v) {
    root.recFullscreen = v === true
    saveSettings()
  }

  function setRecWebcam(v) {
    if (!root.hasWebcam) return
    root.recWebcamPref = v === true
    if (!root.showWebcamSizeRow && root.cursorIndex >= 14 && root.cursorIndex <= 16) {
      root.cursorIndex = 13
    }
    saveSettings()
  }

  function setRecFps(value) {
    root.recFps = Model.normalizeFps(value)
    saveSettings()
  }

  function setRecResolution(value) {
    root.recResolution = Model.normalizeResolution(value)
    saveSettings()
  }

  function setRecWebcamSize(value) {
    root.recWebcamSize = Model.normalizeWebcamSize(value)
    saveSettings()
  }

  function refreshRecordingStatus() {
    if (!root.bar || statusProc.running) return
    statusProc.command = ["omarchy-capture-screenrecording", "--status"]
    statusProc.running = true
  }

  function refreshWebcamStatus() {
    if (!root.bar || webcamProc.running) return
    webcamProc.command = ["omarchy-hw-webcam"]
    webcamProc.running = true
  }

  function refreshDepsStatus() {
    if (!root.bar || depsProc.running) return
    depsProc.command = [
      "sh", "-c",
      "command -v gpu-screen-recorder >/dev/null 2>&1 && echo gsr=1 || echo gsr=0; " +
      "command -v wf-recorder >/dev/null 2>&1 && echo wfr=1 || echo wfr=0; " +
      "command -v hyprpicker >/dev/null 2>&1 && echo hyprpicker=1 || echo hyprpicker=0"
    ]
    depsProc.running = true
  }

  function runAfterClose(cmd) {
    if (!root.bar || !cmd) return
    if (!root.opened) {
      root.bar.run(cmd)
      return
    }
    root.pendingCommand = cmd
    root.close()
    launchTimer.restart()
  }

  function runScreenshot(mode) {
    var cmd = Model.buildScreenshotCommand(mode, root.annotateMode)
    if (cmd) runAfterClose(cmd)
  }

  function runTool(toolId) {
    if (toolId === "color" && root.depsChecked && !root.hasHyprpicker) return
    var cmd = Model.buildToolCommand(toolId)
    if (cmd) runAfterClose(cmd)
  }

  function toggleRecording() {
    if (!root.bar) return
    if (root.recording) {
      var stopCmd = Model.buildRecordCommand({ stop: true })
      root.close()
      root.bar.run(stopCmd)
      statusFollowupTimer.restart()
      return
    }
    if (root.depsChecked && !root.hasRecorder) return

    var startCmd = Model.buildRecordCommand({
      fullscreen: root.recFullscreen,
      desktopAudio: root.recDesktopAudio,
      micAudio: root.recMicAudio,
      webcam: root.recWebcam,
      hasWebcam: root.hasWebcam,
      webcamSize: root.recWebcamSize,
      resolution: root.supportsResolution ? root.recResolution : "auto",
      fps: root.recFps,
      fpsScriptPath: root.fpsScriptPath
    })
    runAfterClose(startCmd)
    statusFollowupTimer.restart()
  }

  function resizeWebcam(sizeArg) {
    if (!root.bar || !root.recording || !root.hasWebcam) return
    var cmd = Model.buildWebcamResizeCommand(sizeArg)
    if (cmd) root.bar.run(cmd)
  }

  function openFolder(kind) {
    if (!root.bar) return
    var cmd = Model.buildOpenFolderCommand(kind)
    if (!cmd) return
    root.close()
    root.bar.run(cmd)
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    cursorIndex = Model.moveCursor(cursorIndex, dx, dy, root.recording, root.showWebcamSizeRow)
  }

  function activateCursor() {
    if (!cursorActive) return
    if (cursorIndex >= 0 && cursorIndex <= 3) {
      runScreenshot(screenshotActions[cursorIndex].mode)
    } else if (!root.recording && (cursorIndex === 4 || cursorIndex === 5)) {
      if (root.hasRecorder) setRecFps(fpsOptions[cursorIndex - 4].value)
    } else if (!root.recording && cursorIndex >= 6 && cursorIndex <= 9) {
      var resOpt = resolutionOptions[cursorIndex - 6]
      if (root.hasRecorder && (resOpt.value === "auto" || root.supportsResolution)) {
        setRecResolution(resOpt.value)
      }
    } else if (!root.recording && cursorIndex === 10) {
      setRecDesktopAudio(!root.recDesktopAudio)
    } else if (!root.recording && cursorIndex === 11) {
      setRecMicAudio(!root.recMicAudio)
    } else if (!root.recording && cursorIndex === 12) {
      setRecFullscreen(!root.recFullscreen)
    } else if (!root.recording && cursorIndex === 13) {
      if (root.hasWebcam) setRecWebcam(!root.recWebcam)
    } else if (root.showWebcamSizeRow && cursorIndex >= 14 && cursorIndex <= 16) {
      setRecWebcamSize(webcamSizeOptions[cursorIndex - 14].value)
    } else if (cursorIndex === 17) {
      toggleRecording()
    } else if (cursorIndex >= 18 && cursorIndex <= 21) {
      runTool(toolActions[cursorIndex - 18].id)
    } else if (cursorIndex === 22) {
      openFolder("screenshots")
    } else if (cursorIndex === 23) {
      openFolder("videos")
    }
  }

  onOpenedChanged: {
    if (opened) {
      launchTimer.stop()
      pendingCommand = ""
      cursorActive = false
      cursorIndex = 0
      refreshRecordingStatus()
      refreshWebcamStatus()
      refreshDepsStatus()
      Qt.callLater(function() {
        if (panel.loadedContent) panel.loadedContent.forceActiveFocus()
      })
    }
  }

  onRecordingChanged: {
    if (recording && cursorIndex >= 4 && cursorIndex <= 16) {
      cursorIndex = 17
    }
  }

  onBarChanged: {
    refreshRecordingStatus()
    refreshWebcamStatus()
    refreshDepsStatus()
  }

  Component.onCompleted: {
    refreshRecordingStatus()
    refreshWebcamStatus()
    refreshDepsStatus()
  }

  Component.onDestruction: {
    launchTimer.stop()
    statusFollowupTimer.stop()
    statusPollTimer.stop()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.applySettings(text())
    onLoadFailed: root.settingsReady = true
  }

  Process {
    id: statusProc
    onExited: function(exitCode) {
      root.recording = exitCode === 0
    }
  }

  Process {
    id: webcamProc
    onExited: function(exitCode) {
      root.hasWebcam = exitCode === 0
      if (!root.showWebcamSizeRow && root.cursorIndex >= 14 && root.cursorIndex <= 16) {
        root.cursorIndex = 13
      }
    }
  }

  Process {
    id: depsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var deps = Model.parseDepsOutput(text)
        root.recorderBackend = deps.recorderBackend
        root.hasRecorder = deps.hasRecorder
        root.supportsResolution = deps.supportsResolution
        root.hasHyprpicker = deps.hasHyprpicker
        root.depsChecked = true
      }
    }
  }

  Timer {
    id: launchTimer
    interval: 150
    repeat: false
    onTriggered: {
      if (!root.opened && root.bar && root.pendingCommand !== "") {
        var cmd = root.pendingCommand
        root.pendingCommand = ""
        root.bar.run(cmd)
      }
    }
  }

  Timer {
    id: statusFollowupTimer
    interval: 1200
    repeat: false
    onTriggered: root.refreshRecordingStatus()
  }

  Timer {
    id: statusPollTimer
    interval: root.recording ? 2000 : 5000
    running: root.bar !== null && (root.recording || root.opened || root.visible)
    repeat: true
    onTriggered: root.refreshRecordingStatus()
  }

  // Local plain-text helper so every label obeys Omarchy UI safety guidelines.
  component PlainText: Text {
    textFormat: Text.PlainText
    font.family: root.fontFamily
    color: root.foreground
  }

  // Bounded tooltip using Omarchy's themed PanelToolTip so hover hints fit inside the panel.
  component HintToolTip: PanelToolTip {
    delay: 280
    fontFamily: root.fontFamily
    fontSize: Style.font.caption
    width: Math.min(implicitWidth, Style.space(220))
  }

  // Retro minimalist monospace toggle: Label on left, [×]/[ ] aligned right.
  // Set `flat: true` for clean borderless checkbox rows (hover/cursor still highlights).
  component RetroToggleChip: BorderSurface {
    id: chip
    property string label: ""
    property string tooltipText: ""
    property bool checked: false
    property bool chipEnabled: true
    property bool flat: false
    property int slotIndex: -1
    signal toggled()

    readonly property bool isHot: chipEnabled && ((slotIndex >= 0 && root.cursorActive && root.cursorIndex === slotIndex) || chipMouse.containsMouse)

    implicitWidth: Math.max(chipLabel.implicitWidth + Style.space(6) + chipCheck.implicitWidth + Style.space(14), Style.space(68))
    implicitHeight: Style.space(22)
    radius: Style.cornerRadius
    color: flat
      ? (isHot ? Style.controlFill(false, true, root.foreground, root.accentColor) : "transparent")
      : Style.controlFill(checked, isHot, root.foreground, root.accentColor)
    borderSpec: flat
      ? (isHot ? Border.controlSpec("hover-cursor", root.foreground, root.accentColor) : Border.none())
      : Border.controlSpec(
          isHot ? "hover-cursor" : (checked && Border.controlHasWidth("selected") ? "selected" : "normal"),
          root.foreground,
          root.accentColor
        )
    opacity: chipEnabled ? (checked ? 1.0 : 0.78) : 0.35

    Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

    Item {
      anchors.fill: parent
      anchors.leftMargin: (flat ? 0 : chip.borderLeft) + Style.space(6)
      anchors.rightMargin: (flat ? 0 : chip.borderRight) + Style.space(6)

      PlainText {
        id: chipLabel
        anchors.left: parent.left
        anchors.right: chipCheck.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: chip.label
        color: chip.checked ? root.foreground : root.dimColor
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      PlainText {
        id: chipCheck
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: chip.checked ? "[×]" : "[ ]"
        color: chip.checked ? root.accentColor : root.dimColor
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    HintToolTip {
      visible: root.opened && chip.tooltipText !== "" && chipMouse.containsMouse
      text: Model.sanitizeText(chip.tooltipText, 120)
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: chip.chipEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: {
        if (chip.chipEnabled && chip.slotIndex >= 0) {
          root.cursorActive = true
          root.cursorIndex = chip.slotIndex
        }
      }
      onClicked: {
        if (chip.chipEnabled) chip.toggled()
      }
    }
  }

  // Compact retro segmented option button (FPS, Resolution, Webcam size)
  component RetroOptionButton: BorderSurface {
    id: opt
    property string label: ""
    property string tooltipText: ""
    property bool selected: false
    property bool optEnabled: true
    property int slotIndex: -1
    signal chosen()

    readonly property bool isHot: optEnabled && ((slotIndex >= 0 && root.cursorActive && root.cursorIndex === slotIndex) || optMouse.containsMouse)

    implicitHeight: Style.space(22)
    radius: Style.cornerRadius
    color: Style.controlFill(optEnabled && selected, isHot, root.foreground, root.accentColor)
    borderSpec: Border.controlSpec(
      isHot ? "hover-cursor" : (optEnabled && selected && Border.controlHasWidth("selected") ? "selected" : "normal"),
      root.foreground,
      root.accentColor
    )
    opacity: optEnabled ? (selected ? 1.0 : 0.72) : 0.32

    Behavior on opacity { NumberAnimation { duration: Style.duration(100); easing.type: Easing.OutCubic } }

    PlainText {
      anchors.centerIn: parent
      width: Math.max(0, opt.width - opt.borderLeft - opt.borderRight - Style.space(6))
      horizontalAlignment: Text.AlignHCenter
      text: opt.label
      color: (opt.optEnabled && opt.selected) ? root.accentColor : root.dimColor
      font.pixelSize: Style.font.caption
      font.bold: opt.optEnabled && opt.selected
      elide: Text.ElideRight
    }

    HintToolTip {
      visible: root.opened && opt.tooltipText !== "" && optMouse.containsMouse
      text: Model.sanitizeText(opt.tooltipText, 120)
    }

    MouseArea {
      id: optMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: opt.optEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: {
        if (opt.optEnabled && opt.slotIndex >= 0) {
          root.cursorActive = true
          root.cursorIndex = opt.slotIndex
        }
      }
      onClicked: {
        if (opt.optEnabled) opt.chosen()
      }
    }
  }

  // Compact toolkit action tile with icon, clean label, and descriptive hover tooltip
  component ToolTile: BorderSurface {
    id: tile
    property string iconText: ""
    property string label: ""
    property string tooltipText: ""
    property bool tileEnabled: true
    property int slotIndex: -1
    signal triggered()

    readonly property bool isHot: tileEnabled && ((root.cursorActive && root.cursorIndex === slotIndex) || tileMouse.containsMouse)

    implicitHeight: Style.space(28)
    radius: Style.cornerRadius
    color: Style.controlFill(false, isHot, root.foreground, root.accentColor)
    borderSpec: Border.controlSpec(isHot ? "hover-cursor" : "normal", root.foreground, root.accentColor)
    opacity: tileEnabled ? 1.0 : 0.4

    Behavior on color { ColorAnimation { duration: Style.duration(100) } }

    Item {
      anchors.fill: parent
      anchors.leftMargin: tile.borderLeft + Style.space(7)
      anchors.rightMargin: tile.borderRight + Style.space(7)

      PlainText {
        id: tileIcon
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(15)
        horizontalAlignment: Text.AlignHCenter
        text: tile.iconText
        color: tile.isHot ? root.accentColor : root.foreground
        font.pixelSize: Style.font.iconSmall
      }

      PlainText {
        anchors.left: tileIcon.right
        anchors.leftMargin: Style.space(5)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: tile.label
        color: root.foreground
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    HintToolTip {
      visible: root.opened && tile.tooltipText !== "" && tileMouse.containsMouse
      text: Model.sanitizeText(tile.tooltipText, 120)
    }

    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: tile.tileEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: {
        if (tile.tileEnabled && tile.slotIndex >= 0) {
          root.cursorActive = true
          root.cursorIndex = tile.slotIndex
        }
      }
      onClicked: {
        if (tile.tileEnabled) tile.triggered()
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.recording ? "󰻂" : "󰄀"
    active: root.recording
    activeColor: root.urgentColor
    tooltipText: root.barTooltipText
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        if (root.recording) root.toggleRecording()
        else root.runScreenshot("smart")
      } else if (mouseButton === Qt.LeftButton) {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(288))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      implicitHeight: mainColumn.implicitHeight

      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(ch, modifiers) {
        if ((modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) !== 0) return
        var k = String(ch || "").toLowerCase()
        if (k === "1") root.runScreenshot("smart")
        else if (k === "2") root.runScreenshot("fullscreen")
        else if (k === "3") root.runScreenshot("windows")
        else if (k === "4") root.runScreenshot("scroll")
        else if (k === "e") root.setAnnotateMode(!root.annotateMode)
        else if (k === "a" && !root.recording) root.setRecDesktopAudio(!root.recDesktopAudio)
        else if (k === "m" && !root.recording) root.setRecMicAudio(!root.recMicAudio)
        else if (k === "f" && !root.recording) root.setRecFullscreen(!root.recFullscreen)
        else if (k === "w" && !root.recording && root.hasWebcam) root.setRecWebcam(!root.recWebcam)
        else if (k === "p" && !root.recording && root.hasRecorder) root.setRecFps(Model.cycleFps(root.recFps))
        else if (k === "s" && !root.recording && root.hasRecorder && root.supportsResolution) root.setRecResolution(Model.cycleResolution(root.recResolution))
        else if (k === "z" && root.showWebcamSizeRow) root.setRecWebcamSize(Model.cycleWebcamSize(root.recWebcamSize))
        else if (k === "r") root.toggleRecording()
        else if (k === "-" && root.recording && root.hasWebcam) root.resizeWebcam("smaller")
        else if (k === "0" && root.recording && root.hasWebcam) root.resizeWebcam("reset")
        else if ((k === "+" || k === "=") && root.recording && root.hasWebcam) root.resizeWebcam("larger")
        else if (k === "t") root.runTool("ocr")
        else if (k === "q") root.runTool("qr")
        else if (k === "c") root.runTool("color")
        else if (k === "v") root.runTool("transcode")
      }

      Column {
        id: mainColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(6)

        // ---------- Retro Header ----------
        Item {
          width: parent.width
          implicitHeight: Style.space(20)

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            PlainText {
              text: root.recording ? "󰻂" : "󰄀"
              color: root.recording ? root.urgentColor : root.accentColor
              font.pixelSize: Style.font.iconSmall
              anchors.verticalCenter: parent.verticalCenter
            }

            PlainText {
              text: strings.t("title").toUpperCase()
              color: root.foreground
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              font.letterSpacing: 1.2
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          BorderSurface {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: statusRow.implicitWidth + Style.space(10)
            implicitHeight: Style.space(18)
            radius: Style.cornerRadius
            color: root.recording
              ? Qt.rgba(root.urgentColor.r, root.urgentColor.g, root.urgentColor.b, 0.14)
              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
            borderSpec: Border.controlSpec(
              root.recording && Border.controlHasWidth("selected") ? "selected" : "normal",
              root.recording ? root.urgentColor : root.foreground,
              root.recording ? root.urgentColor : root.accentColor
            )

            Row {
              id: statusRow
              anchors.centerIn: parent
              spacing: Style.space(4)

              Rectangle {
                width: Style.space(5)
                height: Style.space(5)
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: root.recording ? root.urgentColor : root.dimColor

                SequentialAnimation on opacity {
                  running: root.recording && !Style.reduceMotion
                  loops: Animation.Infinite
                  NumberAnimation { to: 0.25; duration: Style.duration(650); easing.type: Easing.OutCubic }
                  NumberAnimation { to: 1.0; duration: Style.duration(650); easing.type: Easing.OutCubic }
                  onRunningChanged: if (!running) opacity = 1.0
                }
              }

              PlainText {
                text: root.recording ? strings.t("status.recording") : strings.t("status.ready")
                color: root.recording ? root.urgentColor : root.dimColor
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 0.8
              }
            }
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.foreground
        }

        // ---------- Screenshot Section ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(shotHeader.implicitHeight, annotateChip.implicitHeight)

          PanelSectionHeader {
            id: shotHeader
            text: strings.t("section.screenshot").toUpperCase()
            foreground: root.foreground
            fontFamily: root.fontFamily
            font.letterSpacing: 0.9
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          RetroToggleChip {
            id: annotateChip
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Math.max(Style.space(64), parent.width - shotHeader.implicitWidth - Style.space(8)))
            implicitHeight: Style.space(20)
            label: strings.t("toggle.annotate")
            tooltipText: strings.t("tip.toggle.annotate")
            checked: root.annotateMode
            onToggled: root.setAnnotateMode(!root.annotateMode)
          }
        }

        Grid {
          width: parent.width
          columns: 2
          columnSpacing: Style.space(4)
          rowSpacing: Style.space(4)

          Repeater {
            model: root.screenshotActions

            ToolTile {
              required property var modelData
              required property int index

              width: (mainColumn.width - Style.space(4)) / 2
              iconText: modelData.icon
              label: modelData.label
              tooltipText: modelData.tip
              slotIndex: index
              onTriggered: root.runScreenshot(modelData.mode)
            }
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.foreground
        }

        // ---------- Screen Record Section ----------
        Item {
          width: parent.width
          implicitHeight: recHeader.implicitHeight

          PanelSectionHeader {
            id: recHeader
            text: strings.t("section.record").toUpperCase()
            foreground: root.foreground
            fontFamily: root.fontFamily
            font.letterSpacing: 0.9
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          PlainText {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.recordBadgeText
            color: root.dimColor
            opacity: 0.85
            font.pixelSize: Style.font.caption
            font.letterSpacing: 0.6
          }
        }

        // FPS selector row (when idle)
        Row {
          visible: !root.recording
          width: parent.width
          spacing: Style.space(4)

          PlainText {
            width: Style.space(32)
            anchors.verticalCenter: parent.verticalCenter
            text: strings.t("rec.fpsLabel").toUpperCase()
            color: root.dimColor
            font.pixelSize: Style.font.caption
            font.letterSpacing: 0.7
            elide: Text.ElideRight
          }

          Repeater {
            model: root.fpsOptions

            RetroOptionButton {
              required property var modelData
              width: (mainColumn.width - Style.space(32) - Style.space(8)) / 2
              label: modelData.label
              tooltipText: modelData.tip
              selected: root.recFps === modelData.value
              optEnabled: root.hasRecorder
              slotIndex: modelData.slotIndex
              onChosen: root.setRecFps(modelData.value)
            }
          }
        }

        // Resolution selector row (when idle)
        Row {
          visible: !root.recording
          width: parent.width
          spacing: Style.space(4)

          PlainText {
            width: Style.space(32)
            anchors.verticalCenter: parent.verticalCenter
            text: strings.t("rec.resLabel").toUpperCase()
            color: root.dimColor
            font.pixelSize: Style.font.caption
            font.letterSpacing: 0.7
            elide: Text.ElideRight
          }

          Repeater {
            model: root.resolutionOptions

            RetroOptionButton {
              required property var modelData
              readonly property bool resSupported: modelData.value === "auto" || root.supportsResolution
              width: (mainColumn.width - Style.space(32) - Style.space(16)) / 4
              label: modelData.label
              tooltipText: resSupported ? modelData.tip : strings.t("tip.rec.resNeedsGsr")
              selected: (root.supportsResolution ? root.recResolution : "auto") === modelData.value
              optEnabled: root.hasRecorder && resSupported
              slotIndex: modelData.slotIndex
              onChosen: root.setRecResolution(modelData.value)
            }
          }
        }

        // Sub-header clarifying that options belong to the video recording
        PlainText {
          visible: !root.recording
          width: parent.width
          text: strings.t("rec.optionsLabel").toUpperCase()
          color: root.dimColor
          opacity: 0.78
          font.pixelSize: Style.font.caption
          font.letterSpacing: 0.7
          elide: Text.ElideRight
        }

        // Video options 2x2 grid (clean borderless checkboxes, when idle)
        Grid {
          visible: !root.recording
          width: parent.width
          columns: 2
          columnSpacing: Style.space(8)
          rowSpacing: Style.space(2)

          RetroToggleChip {
            width: (mainColumn.width - Style.space(8)) / 2
            flat: true
            label: strings.t("rec.audio")
            tooltipText: strings.t("tip.rec.audio")
            checked: root.recDesktopAudio
            slotIndex: 10
            onToggled: root.setRecDesktopAudio(!root.recDesktopAudio)
          }

          RetroToggleChip {
            width: (mainColumn.width - Style.space(8)) / 2
            flat: true
            label: strings.t("rec.mic")
            tooltipText: strings.t("tip.rec.mic")
            checked: root.recMicAudio
            slotIndex: 11
            onToggled: root.setRecMicAudio(!root.recMicAudio)
          }

          RetroToggleChip {
            width: (mainColumn.width - Style.space(8)) / 2
            flat: true
            label: strings.t("rec.fullscreen")
            tooltipText: strings.t("tip.rec.fullscreen")
            checked: root.recFullscreen
            slotIndex: 12
            onToggled: root.setRecFullscreen(!root.recFullscreen)
          }

          RetroToggleChip {
            width: (mainColumn.width - Style.space(8)) / 2
            flat: true
            label: strings.t("rec.webcam")
            tooltipText: root.hasWebcam ? strings.t("tip.rec.webcam") : strings.t("tip.rec.noWebcam")
            checked: root.recWebcam
            chipEnabled: root.hasWebcam
            slotIndex: 13
            onToggled: root.setRecWebcam(!root.recWebcam)
          }
        }

        // Initial webcam size row (only when webcam toggle is checked)
        Row {
          visible: root.showWebcamSizeRow
          width: parent.width
          spacing: Style.space(4)

          PlainText {
            width: Style.space(32)
            anchors.verticalCenter: parent.verticalCenter
            text: strings.t("rec.camSizeLabel").toUpperCase()
            color: root.dimColor
            font.pixelSize: Style.font.caption
            font.letterSpacing: 0.7
            elide: Text.ElideRight
          }

          Repeater {
            model: root.webcamSizeOptions

            RetroOptionButton {
              required property var modelData
              width: (mainColumn.width - Style.space(32) - Style.space(12)) / 3
              label: modelData.label
              tooltipText: modelData.tip
              selected: root.recWebcamSize === modelData.value
              slotIndex: modelData.slotIndex
              onChosen: root.setRecWebcamSize(modelData.value)
            }
          }
        }

        // Start / Stop Recording main action
        Button {
          id: recordBtn
          width: parent.width
          enabled: root.recording || !root.depsChecked || root.hasRecorder
          opacity: enabled ? 1.0 : 0.42
          iconText: root.recording ? "󰓛" : "󰻂"
          iconSize: Style.font.iconSmall
          text: root.recording ? strings.t("rec.stop") : strings.t("rec.start")
          tooltipText: Model.sanitizeText(
            root.recording
              ? strings.t("tip.rec.stop")
              : (root.depsChecked && !root.hasRecorder ? strings.t("rec.missingDeps") : strings.t("tip.rec.start")),
            120
          )
          fontSize: Style.font.caption
          foreground: root.recording ? root.urgentColor : root.foreground
          accent: root.recording ? root.urgentColor : root.accentColor
          fontFamily: root.fontFamily
          verticalPadding: Style.space(5)
          bordered: true
          selected: true
          hasCursor: root.cursorActive && root.cursorIndex === 17
          onClicked: root.toggleRecording()
          onHovered: function(h) {
            if (h) {
              root.cursorActive = true
              root.cursorIndex = 17
            }
          }
        }

        // Live webcam resize controls while recording
        Item {
          visible: root.recording && root.hasWebcam
          width: parent.width
          implicitHeight: Style.space(22)

          PlainText {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: strings.t("rec.webcamLabel").toUpperCase()
            color: root.dimColor
            font.pixelSize: Style.font.caption
            font.letterSpacing: 0.7
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Button {
              text: "−"
              tooltipText: Model.sanitizeText(strings.t("rec.webcamSmaller"), 80)
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.space(7)
              verticalPadding: Style.space(2)
              bordered: true
              onClicked: root.resizeWebcam("smaller")
            }

            Button {
              text: "1:1"
              tooltipText: Model.sanitizeText(strings.t("rec.webcamReset"), 80)
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.space(6)
              verticalPadding: Style.space(2)
              bordered: true
              onClicked: root.resizeWebcam("reset")
            }

            Button {
              text: "+"
              tooltipText: Model.sanitizeText(strings.t("rec.webcamLarger"), 80)
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.space(7)
              verticalPadding: Style.space(2)
              bordered: true
              onClicked: root.resizeWebcam("larger")
            }
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.foreground
        }

        // ---------- Utility Tools Section ----------
        PanelSectionHeader {
          text: strings.t("section.tools").toUpperCase()
          foreground: root.foreground
          fontFamily: root.fontFamily
          font.letterSpacing: 0.9
        }

        Grid {
          width: parent.width
          columns: 2
          columnSpacing: Style.space(4)
          rowSpacing: Style.space(4)

          Repeater {
            model: root.toolActions

            ToolTile {
              required property var modelData
              required property int index
              readonly property bool depOk: modelData.id !== "color" || !root.depsChecked || root.hasHyprpicker

              width: (mainColumn.width - Style.space(4)) / 2
              iconText: modelData.icon
              label: modelData.label
              tooltipText: depOk ? modelData.tip : strings.t("tip.tool.missingHyprpicker")
              tileEnabled: depOk
              slotIndex: 18 + index
              onTriggered: root.runTool(modelData.id)
            }
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.foreground
        }

        // ---------- Footer: Quick folders ----------
        Row {
          width: parent.width
          spacing: Style.space(4)

          Button {
            width: (mainColumn.width - Style.space(4)) / 2
            iconText: "󰉋"
            iconSize: Style.font.iconSmall
            text: strings.t("folder.screenshots")
            tooltipText: Model.sanitizeText(strings.t("tip.folder.screenshots"), 100)
            fontSize: Style.font.caption
            foreground: root.dimColor
            accent: root.accentColor
            fontFamily: root.fontFamily
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(2)
            hasCursor: root.cursorActive && root.cursorIndex === 22
            onClicked: root.openFolder("screenshots")
            onHovered: function(h) {
              if (h) {
                root.cursorActive = true
                root.cursorIndex = 22
              }
            }
          }

          Button {
            width: (mainColumn.width - Style.space(4)) / 2
            iconText: "󰕧"
            iconSize: Style.font.iconSmall
            text: strings.t("folder.videos")
            tooltipText: Model.sanitizeText(strings.t("tip.folder.videos"), 100)
            fontSize: Style.font.caption
            foreground: root.dimColor
            accent: root.accentColor
            fontFamily: root.fontFamily
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(2)
            hasCursor: root.cursorActive && root.cursorIndex === 23
            onClicked: root.openFolder("videos")
            onHovered: function(h) {
              if (h) {
                root.cursorActive = true
                root.cursorIndex = 23
              }
            }
          }
        }

        // ---------- Footer: Dependency error banner (theme urgent/error palette) ----------
        BorderSurface {
          visible: root.missingDepsMessage !== ""
          width: parent.width
          implicitHeight: missingDepRow.implicitHeight + Style.space(8)
          radius: Style.cornerRadius
          color: Qt.rgba(root.urgentColor.r, root.urgentColor.g, root.urgentColor.b, 0.12)
          borderSpec: Border.controlSpec("normal", root.urgentColor, root.urgentColor, root.urgentColor)

          Row {
            id: missingDepRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(7)
            anchors.rightMargin: Style.space(7)
            spacing: Style.space(6)

            PlainText {
              text: "󰀪"
              color: root.urgentColor
              font.pixelSize: Style.font.iconSmall
              anchors.verticalCenter: parent.verticalCenter
            }

            PlainText {
              width: parent.width - Style.space(22)
              text: root.missingDepsMessage
              color: root.urgentColor
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }
  }
}
