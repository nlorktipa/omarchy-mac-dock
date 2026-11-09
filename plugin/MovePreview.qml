import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// While the dock's divider is dragged, shows where the dock will land: a glow
// along that edge and a ghost of the dock there which flies out of the
// dock and follows the pointer from edge to edge. Drawn on its own surface,
// since the dock's window only covers the edge it sits on.
PanelWindow {
  id: preview

  required property var dockWindow

  readonly property string target: dockWindow.moveTarget
  // Moving to the edge the dock is already on is no move at all.
  readonly property bool armed: target !== "" && target !== dockWindow.position
  // Where the ghost is drawn: the target, or the dock itself until there is one.
  readonly property string side: armed ? target : dockWindow.position
  readonly property bool sideVertical: side === "left" || side === "right"

  screen: dockWindow.screen
  visible: dockWindow.movingDock && dockWindow.shown
  color: "transparent"
  WlrLayershell.namespace: "omarchy-dock-preview"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  // Covers the whole screen: kept clear of reserved space, it would also stop
  // short of the dock's own reserved edge and cut the ghost off there. The
  // room the dock gets is laid out by hand instead (area, below).
  exclusionMode: ExclusionMode.Ignore

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  // Visual only: an empty input region keeps the divider's pointer grab.
  mask: Region {}

  readonly property real ghostLength: dockWindow.restLength + dockWindow.padAlong * 2
  readonly property real ghostDepth: dockWindow.barDepth
  readonly property color accent: Commons.Color.accent

  // A short pop each time the target changes.
  onTargetChanged: if (armed) popAnim.restart()
  onVisibleChanged: {
    if (visible) Hyprland.refreshMonitors()
    else ghost.scale = 1
  }

  // What other surfaces such as the bar reserve on each edge: Hyprland's
  // reserved space (left, top, right, bottom) less the dock's own zone, which
  // goes with it when it moves.
  readonly property var reserved: {
    var m = dockWindow.monitor
    var r = m && m.lastIpcObject && m.lastIpcObject.reserved ? m.lastIpcObject.reserved : [0, 0, 0, 0]
    var own = dockWindow.reserving ? dockWindow.margin + dockWindow.barDepth : 0
    var pos = dockWindow.position
    return {
      left: Math.max(0, (r[0] || 0) - (pos === "left" ? own : 0)),
      top: Math.max(0, (r[1] || 0) - (pos === "top" ? own : 0)),
      right: Math.max(0, (r[2] || 0) - (pos === "right" ? own : 0)),
      bottom: Math.max(0, (r[3] || 0) - (pos === "bottom" ? own : 0))
    }
  }

  // The room the dock gets once moved, clear of the bar, so the ghost sits
  // exactly where the dock will.
  Item {
    id: area
    x: preview.reserved.left
    y: preview.reserved.top
    width: preview.width - preview.reserved.left - preview.reserved.right
    height: preview.height - preview.reserved.top - preview.reserved.bottom

    // ----------------------------------------------------------- edge glow
    Rectangle {
      id: glow

      readonly property real thickness: preview.ghostDepth * 2.2

      // Only for a move: while the dock would stay, its own window draws a
      // fainter glow behind the bar instead (DockWindow.qml).
      opacity: preview.armed ? 1 : 0
      x: preview.side === "right" ? area.width - thickness : 0
      y: preview.side === "bottom" ? area.height - thickness : 0
      width: preview.sideVertical ? thickness : area.width
      height: preview.sideVertical ? area.height : thickness

      gradient: Gradient {
        orientation: preview.sideVertical ? Gradient.Horizontal : Gradient.Vertical
        GradientStop {
          position: 0
          color: Util.alpha(preview.accent, preview.side === "left" || preview.side === "top" ? 0.32 : 0)
        }
        GradientStop {
          position: 1
          color: Util.alpha(preview.accent, preview.side === "left" || preview.side === "top" ? 0 : 0.32)
        }
      }

      Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
    }

    // ---------------------------------------------------------- ghost dock
    Item {
      id: ghost

      readonly property real len: preview.ghostLength
      readonly property real depth: preview.ghostDepth
      readonly property real margin: preview.dockWindow.margin

      x: preview.side === "left" ? margin
        : preview.side === "right" ? area.width - margin - depth
        : Math.round((area.width - len) / 2)
      y: preview.sideVertical ? Math.round((area.height - len) / 2)
        : preview.side === "top" ? margin
        : area.height - margin - depth
      width: preview.sideVertical ? depth : len
      height: preview.sideVertical ? len : depth
      opacity: preview.armed ? 1 : 0

      Behavior on x { NumberAnimation { duration: Style.duration(260); easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
      Behavior on y { NumberAnimation { duration: Style.duration(260); easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
      Behavior on width { NumberAnimation { duration: Style.duration(260); easing.type: Easing.OutCubic } }
      Behavior on height { NumberAnimation { duration: Style.duration(260); easing.type: Easing.OutCubic } }
      Behavior on opacity { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }

      SequentialAnimation {
        id: popAnim
        NumberAnimation { target: ghost; property: "scale"; to: 0.9; duration: Style.duration(70); easing.type: Easing.OutCubic }
        NumberAnimation { target: ghost; property: "scale"; to: 1; duration: Style.duration(260); easing.type: Easing.OutBack; easing.overshoot: 2 }
      }

      // The bar, its outline breathing while the drag is on.
      Rectangle {
        id: ghostBar
        anchors.fill: parent
        radius: preview.dockWindow.barRadius
        color: Util.alpha(preview.accent, 0.14)
        border.width: 2
        border.color: preview.accent

        SequentialAnimation on border.color {
          running: preview.visible && preview.armed
          loops: Animation.Infinite
          ColorAnimation { to: Util.alpha(preview.accent, 0.4); duration: Style.duration(650); easing.type: Easing.InOutSine }
          ColorAnimation { to: preview.accent; duration: Style.duration(650); easing.type: Easing.InOutSine }
        }
      }

      // A tile for every app and the apps button, with the divider between.
      Repeater {
        model: preview.dockWindow.appCount + 1

        delegate: Rectangle {
          required property int index

          readonly property real along: preview.dockWindow.padAlong + index * preview.dockWindow.slotSize
            + (index >= preview.dockWindow.appCount ? preview.dockWindow.separatorSize : 0)
            + preview.dockWindow.inset
          readonly property real across: preview.dockWindow.padAcross + preview.dockWindow.inset

          x: preview.sideVertical ? across : along
          y: preview.sideVertical ? along : across
          width: preview.dockWindow.iconSize
          height: preview.dockWindow.iconSize
          radius: width * 0.225
          color: Util.alpha(preview.accent, 0.1)
          border.width: 1
          border.color: Util.alpha(preview.accent, 0.55)
        }
      }

      Rectangle {
        readonly property real along: preview.dockWindow.padAlong
          + preview.dockWindow.appCount * preview.dockWindow.slotSize + preview.dockWindow.separatorSize / 2
        readonly property real across: ghost.depth * 0.2
        readonly property real span: ghost.depth * 0.6

        x: preview.sideVertical ? across : along - 1
        y: preview.sideVertical ? along - 1 : across
        width: preview.sideVertical ? span : 2
        height: preview.sideVertical ? 2 : span
        radius: 1
        color: preview.accent
      }

      // Names the edge, just inward of the ghost.
      Rectangle {
        readonly property real gapIn: Style.space(10)

        width: labelText.implicitWidth + Style.spacing.controlPaddingX * 2
        height: labelText.implicitHeight + Style.spacing.controlPaddingY * 2
        radius: height / 2
        color: preview.accent
        x: preview.side === "left" ? ghost.width + gapIn
          : preview.side === "right" ? -width - gapIn
          : Math.round((ghost.width - width) / 2)
        y: preview.side === "top" ? ghost.height + gapIn
          : preview.side === "bottom" ? -height - gapIn
          : Math.round((ghost.height - height) / 2)

        Text {
          id: labelText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: {
            var arrow = preview.side === "left" ? "←  " : preview.side === "right" ? "→  "
              : preview.side === "top" ? "↑  " : "↓  "
            var key = preview.side === "left" ? "dock.positionLeft"
              : preview.side === "right" ? "dock.positionRight"
              : preview.side === "top" ? "dock.positionTop" : "dock.positionBottom"
            return arrow + Commons.I18n.t(key)
          }
          color: Commons.Color.background
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
        }
      }
    }
  }
}
