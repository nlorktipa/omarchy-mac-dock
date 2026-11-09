import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "DockModel.js" as DockModel

// One screen's dock, drawn the macOS way: a frosted, rounded bar the icons sit
// on, icons that swell under the pointer and push their neighbours aside, a dot
// under every running app, the app's name over the icon under the pointer, and
// a bounce while an app starts.
//
// Behaviour (pins, drag to reorder, menus, auto-hide, the app grid) is the stock
// Omarchy dock's. The window stays mapped and only hides its contents, so
// leaving fullscreen does not wait on a fresh layer surface.
// While hidden the mask is empty and clicks fall through to the windows below.
//
// Geometry is worked out along the dock ("along": x for a horizontal dock, y
// for a vertical one) and away from the screen edge ("inward"). Slots have a
// fixed resting layout, which drags and drops reckon with; magnification only
// warps where those resting positions are drawn, so it never feeds back into
// what is under the pointer.
PanelWindow {
  id: window
  // Right-to-left languages read this window mirrored.
  Binding { target: window.contentItem; property: "LayoutMirroring.enabled"; value: Commons.I18n.rightToLeft }
  Binding { target: window.contentItem; property: "LayoutMirroring.childrenInherit"; value: true }

  property var dock: null

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property string position: dock ? dock.position : "bottom"
  readonly property bool vertical: dock ? dock.vertical : false
  readonly property var monitor: Hyprland.monitorFor(screen)
  readonly property var workspace: monitor ? monitor.activeWorkspace : null
  readonly property int workspaceId: workspace ? workspace.id : -1
  // The most fullscreen window on the workspace, as Hyprland counts it: 1 is
  // maximized, and 2 or 3 fullscreen.
  readonly property int fullscreenMode: {
    var mode = 0
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var toplevel = toplevels[i]
      if (!toplevel.workspace || toplevel.workspace.id !== workspaceId) continue
      var ipc = toplevel.lastIpcObject
      mode = Math.max(mode, ipc && ipc.fullscreen ? ipc.fullscreen : 0)
    }
    return mode
  }
  // The dock shows on every workspace, tiled or floating, and only steps aside
  // for a fullscreen window.
  readonly property bool shown: !!dock && fullscreenMode < 2
  // Whether the dock holds its edge clear of windows, as the bar does. Not
  // while auto-hide is on: the dock then slides over the windows instead.
  readonly property bool keptShown: !!dock && !dock.autohide
  readonly property bool reserving: shown && keptShown
  // With auto-hide on, the dock waits off screen until the pointer reaches its
  // edge, and stays while the pointer, a menu, or a drag still needs it. A
  // maximized window hides the dock the same way, so it can still be called up,
  // unless the dock holds its edge clear, so it covers nothing.
  readonly property bool autohide: !!dock && (dock.autohide || (fullscreenMode === 1 && !reserving))
  property bool revealed: false
  readonly property bool menuOpen: menuItem !== null || settingsMenu
  readonly property bool tucked: autohide && !(revealed || menuOpen || dragging || movingDock || insertIndex >= 0)
  readonly property bool contentShown: shown && !tucked

  // ------------------------------------------------------------- options
  // Read from the `dock.mac` object in ~/.config/omarchy/shell.json.
  readonly property var mac: dock && dock.dockConfig && typeof dock.dockConfig.mac === "object" && dock.dockConfig.mac
    ? dock.dockConfig.mac : ({})

  function option(value, fallback, low, high) {
    var n = Number(value)
    if (value === undefined || value === null || value === "" || !isFinite(n)) return fallback
    return Math.max(low, Math.min(high, n))
  }

  // Icon size in pixels; left unset it follows the shell's font scale.
  readonly property int iconSize: Math.round(mac.iconSize !== undefined
    ? option(mac.iconSize, 48, 16, 160)
    : 48 * Style.fontScale)
  // How large the icon under the pointer grows; 1 turns magnification off.
  readonly property real maxScale: option(mac.magnification, 1.7, 1, 3)
  // How see-through the bar is: 0 is clear, 1 solid.
  readonly property real barOpacity: option(mac.opacity, 0.45, 0, 1)
  readonly property bool labels: mac.labels !== false
  readonly property bool runningDots: mac.dots !== false
  readonly property bool bounceOnLaunch: mac.bounce !== false

  // ------------------------------------------------------------ geometry
  // Room around each icon inside its slot.
  readonly property int inset: Math.max(2, Math.round(iconSize * 0.06))
  readonly property int slotSize: iconSize + inset * 2
  // The bar's padding around its slots.
  readonly property int padAcross: Math.max(3, Math.round(iconSize * 0.12))
  readonly property int padAlong: Math.max(3, Math.round(iconSize * 0.12))
  readonly property int barDepth: slotSize + padAcross * 2
  readonly property int barRadius: Math.round(barDepth * 0.3)
  // Distance between the bar and the screen edge.
  readonly property int margin: Math.max(4, Math.round(iconSize * 0.15))
  readonly property int separatorSize: Math.max(8, Math.round(iconSize * 0.36))
  readonly property int dotSize: Math.max(3, Math.round(iconSize * 0.085))
  // How far from the pointer magnification reaches, in resting pixels.
  readonly property real range: slotSize * 2.6
  readonly property int gap: Style.spacing.xs
  // Room inward of the dock for its menus (the tallest, the apps button's, has
  // five rows), for magnified icons, and for the label over them.
  readonly property int popupRoom: Style.spacing.popupRowHeight * 5 + Style.spacing.sm * 2 + Style.normalBorderWidth * 2 + gap * 2
  readonly property int overflowRoom: Math.ceil((maxScale - 1) * slotSize)
  readonly property int labelRoom: window.vertical ? 240 : Style.spacing.popupRowHeight + Style.space(16)
  // Menus open over magnified icons, so their room starts past the overflow.
  readonly property int innerRoom: Math.max(overflowRoom + Style.space(2) + popupRoom, overflowRoom + labelRoom, Math.round(iconSize * 0.5) + labelRoom)

  readonly property int appCount: appRepeater.count
  // The resting strip: the apps, a separator, then the button for every app.
  readonly property real appsStart: appCount * slotSize + (appCount > 0 ? separatorSize : 0)
  readonly property real restLength: appsStart + slotSize
  readonly property real alongLength: vertical ? height : width
  readonly property real restStart: Math.round((alongLength - restLength) / 2)

  // ------------------------------------------------------- magnification
  // Where the pointer is along the resting strip, and whether it is over the
  // dock. Kept while a menu is open, so the icons hold still under it.
  property real pointerAlong: 0
  property bool pointerInside: false
  readonly property bool magnifyOn: maxScale > 1.01 && contentShown && !dragging && !movingDock && insertIndex < 0
    && ((pointerInside && !hoverStale) || menuOpen)
  property real magnify: magnifyOn ? 1 : 0
  Behavior on magnify {
    NumberAnimation { duration: Style.duration(window.magnifyOn ? 140 : 200); easing.type: Easing.OutCubic }
  }

  // Maps a resting position along the strip to where it is drawn. Each
  // resting pixel is stretched by 1 + (maxScale - 1) * g, where g falls from
  // 1 under the pointer to 0 at `range` on a cosine; this is that stretch,
  // integrated out from the pointer. The point under the pointer stays put,
  // and everything else is pushed away from it.
  function warp(u) {
    var m = (window.maxScale - 1) * window.magnify
    if (m <= 0) return u
    var d = u - window.pointerAlong
    var ad = Math.abs(d)
    var r = window.range
    var grown = ad < r ? (ad + r / Math.PI * Math.sin(Math.PI * ad / r)) / 2 : r / 2
    return u + m * (d < 0 ? -grown : grown)
  }

  // Room opened in the bar for an app dragged in from the app grid.
  property real insertGrow: insertIndex >= 0 ? slotSize : 0
  Behavior on insertGrow {
    enabled: window.animateShifts
    NumberAnimation { duration: Style.duration(150); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
  }

  // The bar's ends along the strip, relative to the resting start. The
  // padding is warped too, so the bar keeps its margin round a magnified end.
  readonly property real barStart: warp(-padAlong) - insertGrow / 2
  readonly property real barEnd: warp(restLength + padAlong) + insertGrow / 2

  // How far the dock is tucked past its edge. Auto-hide slides it, but only
  // while the dock is on screen: coming back from fullscreen shows it where it
  // belongs at once.
  property real tuck: window.tucked ? margin + barDepth + Style.space(2) : 0
  Behavior on tuck {
    id: tuckMotion
    enabled: window.shown
    NumberAnimation {
      duration: Style.duration(tuckMotion.targetValue > 0 ? 140 : 200)
      easing.type: Easing.OutCubic
    }
  }

  // Moves `v` pixels away from the screen edge.
  function inwardX(v) { return position === "left" ? v : position === "right" ? -v : 0 }
  function inwardY(v) { return position === "top" ? v : position === "bottom" ? -v : 0 }

  // ------------------------------------------------------- drag and drop
  // The app being dragged along the dock, how far the pointer has taken it,
  // and the slot it would land in.
  property int dragIndex: -1
  property int dropIndex: -1
  property real dragOffset: 0
  readonly property bool dragging: dragIndex >= 0
  // Off while a drop resets the slots: they snap to where the reorder puts
  // them rather than sliding back from where they stepped aside. Set before
  // the drag state changes, so the slots never see the reset animated.
  property bool animateShifts: true
  // After a drop the slots have moved under a pointer that has not, so what
  // they think is hovered is stale until it moves again.
  property bool hoverStale: false
  // In window coordinates.
  property point dropPoint
  // Where an app dragged in from the app grid would land, or -1.
  property int insertIndex: -1

  // Where this window sits on its screen, which a point from the app grid's
  // fullscreen surface is given in: against its edge, clear of the space
  // other surfaces such as the bar reserve. Hyprland lists that space as
  // left, top, right, bottom.
  function origin() {
    var reserved = monitor && monitor.lastIpcObject && monitor.lastIpcObject.reserved ? monitor.lastIpcObject.reserved : [0, 0, 0, 0]
    var left = reserved[0] || 0, top = reserved[1] || 0, right = reserved[2] || 0, bottom = reserved[3] || 0
    var x = window.position === "right" ? screen.width - right - window.width : left
    var y = window.position === "bottom" ? screen.height - bottom - window.height : top
    return Qt.point(x, y)
  }

  // An app from the app grid lands where the pointer is, once it is over the
  // dock or close to it on the inward side.
  function moveExternalDrag(screenX, screenY) {
    var at = window.origin()
    var px = screenX - at.x
    var py = screenY - at.y
    var along = (window.vertical ? py : px) - window.restStart
    var inward = window.position === "bottom" ? window.height - py
      : window.position === "top" ? py
      : window.position === "left" ? px
      : window.width - px
    var near = along >= -window.slotSize && along <= window.restLength + window.slotSize
      && inward <= window.margin + window.barDepth + window.slotSize
    if (window.shown && window.autohide && near) window.revealed = true
    window.insertIndex = window.shown && near ? window.slotIndexAt(along) : -1
  }

  function dropExternalDrag(screenX, screenY, key) {
    window.moveExternalDrag(screenX, screenY)
    window.settleShifts()
    if (window.insertIndex >= 0 && key && window.dock) window.dock.pinAt(key, window.insertIndex)
    window.endExternalDrag()
  }

  function endExternalDrag() {
    window.insertIndex = -1
    if (window.autohide) hideTimer.restart()
  }

  // ------------------------------------------------------- moving the dock
  // Dragging the divider carries the dock to another edge, as on macOS: it
  // snaps to whichever screen edge the pointer is nearest when released. The edge only changes on release, because
  // re-anchoring the window mid-drag would cut off the pointer it is reading.
  property bool movingDock: false
  // The edge the dock would land on, or "" while the drag is too short.
  property string moveTarget: ""

  // A point in window coordinates, on the screen.
  function screenPoint(at) {
    var o = window.origin()
    return Qt.point(o.x + at.x, o.y + at.y)
  }

  function edgeNearest(p) {
    var toLeft = p.x
    var toRight = screen.width - p.x
    var toTop = p.y
    var toBottom = screen.height - p.y
    var nearest = Math.min(toLeft, toRight, toTop, toBottom)
    if (nearest === toBottom) return "bottom"
    if (nearest === toTop) return "top"
    return nearest === toLeft ? "left" : "right"
  }

  // The slot a resting position along the strip falls before.
  function slotIndexAt(along) {
    return Math.max(0, Math.min(window.appCount, Math.round(along / window.slotSize)))
  }

  property var menuItem: null
  property Item menuSlot: null
  // The apps button's menu: where the dock sits and whether it hides.
  property bool settingsMenu: false

  onShownChanged: {
    if (shown) return
    closeMenu()
    window.revealed = false
    window.pointerInside = false
  }

  function openMenu(item, slot) {
    window.settingsMenu = false
    window.menuItem = item
    window.menuSlot = slot
  }

  function openSettingsMenu(slot) {
    window.menuItem = null
    window.settingsMenu = true
    window.menuSlot = slot
  }

  function settleShifts() {
    window.animateShifts = false
    Qt.callLater(function() { window.animateShifts = true })
  }

  function endDrag() {
    window.settleShifts()
    window.hoverStale = true
    window.dragIndex = -1
    window.dropIndex = -1
    window.dragOffset = 0
  }

  function closeMenu() {
    window.menuItem = null
    window.settingsMenu = false
    window.menuSlot = null
    if (window.autohide) hideTimer.restart()
  }

  // Places the menu inward of the dock and its magnified icons, centered on a
  // slot.
  function popupX(slot, popup) {
    if (!slot) return 0
    if (window.position === "left") return stage.x + stage.width + window.gap
    if (window.position === "right") return stage.x - window.gap - popup.width
    var center = slot.mapToItem(window.contentItem, slot.width / 2, 0).x
    return Math.max(window.gap, Math.min(window.width - popup.width - window.gap, center - popup.width / 2))
  }

  function popupY(slot, popup) {
    if (!slot) return 0
    if (window.position === "top") return stage.y + stage.height + window.gap
    if (window.position === "bottom") return stage.y - window.gap - popup.height
    var center = slot.mapToItem(window.contentItem, 0, slot.height / 2).y
    return Math.max(window.gap, Math.min(window.height - popup.height - window.gap, center - popup.height / 2))
  }

  visible: !remapGuard.remapping
  color: "transparent"
  // Kept as the stock name so Omarchy's own layer rules, and the blur rule
  // from hypr/macdock.lua, apply to it.
  WlrLayershell.namespace: "omarchy-dock"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  // Kept clear of the bar's reserved edge. While it stays on screen it reserves
  // the resting bar and its margin (not the room kept for magnification and
  // menus), so windows stop short of it.
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: window.reserving ? window.margin + window.barDepth : 0

  anchors {
    top: window.position !== "bottom"
    bottom: window.position !== "top"
    left: window.position !== "right"
    right: window.position !== "left"
  }

  implicitWidth: window.vertical ? window.margin + window.barDepth + window.innerRoom : 0
  implicitHeight: window.vertical ? 0 : window.margin + window.barDepth + window.innerRoom

  mask: Region {
    item: window.contentShown ? stage : null

    Region { item: window.shown && window.autohide ? edgeTrigger : null }
    Region { item: menu.visible ? menu : null }
  }

  onAutohideChanged: window.revealed = false

  Timer {
    id: hideTimer
    // Long enough to cross a gap between the edge and the icons, no longer.
    interval: 150
    onTriggered: {
      if (!stageHover.hovered && !edgeHover.hovered && !window.menuOpen && !window.dragging && !window.movingDock) window.revealed = false
    }
  }

  // The strip along the screen edge that brings an auto-hidden dock back.
  Item {
    id: edgeTrigger

    readonly property int depth: window.margin + Style.spacing.xxs

    x: window.position === "left" ? 0 : window.position === "right" ? window.width - depth : stage.x
    y: window.position === "top" ? 0 : window.position === "bottom" ? window.height - depth : stage.y
    width: window.vertical ? depth : stage.width
    height: window.vertical ? stage.height : depth

    HoverHandler {
      id: edgeHover
      onHoveredChanged: {
        if (hovered) window.revealed = true
        else hideTimer.restart()
      }
    }
  }

  ScreenMoveRemap {
    id: remapGuard
    window: window
  }

  // Where a drag of the divider will put the dock (MovePreview.qml).
  MovePreview {
    dockWindow: window
  }

  HyprlandFocusGrab {
    active: window.menuOpen
    windows: [window]
    onCleared: window.closeMenu()
  }

  // While the divider is held and the dock would stay put, a faint glow along
  // its own edge, drawn here behind the bar rather than over it. Kept under
  // the blur rule's ignore_alpha (hypr/macdock.lua) so it is never frosted.
  Rectangle {
    id: stayGlow

    readonly property bool vertical: window.vertical
    readonly property real thickness: window.margin + window.barDepth * 1.4
    readonly property bool staying: window.movingDock
      && (window.moveTarget === "" || window.moveTarget === window.position)
    readonly property color tint: Util.alpha(Commons.Color.accent, 0.09)
    readonly property color clear: Util.alpha(Commons.Color.accent, 0)
    readonly property bool fromStart: window.position === "left" || window.position === "top"

    visible: opacity > 0
    opacity: staying && window.shown ? 1 : 0
    x: window.position === "right" ? window.width - thickness : 0
    y: window.position === "bottom" ? window.height - thickness : 0
    width: vertical ? thickness : window.width
    height: vertical ? window.height : thickness

    gradient: Gradient {
      orientation: window.vertical ? Gradient.Horizontal : Gradient.Vertical
      GradientStop { position: 0; color: stayGlow.fromStart ? stayGlow.tint : stayGlow.clear }
      GradientStop { position: 1; color: stayGlow.fromStart ? stayGlow.clear : stayGlow.tint }
    }

    Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
  }

  // Everything the dock draws: the bar, and above it the magnified icons. It
  // is also the dock's input region.
  Item {
    id: stage

    // The strip keeps its order in every language, like the bar: drags and
    // drops reckon slots along from the first app. Only the menu mirrors.
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    readonly property real alongStart: window.restStart + window.barStart
    readonly property real alongLen: window.barEnd - window.barStart
    readonly property real near: window.margin - window.tuck
    readonly property real depth: window.barDepth + Math.ceil((window.maxScale - 1) * window.magnify * window.slotSize) + Style.space(2)

    x: !window.vertical ? alongStart : (window.position === "left" ? near : window.width - near - depth)
    y: window.vertical ? alongStart : (window.position === "top" ? near : window.height - near - depth)
    width: window.vertical ? depth : alongLen
    height: window.vertical ? alongLen : depth
    // Fullscreen shows and hides the dock at once, with nothing to watch in
    // between. Hidden by opacity rather than
    // visibility, so the icons keep their textures and are drawn on the first
    // frame back instead of being uploaded again.
    opacity: window.shown ? 1 : 0

    function pointerAt(position) {
      var at = stage.mapToItem(window.contentItem, position.x, position.y)
      return at
    }

    HoverHandler {
      id: stageHover
      onHoveredChanged: {
        if (hovered) {
          var at = stage.pointerAt(point.position)
          window.pointerAlong = (window.vertical ? at.y : at.x) - window.restStart
        }
        window.pointerInside = hovered
        if (!hovered && window.autohide) hideTimer.restart()
      }
      // Read in window coordinates: the stage moves as it magnifies, and the
      // pointer has not.
      onPointChanged: {
        if (!hovered) return
        var at = stage.pointerAt(point.position)
        if (!window.menuOpen) window.pointerAlong = (window.vertical ? at.y : at.x) - window.restStart
        // Only a real move clears it: the release itself reports the pointer too.
        if (window.hoverStale && !window.dragging
            && Math.hypot(at.x - window.dropPoint.x, at.y - window.dropPoint.y) > Style.space(4))
          window.hoverStale = false
      }
    }

    // The frosted bar. The blur behind it comes from Hyprland (hypr/macdock.lua).
    Placed {
      along: 0
      alongLen: stage.alongLen
      inward: 0
      depth: window.barDepth

      Rectangle {
        anchors.fill: parent
        radius: window.barRadius
        color: Util.alpha(Commons.Color.background, window.barOpacity)
        border.width: 1
        border.color: Util.alpha(Commons.Color.foreground, 0.16)

        // A faint inner rim catches the light the way glass does.
        Rectangle {
          anchors.fill: parent
          anchors.margins: 1
          radius: Math.max(0, parent.radius - 1)
          color: "transparent"
          border.width: 1
          border.color: Util.alpha("#ffffff", 0.05)
        }
      }
    }

    // Between the apps and the button for every app.
    Placed {
      visible: window.appCount > 0
      readonly property real center: (window.warp(window.appCount * window.slotSize)
        + window.warp(window.appCount * window.slotSize + window.separatorSize)) / 2

      along: center + window.insertGrow / 2 - window.barStart - 0.5
      alongLen: 1
      inward: Math.round(window.barDepth * 0.2)
      depth: Math.round(window.barDepth * 0.6)

      Rectangle {
        anchors.fill: parent
        color: window.movingDock || dividerHandle.containsMouse
          ? Commons.Color.accent : Util.alpha(Commons.Color.foreground, 0.28)
      }
    }

    // The divider's grip: wider than the line, across the bar's full depth.
    Placed {
      visible: window.appCount > 0 && window.contentShown
      along: window.warp(window.appCount * window.slotSize) + window.insertGrow / 2 - window.barStart
      alongLen: window.warp(window.appCount * window.slotSize + window.separatorSize)
        - window.warp(window.appCount * window.slotSize)
      inward: 0
      depth: window.barDepth

      MouseArea {
        id: dividerHandle

        property point pressPoint

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: window.movingDock ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        function windowPoint(event) {
          return dividerHandle.mapToItem(window.contentItem, event.x, event.y)
        }

        onPressed: function(event) {
          window.closeMenu()
          dividerHandle.pressPoint = dividerHandle.windowPoint(event)
          window.moveTarget = ""
          window.movingDock = true
        }

        // The pointer keeps reporting here while the button is held, even well
        // outside the dock's window.
        onPositionChanged: function(event) {
          if (!window.movingDock) return
          var at = dividerHandle.windowPoint(event)
          if (window.moveTarget === ""
              && Math.hypot(at.x - dividerHandle.pressPoint.x, at.y - dividerHandle.pressPoint.y) < Style.space(12))
            return
          window.moveTarget = window.edgeNearest(window.screenPoint(at))
        }

        onReleased: function(event) {
          var target = window.moveTarget
          window.movingDock = false
          window.moveTarget = ""
          if (target !== "" && target !== window.position)
            Util.execDetached("omarchy-dock position " + target)
          if (window.autohide) hideTimer.restart()
        }

        onCanceled: {
          window.movingDock = false
          window.moveTarget = ""
        }
      }
    }

    Repeater {
      id: appRepeater
      model: window.dock ? window.dock.itemModel : null

      delegate: AppSlot {}
    }

    AppsSlot {}
  }

  // An item laid out along the dock and away from its edge, inside the stage.
  component Placed: Item {
    property real along: 0
    property real alongLen: 0
    property real inward: 0
    property real depth: 0

    x: window.vertical ? (window.position === "left" ? inward : stage.width - inward - depth) : along
    y: window.vertical ? along : (window.position === "top" ? inward : stage.height - inward - depth)
    width: window.vertical ? depth : alongLen
    height: window.vertical ? alongLen : depth
  }

  // One square slot: where it rests along the strip, and where magnification
  // draws it.
  component Slot: Placed {
    id: slot

    property real restAlong: 0
    readonly property real drawnStart: window.warp(restAlong)
    readonly property real drawnEnd: window.warp(restAlong + window.slotSize)
    // How much the slot is magnified.
    readonly property real zoom: alongLen / window.slotSize

    // Only the dragged icon is lifted while a drag is on; none of the others
    // react as it passes over them.
    property bool hovered: mouse.containsMouse && !window.hoverStale && !window.dragging
    property bool pressed: mouse.pressed
    property alias mouse: mouse
    property string label: ""

    along: drawnStart - window.barStart
    alongLen: drawnEnd - drawnStart
    inward: window.padAcross
    depth: alongLen
    z: hovered ? 2 : 0

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    }

    Label {
      text: slot.label
      shown: window.labels && slot.hovered && !window.menuOpen && slot.label !== ""
    }
  }

  // The app's name, over its icon on the side away from the screen edge.
  component Label: Rectangle {
    id: label

    property string text: ""
    property bool shown: false
    readonly property int offset: Style.space(10)

    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Style.duration(shown ? 120 : 80); easing.type: Easing.OutCubic } }

    width: Math.min(220, labelText.implicitWidth + Style.spacing.controlPaddingX * 2)
    height: labelText.implicitHeight + Style.spacing.controlPaddingY * 2
    radius: Math.min(height / 2, Style.space(8))
    color: Util.alpha(Commons.Color.tooltip.background, 0.92)
    border.width: 1
    border.color: Util.alpha(Commons.Color.tooltip.border, 0.18)

    x: window.position === "left" ? parent.width + offset
      : window.position === "right" ? -width - offset
      : Math.round((parent.width - width) / 2)
    y: window.position === "top" ? parent.height + offset
      : window.position === "bottom" ? -height - offset
      : Math.round((parent.height - height) / 2)

    Text {
      id: labelText
      anchors.centerIn: parent
      width: Math.min(implicitWidth, 220 - Style.spacing.controlPaddingX * 2)
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: label.text
      color: Commons.Color.tooltip.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  component AppsSlot: Slot {
    id: appsSlot

    restAlong: window.appsStart
    label: strings.t("dock.apps")

    property real displayedShift: window.insertIndex >= 0 ? window.slotSize / 2 : 0

    Behavior on displayedShift {
      enabled: window.animateShifts
      NumberAnimation { duration: Style.duration(150); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }

    mouse.onClicked: function(event) {
      if (event.button === Qt.RightButton) {
        window.openSettingsMenu(appsSlot)
        return
      }
      window.closeMenu()
      if (window.dock) window.dock.openApps()
    }

    // A tile with a grid of app squares reads as "all apps" in any icon
    // theme. Drawn rather than taken from a font, so its edges stay crisp at
    // every magnification.
    Rectangle {
      id: tile
      anchors.fill: parent
      anchors.margins: window.inset * appsSlot.zoom
      radius: width * 0.225
      color: Util.alpha(Commons.Color.foreground, 0.14)
      border.width: 1
      border.color: Util.alpha(Commons.Color.foreground, 0.2)
      opacity: appsSlot.pressed ? 0.7 : 1
      transform: Translate {
        x: window.vertical ? 0 : appsSlot.displayedShift
        y: window.vertical ? appsSlot.displayedShift : 0
      }

      Grid {
        readonly property real square: tile.width * 0.16

        anchors.centerIn: parent
        columns: 3
        spacing: tile.width * 0.075

        Repeater {
          model: 9

          delegate: Rectangle {
            width: parent.square
            height: parent.square
            radius: Math.max(1, parent.square * 0.25)
            color: Commons.Color.foreground
          }
        }
      }
    }
  }

  component AppSlot: Slot {
    id: appSlot

    required property int index
    required property string key
    readonly property var modelData: window.dock ? window.dock.itemFor(key) : null
    readonly property var entry: window.dock && modelData ? window.dock.entryFor(modelData) : null
    readonly property bool launching: !!window.dock && window.dock.isLaunching(key)
    readonly property bool lifted: window.dragIndex === index
    property point pressPoint
    property bool dragged: false
    readonly property int windowCount: modelData ? modelData.windows.length : 0
    // How high the icon is while it bounces.
    property real bounce: 0

    restAlong: index * window.slotSize
    label: entry && entry.name ? String(entry.name) : key
    z: lifted ? 3 : (hovered ? 2 : 0)

    // Slots between where the dragged app was and where it would land step
    // aside to make room; the dragged one follows the pointer.
    readonly property real shift: window.insertIndex >= 0 ? (index >= window.insertIndex ? 1 : -1) * window.slotSize / 2
      : !window.dragging ? 0
      : lifted ? window.dragOffset
      : (window.dragIndex < index && index <= window.dropIndex) ? -window.slotSize
      : (window.dropIndex <= index && index < window.dragIndex) ? window.slotSize
      : 0
    property real displayedShift: shift

    // Only while dragging: once the drop reorders the slots, they are already
    // where they were shown.
    Behavior on displayedShift {
      enabled: window.animateShifts && ((window.dragging && !appSlot.lifted) || window.insertIndex >= 0)
      NumberAnimation { duration: Style.duration(150); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }

    // The slot, and the pointer handling in it, stays where it is; only the
    // icon moves. Points are read in window coordinates, which the slot moving
    // does not change.
    function windowPoint(event) {
      return appSlot.mapToItem(window.contentItem, event.x, event.y)
    }

    mouse.onPressed: function(event) {
      appSlot.dragged = false
      if (event.button === Qt.LeftButton) appSlot.pressPoint = appSlot.windowPoint(event)
    }

    mouse.onPositionChanged: function(event) {
      if (!(appSlot.mouse.pressedButtons & Qt.LeftButton)) return
      var point = appSlot.windowPoint(event)
      var delta = window.vertical ? point.y - appSlot.pressPoint.y : point.x - appSlot.pressPoint.x
      // A press that wanders is a drag in the making, not a click.
      if (Math.hypot(point.x - appSlot.pressPoint.x, point.y - appSlot.pressPoint.y) > Style.space(4)) appSlot.dragged = true
      if (!window.dragging) {
        if (Math.abs(delta) < Style.space(6)) return
        window.closeMenu()
        // The landing slot first: with the dragged slot set and no landing
        // slot yet, every slot before it would count as in between and step
        // aside for a moment.
        window.dropIndex = appSlot.index
        window.dragIndex = appSlot.index
      }
      if (!appSlot.lifted) return
      window.dragOffset = delta
      window.dropIndex = DockModel.dropIndex(appSlot.index, delta, window.slotSize, appRepeater.count)
    }

    mouse.onReleased: function(event) {
      if (!appSlot.lifted) return
      window.dropPoint = appSlot.windowPoint(event)
      var from = window.dragIndex
      var to = window.dropIndex
      appSlot.dragged = true
      window.endDrag()
      window.dock.moveItem(from, to)
    }

    mouse.onCanceled: if (appSlot.lifted) window.endDrag()

    mouse.onClicked: function(event) {
      // A drag ends in a release over the app, which is not a click on it.
      if (appSlot.dragged) {
        appSlot.dragged = false
        return
      }
      if (event.button === Qt.RightButton) {
        window.openMenu(appSlot.modelData, appSlot)
        return
      }
      window.closeMenu()
      if (event.button === Qt.MiddleButton) window.dock.launch(appSlot.modelData)
      else window.dock.activate(appSlot.modelData)
    }

    Image {
      anchors.fill: parent
      anchors.margins: window.inset * appSlot.zoom
      sourceSize: Qt.size(Math.ceil(window.iconSize * window.maxScale * 2), Math.ceil(window.iconSize * window.maxScale * 2))
      source: window.dock && appSlot.modelData ? window.dock.iconFor(appSlot.modelData) : ""
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      mipmap: true
      // Pressing darkens the icon a touch. With animations off, a starting
      // app is shown dimmed instead of bouncing.
      opacity: appSlot.pressed ? 0.7 : (appSlot.launching && (Style.reduceMotion || !window.bounceOnLaunch) ? 0.6 : 1)
      scale: appSlot.lifted ? 1.1 : 1
      transform: Translate {
        x: (window.vertical ? 0 : appSlot.displayedShift) + window.inwardX(appSlot.bounce)
        y: (window.vertical ? appSlot.displayedShift : 0) + window.inwardY(appSlot.bounce)
      }

      Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
    }

    // The dot under a running app, halfway between its icon and the bar's
    // edge. It stays put while the icon bounces.
    Rectangle {
      readonly property real fromEdge: (window.padAcross + window.inset * appSlot.zoom) / 2

      visible: window.runningDots && appSlot.windowCount > 0
      width: window.dotSize
      height: window.dotSize
      radius: width / 2
      color: Util.alpha(Commons.Color.foreground, 0.85)

      x: window.position === "left" ? -window.padAcross + fromEdge - width / 2
        : window.position === "right" ? parent.width + window.padAcross - fromEdge - width / 2
        : (parent.width - width) / 2
      y: window.position === "top" ? -window.padAcross + fromEdge - height / 2
        : window.position === "bottom" ? parent.height + window.padAcross - fromEdge - height / 2
        : (parent.height - height) / 2
      transform: Translate {
        x: window.vertical ? 0 : appSlot.displayedShift
        y: window.vertical ? appSlot.displayedShift : 0
      }
    }

    // A starting app hops until a window of it shows up; the hop in flight
    // always lands.
    SequentialAnimation {
      running: appSlot.launching && window.bounceOnLaunch && !Style.reduceMotion
      loops: Animation.Infinite
      alwaysRunToEnd: true

      NumberAnimation { target: appSlot; property: "bounce"; from: 0; to: window.iconSize * 0.45; duration: 260; easing.type: Easing.OutQuad }
      NumberAnimation { target: appSlot; property: "bounce"; to: 0; duration: 260; easing.type: Easing.InQuad }
      PauseAnimation { duration: 80 }
    }
  }

  BorderSurface {
    id: menu

    readonly property var item: window.menuItem
    readonly property bool hasEntry: !!item && !!window.dock && !!window.dock.entryFor(item)
    readonly property bool running: !!item && item.windows.length > 0

    visible: window.contentShown && (!!item || window.settingsMenu)
    width: Math.max(Style.space(140), menuColumn.implicitWidth) + padding * 2
    height: menuColumn.implicitHeight + padding * 2
    x: window.popupX(window.menuSlot, menu)
    y: window.popupY(window.menuSlot, menu)
    radius: Math.max(Style.cornerRadius, Style.space(8))
    color: Commons.Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)
    padding: Style.spacing.sm

    Column {
      id: menuColumn
      x: menu.contentLeftInset
      y: menu.contentTopInset
      width: menu.width - menu.contentLeftInset - menu.contentRightInset

      Repeater {
        model: [["top", Commons.I18n.t("dock.positionTop")], ["bottom", Commons.I18n.t("dock.positionBottom")], ["left", Commons.I18n.t("dock.positionLeft")], ["right", Commons.I18n.t("dock.positionRight")]]

        delegate: MenuRow {
          required property var modelData

          visible: window.settingsMenu
          text: modelData[1]
          checked: window.position === modelData[0]
          onTriggered: Util.execDetached("omarchy-dock position " + modelData[0])
        }
      }

      // Auto-hide, put the other way round: checked keeps the dock on screen.
      MenuRow {
        visible: window.settingsMenu
        text: strings.t("dock.show")
        checked: window.keptShown
        onTriggered: Util.execDetached("omarchy-dock autohide " + (window.keptShown ? "on" : "off"))
      }

      MenuRow {
        visible: menu.hasEntry && menu.running
        text: Commons.I18n.t("dock.newWindow")
        onTriggered: window.dock.launch(menu.item)
      }

      MenuRow {
        visible: menu.hasEntry
        text: menu.item && menu.item.pinned ? Commons.I18n.t("dock.removeFromDock") : Commons.I18n.t("dock.keepInDock")
        onTriggered: window.dock.setPinned(menu.item.key, !menu.item.pinned)
      }

      MenuRow {
        visible: menu.running
        text: Commons.I18n.t("dock.quit")
        onTriggered: window.dock.quit(menu.item)
      }
    }
  }

  component MenuRow: Rectangle {
    id: row

    property string text: ""
    property bool checked: false
    signal triggered()

    width: parent ? parent.width : 0
    height: visible ? Style.spacing.popupRowHeight : 0
    radius: Math.max(Style.cornerRadius, Style.space(5))
    color: rowMouse.containsMouse ? Style.hoverFill : "transparent"

    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.controlPaddingX
      textFormat: Text.PlainText
      text: row.text
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Text {
      visible: row.checked
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.controlPaddingX
      textFormat: Text.PlainText
      text: "✓"
      color: Commons.Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        row.triggered()
        window.closeMenu()
      }
    }
  }
}
