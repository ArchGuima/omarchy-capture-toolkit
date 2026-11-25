import QtQuick
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

  // Recording & capture state
  property bool recording: false
  property bool hasWebcam: false
  property bool annotateMode: false
  property bool recDesktopAudio: true
  property bool recMicAudio: false
  property bool recFullscreen: false
  property bool recWebcam: false

  // Pending deferred command (runs after panel closes so overlay never blocks capture)
  property string pendingCommand: ""

  // Keyboard cursor across action slots (see Model.moveCursor):
  // 0..3 = screenshots, 4..7 = record toggles (idle only), 8 = record action,
  // 9..12 = tools, 13..14 = folders
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

  readonly property var screenshotActions: [
    { id: "region", icon: "󰩭", key: "1", label: strings.t("shot.region"), mode: "smart" },
    { id: "fullscreen", icon: "󰊓", key: "2", label: strings.t("shot.fullscreen"), mode: "fullscreen" },
    { id: "window", icon: "󰖯", key: "3", label: strings.t("shot.window"), mode: "windows" },
    { id: "scroll", icon: "󰹑", key: "4", label: strings.t("shot.scroll"), mode: "scroll" }
  ]

  readonly property var toolActions: [
    { id: "ocr", icon: "󰴑", key: "t", label: strings.t("tool.ocr") },
    { id: "qr", icon: "󰐲", key: "q", label: strings.t("tool.qr") },
    { id: "color", icon: "󰃉", key: "c", label: strings.t("tool.color") },
    { id: "transcode", icon: "󰧸", key: "v", label: strings.t("tool.transcode") }
  ]

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

    var startCmd = Model.buildRecordCommand({
      fullscreen: root.recFullscreen,
      desktopAudio: root.recDesktopAudio,
      micAudio: root.recMicAudio,
      webcam: root.recWebcam,
      hasWebcam: root.hasWebcam
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
    cursorIndex = Model.moveCursor(cursorIndex, dx, dy, root.recording)
  }

  function activateCursor() {
    if (!cursorActive) return
    if (cursorIndex >= 0 && cursorIndex <= 3) {
      runScreenshot(screenshotActions[cursorIndex].mode)
    } else if (!root.recording && cursorIndex === 4) {
      root.recDesktopAudio = !root.recDesktopAudio
    } else if (!root.recording && cursorIndex === 5) {
      root.recMicAudio = !root.recMicAudio
    } else if (!root.recording && cursorIndex === 6) {
      root.recFullscreen = !root.recFullscreen
    } else if (!root.recording && cursorIndex === 7) {
      if (root.hasWebcam) root.recWebcam = !root.recWebcam
    } else if (cursorIndex === 8) {
      toggleRecording()
    } else if (cursorIndex >= 9 && cursorIndex <= 12) {
      runTool(toolActions[cursorIndex - 9].id)
    } else if (cursorIndex === 13) {
      openFolder("screenshots")
    } else if (cursorIndex === 14) {
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
      Qt.callLater(function() {
        if (panel.loadedContent) panel.loadedContent.forceActiveFocus()
      })
    }
  }

  onRecordingChanged: {
    if (recording && cursorIndex >= 4 && cursorIndex <= 7) {
      cursorIndex = 8
    }
  }

  onBarChanged: {
    refreshRecordingStatus()
    refreshWebcamStatus()
  }

  Component.onCompleted: {
    refreshRecordingStatus()
    refreshWebcamStatus()
  }

  Component.onDestruction: {
    launchTimer.stop()
    statusFollowupTimer.stop()
    statusPollTimer.stop()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

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
      if (!root.hasWebcam) root.recWebcam = false
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

  // Retro minimalist monospace checkbox chip: [×] Label / [ ] Label
  component RetroToggleChip: BorderSurface {
    id: chip
    property string label: ""
    property bool checked: false
    property bool chipEnabled: true
    property int slotIndex: -1
    signal toggled()

    readonly property bool isHot: chipEnabled && ((slotIndex >= 0 && root.cursorActive && root.cursorIndex === slotIndex) || chipMouse.containsMouse)
    readonly property real maxContentWidth: Math.max(0, chip.width - chip.borderLeft - chip.borderRight - Style.space(10))

    implicitWidth: Math.max(chipCheck.implicitWidth + Style.space(4) + chipLabel.implicitWidth + Style.space(12), Style.space(64))
    implicitHeight: Style.space(22)
    radius: Style.cornerRadius
    color: Style.controlFill(checked, isHot, root.foreground, root.accentColor)
    borderSpec: Border.controlSpec(
      isHot ? "hover-cursor" : (checked && Border.controlHasWidth("selected") ? "selected" : "normal"),
      root.foreground,
      root.accentColor
    )
    opacity: chipEnabled ? (checked ? 1.0 : 0.72) : 0.35

    Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

    Row {
      id: chipBox
      anchors.centerIn: parent
      spacing: Style.space(4)

      PlainText {
        id: chipCheck
        text: chip.checked ? "[×]" : "[ ]"
        color: chip.checked ? root.accentColor : root.dimColor
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      PlainText {
        id: chipLabel
        width: Math.min(implicitWidth, Math.max(0, chip.maxContentWidth - chipCheck.implicitWidth - chipBox.spacing))
        text: chip.label
        color: chip.checked ? root.foreground : root.dimColor
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: chip.chipEnabled
      cursorShape: chip.chipEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: {
        if (chip.slotIndex >= 0) {
          root.cursorActive = true
          root.cursorIndex = chip.slotIndex
        }
      }
      onClicked: chip.toggled()
    }
  }

  // Compact toolkit action tile with icon, label and discreet retro key hint
  component ToolTile: BorderSurface {
    id: tile
    property string iconText: ""
    property string label: ""
    property string keyHint: ""
    property int slotIndex: -1
    signal triggered()

    readonly property bool isHot: (root.cursorActive && root.cursorIndex === slotIndex) || tileMouse.containsMouse

    implicitHeight: Style.space(28)
    radius: Style.cornerRadius
    color: Style.controlFill(false, isHot, root.foreground, root.accentColor)
    borderSpec: Border.controlSpec(isHot ? "hover-cursor" : "normal", root.foreground, root.accentColor)

    Behavior on color { ColorAnimation { duration: Style.duration(100) } }

    Item {
      anchors.fill: parent
      anchors.leftMargin: tile.borderLeft + Style.space(7)
      anchors.rightMargin: tile.borderRight + Style.space(6)

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
        anchors.right: keyTag.visible ? keyTag.left : parent.right
        anchors.rightMargin: Style.space(3)
        anchors.verticalCenter: parent.verticalCenter
        text: tile.label
        color: root.foreground
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      PlainText {
        id: keyTag
        visible: tile.keyHint !== ""
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: tile.keyHint
        color: root.dimColor
        opacity: tile.isHot ? 0.95 : 0.5
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        if (tile.slotIndex >= 0) {
          root.cursorActive = true
          root.cursorIndex = tile.slotIndex
        }
      }
      onClicked: tile.triggered()
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
    contentWidth: panel.fittedContentWidth(Style.space(264))
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
        else if (k === "e") root.annotateMode = !root.annotateMode
        else if (k === "a" && !root.recording) root.recDesktopAudio = !root.recDesktopAudio
        else if (k === "m" && !root.recording) root.recMicAudio = !root.recMicAudio
        else if (k === "f" && !root.recording) root.recFullscreen = !root.recFullscreen
        else if (k === "w" && !root.recording && root.hasWebcam) root.recWebcam = !root.recWebcam
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
            checked: root.annotateMode
            onToggled: root.annotateMode = !root.annotateMode
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
              keyHint: modelData.key
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
            text: "60 FPS"
            color: root.dimColor
            opacity: 0.75
            font.pixelSize: Style.font.caption
            font.letterSpacing: 0.6
          }
        }

        // Recording options grid (when idle)
        Grid {
          visible: !root.recording
          width: parent.width
          columns: 2
          columnSpacing: Style.space(4)
          rowSpacing: Style.space(4)

          RetroToggleChip {
            width: (mainColumn.width - Style.space(4)) / 2
            label: strings.t("rec.audio")
            checked: root.recDesktopAudio
            slotIndex: 4
            onToggled: root.recDesktopAudio = !root.recDesktopAudio
          }

          RetroToggleChip {
            width: (mainColumn.width - Style.space(4)) / 2
            label: strings.t("rec.mic")
            checked: root.recMicAudio
            slotIndex: 5
            onToggled: root.recMicAudio = !root.recMicAudio
          }

          RetroToggleChip {
            width: (mainColumn.width - Style.space(4)) / 2
            label: strings.t("rec.fullscreen")
            checked: root.recFullscreen
            slotIndex: 6
            onToggled: root.recFullscreen = !root.recFullscreen
          }

          RetroToggleChip {
            width: (mainColumn.width - Style.space(4)) / 2
            label: strings.t("rec.webcam")
            checked: root.recWebcam
            chipEnabled: root.hasWebcam
            slotIndex: 7
            onToggled: root.recWebcam = !root.recWebcam
          }
        }

        // Start / Stop Recording main action
        Button {
          id: recordBtn
          width: parent.width
          iconText: root.recording ? "󰓛" : "󰻂"
          iconSize: Style.font.iconSmall
          text: root.recording ? strings.t("rec.stop") : strings.t("rec.start")
          fontSize: Style.font.caption
          foreground: root.recording ? root.urgentColor : root.foreground
          accent: root.recording ? root.urgentColor : root.accentColor
          fontFamily: root.fontFamily
          verticalPadding: Style.space(5)
          bordered: true
          selected: true
          hasCursor: root.cursorActive && root.cursorIndex === 8
          onClicked: root.toggleRecording()
          onHovered: function(h) {
            if (h) {
              root.cursorActive = true
              root.cursorIndex = 8
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

              width: (mainColumn.width - Style.space(4)) / 2
              iconText: modelData.icon
              label: modelData.label
              keyHint: modelData.key
              slotIndex: 9 + index
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
            fontSize: Style.font.caption
            foreground: root.dimColor
            accent: root.accentColor
            fontFamily: root.fontFamily
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(2)
            hasCursor: root.cursorActive && root.cursorIndex === 13
            onClicked: root.openFolder("screenshots")
            onHovered: function(h) {
              if (h) {
                root.cursorActive = true
                root.cursorIndex = 13
              }
            }
          }

          Button {
            width: (mainColumn.width - Style.space(4)) / 2
            iconText: "󰕧"
            iconSize: Style.font.iconSmall
            text: strings.t("folder.videos")
            fontSize: Style.font.caption
            foreground: root.dimColor
            accent: root.accentColor
            fontFamily: root.fontFamily
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(2)
            hasCursor: root.cursorActive && root.cursorIndex === 14
            onClicked: root.openFolder("videos")
            onHovered: function(h) {
              if (h) {
                root.cursorActive = true
                root.cursorIndex = 14
              }
            }
          }
        }
      }
    }
  }
}
