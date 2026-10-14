import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  readonly property var cfgShapes: ({
    dots:    { occW: 7.0,  occH: 7.0, emptyW: 3.0, emptyH: 3.0, radiusType: "circle", rotation: 0 },
    square:  { occW: 6.2,  occH: 6.2, emptyW: 3.0, emptyH: 3.0, radiusType: "fixed",  radiusVal: 0.5, rotation: 0 },
    diamond: { occW: 6.0,  occH: 6.0, emptyW: 3.0, emptyH: 3.0, radiusType: "fixed",  radiusVal: 0.5, rotation: 45 },
    bar:     { occW: 11.0, occH: 3.5, emptyW: 9.0, emptyH: 1.5, radiusType: "fixed",  radiusVal: 1.0, rotation: 0 }
  })

  readonly property var cfgDensity: ({
    compact: { slotRatio: 0.8,  vGapToken: Style.spacing.hairline },
    normal:  { slotRatio: 1.0,  vGapToken: Style.spacing.xxs },
    relaxed: { slotRatio: 1.25, vGapToken: Style.spacing.sm }
  })
  readonly property real cfgTrailingGap: 1.5

  function boolOption(name, fallback) {
    var value = setting(name, fallback)
    if (typeof value === "boolean") return value
    if (typeof value === "number") return value !== 0
    var text = String(value).trim().toLowerCase()
    if (["false", "0", "no", "off"].indexOf(text) !== -1) return false
    if (["true", "1", "yes", "on"].indexOf(text) !== -1) return true
    return fallback
  }

  function numberOption(name, fallback, min, max) {
    var value = Number(setting(name, fallback))
    if (!isFinite(value)) value = fallback
    return Math.max(min, Math.min(max, value))
  }

  readonly property string mode: setting("mode", "dots")
  readonly property var currentShapeSpec: cfgShapes[root.mode] || cfgShapes.dots
  readonly property int workspaceCount: Math.round(numberOption("workspaces", 5, 1, 10))
  readonly property bool scrollEnabled: boolOption("scroll", true)
  readonly property bool hideEmpty: boolOption("hideEmpty", false)

  readonly property string density: cfgDensity[setting("density", "normal")] !== undefined ? setting("density", "normal") : "normal"
  readonly property var densityProfile: cfgDensity[root.density]

  readonly property int systemBaseBarSize: root.vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
  readonly property int effectiveBarSize: root.bar ? root.bar.barSize : root.systemBaseBarSize
  readonly property real systemBarScale: (root.effectiveBarSize > 0 && root.systemBaseBarSize > 0) ? (root.effectiveBarSize / root.systemBaseBarSize) : 1.0
  readonly property real scaleFactor: Math.max(0.5, root.systemBarScale)

  readonly property real baseSlotWidth: Math.round(root.effectiveBarSize * (Style.space(20) / Style.bar.sizeHorizontal))
  readonly property real slotWidth: Math.round(root.baseSlotWidth * root.densityProfile.slotRatio)
  readonly property real rowGap: root.densityProfile.vGapToken

  readonly property string colorScheme: setting("colorScheme", "theme")
  readonly property bool isDarkTheme: {
    var bg = (typeof Color !== "undefined" && Color.background) ? Color.background : Qt.rgba(0.06, 0.07, 0.08, 1)
    return (0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b) < 0.5
  }
  readonly property color baseColor: {
    if (root.colorScheme === "monotone") {
      return root.isDarkTheme ? Qt.rgba(1, 1, 1, 1) : Qt.rgba(0, 0, 0, 1)
    }
    return root.bar ? root.bar.barForeground : (typeof Color !== "undefined" && Color.foreground ? Color.foreground : "#cdd6f4")
  }

  // Tri-state on purpose: null (unset) follows the system token; any explicit
  // value pins, even one numerically equal to a theme default. Do not add a
  // static manifest default for dim, or "unset" becomes indistinguishable.
  readonly property real systemIdleAlpha: (typeof Style !== "undefined" && Style.normalBorderAlpha !== undefined) ? Style.normalBorderAlpha : 0.55
  readonly property real occupiedDim: setting("dim", null) !== null ? numberOption("dim", root.systemIdleAlpha, 0.2, 0.9) : root.systemIdleAlpha
  readonly property real emptyDim: Math.max(0.12, root.occupiedDim * 0.45)
  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(root.cfgTrailingGap)

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  readonly property var currentWorkspaceIds: {
    var values = Hyprland.workspaces.values
    var focused = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    var ids = []
    var maxBase = root.workspaceCount

    if (root.hideEmpty) {
      for (var i = 0; i < values.length; i++) {
        var ws = values[i]
        if (ws.id > 0 && ws.id <= 10 && ws.toplevels.values.length > 0) {
          if (ids.indexOf(ws.id) === -1) ids.push(ws.id)
        }
      }
      if (focused > 0 && focused <= 10 && ids.indexOf(focused) === -1) {
        ids.push(focused)
      }
      if (ids.length === 0) ids.push(1)
    } else {
      // Contiguous 1..max(base, highest active): the slot position always
      // equals the workspace id, so a shape-only bar stays readable by
      // counting. Stock-style sparse appending would let a destroyed empty
      // workspace shift a higher one into its slot and lose the ordinal.
      var top = maxBase
      for (var j = 0; j < values.length; j++) {
        var id = values[j].id
        if (id > 0 && id <= 10 && id > top) top = id
      }
      for (var b = 1; b <= top; b++) ids.push(b)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    // Hyprland 0.56 dispatches Lua: `hyprctl dispatch <expr>` runs as
    // `hl.dispatch(<expr>)`. Both paths below use the same hl.dsp.focus
    // call, so click and fallback switch identically.
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
    } else {
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"" + id + "\" })"])
    }
  }

  property real wheelAccumulator: 0

  function scrollWorkspaces(delta) {
    var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
    root.wheelAccumulator = wheel.remainder
    if (!root.scrollEnabled || wheel.steps === 0) return

    var ids = root.currentWorkspaceIds
    var focused = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    var index = ids.indexOf(focused)
    if (index === -1) {
      if (focused <= 0) return
      if (focused > ids[ids.length - 1] && wheel.steps > 0) {
        root.focusWorkspace(ids[ids.length - 1])
      }
      return
    }
    var target = ids[Util.clamp(index - wheel.steps, 0, ids.length - 1)]
    if (target !== ids[index]) root.focusWorkspace(target)
  }

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.currentWorkspaceIds.length
    columnSpacing: 0
    rowSpacing: root.vertical ? root.rowGap : 0

    Repeater {
      model: root.currentWorkspaceIds

      WidgetButton {
        id: wsButton
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        bar: root.bar
        text: " "
        labelVisible: false
        foreground: root.baseColor
        opacity: focused ? 1.0 : (occupied ? root.occupiedDim : root.emptyDim)
        tooltipText: String(modelData)

        fixedWidth: root.vertical ? root.effectiveBarSize : Style.space(root.slotWidth)
        fixedHeight: root.effectiveBarSize
        onPressed: function() { root.focusWorkspace(modelData) }
        onWheelMoved: function(delta) { root.scrollWorkspaces(delta) }

        Rectangle {
          id: shape
          anchors.centerIn: parent

          readonly property var spec: root.currentShapeSpec
          readonly property bool isFullShape: wsButton.occupied || wsButton.focused

          color: wsButton.foreground
          rotation: spec.rotation

          width: (isFullShape ? spec.occW : spec.emptyW) * root.scaleFactor
          height: (isFullShape ? spec.occH : spec.emptyH) * root.scaleFactor
          radius: spec.radiusType === "circle" ? width / 2 : (spec.radiusVal * root.scaleFactor)
        }
      }
    }
  }
}
