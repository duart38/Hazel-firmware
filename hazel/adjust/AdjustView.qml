// The adjust flow as it looks, one per window (the back screen and the viewfinder); what it does
// is AdjustState.qml (the `flow`). Drawn in the camera's own language (its font, white readouts with a thin
// black outline, black panels with its grey border, Hasselblad orange for what is selected or
// moving), sized in back-screen pixels times `unit` (1 on the 640x480 back screen).
//
//   closed  a small sliders button beside the recipe name on live view (tap: the list)
//   list    a panel on the left, the live picture still showing on the right: three tabs
//           (Tone, Colour or B&W, Texture), each a short list of settings with their values;
//           an orange dot marks what differs from the saved recipe
//   adjust  the whole live picture, with one slim strip at the bottom: the setting, its value
//           and its scale; the dial moves it and the picture follows. Tap the picture: back to the
//           list. Hold it: the saved recipe, for comparing
//   done    save to the slot, save as a new slot, use without saving, or discard
//   name    a keyboard for the name of a recipe saved as new: tap the keys, or the front wheel
//           steps key by key, the rear wheel a row, AF-D types
// Written by Claude (Claude Code); see notes/17-on-camera-adjust.md.
import QtQuick 2.4
import "recipe.js" as Recipe

FocusScope {
    id: view
    property QtObject flow
    // the camera's GlobalConstants, or anything with the same few names
    property var constants: ({})
    property real unit: 1
    property bool touch: true
    // where the entry button goes (top-left corner of it), and whether live view shows it
    property real entryX: 30 * unit
    property real entryY: 30 * unit
    property bool entryShown: false

    signal entryTapped()

    // The entry button beside the recipe name: just after it, or just before it when the name is
    // right-aligned against the edge (live view with the ISO readout puts it under ISO, top right)
    function placeEntry(nameLeft, nameRight, nameMiddleY) {
        var gap = 14 * unit, w = 34 * unit;
        entryX = nameRight + gap + w <= width - 10 * unit ? nameRight + gap : nameLeft - gap - w;
        entryY = nameMiddleY - 14 * unit;
    }

    readonly property string font: constants.cameraControlTextFontName || "Helvetica Neue"
    readonly property color orange: constants.hblOrange || "#de4200"
    readonly property color border: constants.popupBorderColor || "#646464"
    readonly property color dim: constants.itemColor || "lightgrey"
    readonly property bool hasFlow: flow !== null && flow !== undefined

    Keys.onPressed: event.accepted = hasFlow && flow.key(event.key)

    // ---- closed: the entry button ----
    Item {
        id: entry
        visible: hasFlow && flow.mode === "closed" && view.entryShown
        x: view.entryX
        y: view.entryY
        width: 34 * unit
        height: 28 * unit
        // three slider lines, knobs at different places: "adjust"
        Repeater {
            model: [0.7, 0.25, 0.55]
            Item {
                y: index * 10 * unit + 3 * unit
                width: entry.width
                height: 3 * unit
                Rectangle { anchors.fill: parent; anchors.margins: -1; color: "black"; opacity: 0.6 }
                Rectangle { anchors.fill: parent; color: "white" }
                Rectangle {
                    width: 9 * unit
                    height: 9 * unit
                    radius: width / 2
                    x: modelData * entry.width - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: hasFlow && flow.edited ? view.orange : "black"
                    border.width: 2 * unit
                    border.color: "white"
                }
            }
        }
        MouseArea {
            enabled: entry.visible && view.touch
            anchors.fill: parent
            anchors.margins: -12 * unit
            preventStealing: true
            onClicked: { view.entryTapped(); flow.open(); }
        }
    }

    // ---- anywhere on the picture, while open ----
    MouseArea {
        id: picture
        enabled: hasFlow && flow.mode !== "closed" && view.touch
        anchors.fill: parent
        preventStealing: true
        onClicked: {
            if (flow.mode === "adjust") flow.select();
            else if (flow.mode === "list") flow.done();
            else if (flow.mode === "done") flow.back();
        }
        onPressAndHold: flow.compare(true)
        onReleased: flow.compare(false)
        onCanceled: flow.compare(false)
    }

    // while holding: the saved recipe is on screen. Just above the strip, next to the value it is
    // compared with, and clear of the camera's ISO and battery along the top
    Rectangle {
        visible: hasFlow && flow.comparing
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: strip.top
        anchors.bottomMargin: 44 * unit
        width: savedLabel.width + 28 * unit
        height: 34 * unit
        color: "#99000000"
        border.width: 2 * unit
        border.color: view.orange
        Text {
            id: savedLabel
            anchors.centerIn: parent
            width: Math.min(implicitWidth, view.width - 88 * unit)
            elide: Text.ElideRight
            text: "Saved " + (hasFlow ? flow.name : "")
            font.family: view.font
            font.pixelSize: 20 * unit
            color: "white"
        }
    }

    // ---- list ----
    Rectangle {
        id: panel
        visible: hasFlow && flow.mode === "list"
        width: 300 * unit
        height: parent.height
        // opaque: the recipe name live view draws underneath must not read through; the picture
        // stays in view to the right
        color: "black"
        MouseArea { anchors.fill: parent; enabled: panel.visible && view.touch }
        Rectangle { anchors.right: parent.right; width: 2 * unit; height: parent.height; color: view.border }

        Text {
            id: title
            x: 20 * unit
            y: 14 * unit
            width: parent.width - 2 * x - editedTag.width
            elide: Text.ElideRight
            text: hasFlow ? flow.name : ""
            font.family: view.font
            font.pixelSize: 24 * unit
            color: "white"
        }
        Text {
            id: editedTag
            visible: hasFlow && flow.edited
            anchors.right: parent.right
            anchors.rightMargin: 20 * unit
            anchors.baseline: title.baseline
            text: "edited"
            font.family: view.font
            font.pixelSize: 16 * unit
            color: view.orange
        }

        // the groups, as tabs
        Row {
            id: tabs
            x: 8 * unit
            y: 52 * unit
            Repeater {
                model: hasFlow ? flow.groups : []
                Item {
                    width: (panel.width - 16 * unit) / Math.max(1, hasFlow ? flow.groups.length : 1)
                    height: 40 * unit
                    readonly property bool current: hasFlow && flow.group === index
                    Text {
                        anchors.centerIn: parent
                        text: modelData.name
                        font.family: view.font
                        font.pixelSize: 19 * unit
                        color: parent.current ? "white" : view.dim
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 16 * unit
                        height: 3 * unit
                        color: parent.current ? view.orange : "#3a3a3a"
                    }
                    MouseArea { anchors.fill: parent; enabled: view.touch; onClicked: flow.showGroup(index) }
                }
            }
        }

        Column {
            id: rows
            y: 100 * unit
            width: parent.width - 2 * unit
            Repeater {
                model: hasFlow && flow.groups.length > 0 ? flow.groups[flow.group].settings : []
                Rectangle {
                    width: rows.width
                    // seven rows (Colour) still leave a gap above Done
                    height: 44 * unit
                    readonly property bool current: hasFlow && flow.row === index
                    readonly property bool changed: hasFlow && flow.changedKeys[modelData.key] === true
                    color: current ? view.orange : "transparent"
                    Text {
                        x: 20 * unit
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        font.family: view.font
                        font.pixelSize: 21 * unit
                        color: "white"
                    }
                    Rectangle {
                        visible: parent.changed
                        width: 8 * unit
                        height: width
                        radius: width / 2
                        anchors.right: valueText.left
                        anchors.rightMargin: 9 * unit
                        anchors.verticalCenter: parent.verticalCenter
                        color: parent.current ? "white" : view.orange
                    }
                    Text {
                        id: valueText
                        anchors.right: parent.right
                        anchors.rightMargin: 20 * unit
                        anchors.verticalCenter: parent.verticalCenter
                        text: hasFlow ? Recipe.shown(modelData, Recipe.settingValue(flow.text, modelData)) : ""
                        font.family: view.font
                        font.pixelSize: 21 * unit
                        color: parent.current ? "white" : view.dim
                    }
                    MouseArea { anchors.fill: parent; enabled: view.touch; onClicked: flow.pick(flow.group, index) }
                }
            }
        }

        // Done: the camera's dialog button (orange outline)
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12 * unit
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 40 * unit
            height: 44 * unit
            color: doneTap.pressed ? "white" : "transparent"
            border.width: 3 * unit
            border.color: view.orange
            Text {
                anchors.centerIn: parent
                text: "Done"
                font.family: view.font
                font.pixelSize: 21 * unit
                color: doneTap.pressed ? "black" : "white"
            }
            MouseArea { id: doneTap; anchors.fill: parent; enabled: view.touch; onClicked: flow.done() }
        }
    }

    // ---- adjust: one slim strip over the picture ----
    Item {
        id: strip
        visible: hasFlow && flow.mode === "adjust" && flow.setting !== null
        readonly property var setting: hasFlow ? flow.setting : null
        readonly property bool twoScales: setting !== null && setting.kind === "tint"
        readonly property bool chips: setting !== null && setting.kind === "filter"
        width: parent.width
        // room under the scales for the compare hint, clear of the knob
        height: (twoScales ? 162 : 124) * unit
        anchors.bottom: parent.bottom

        // fades in from the picture above the strip, so it has no hard top edge and every line
        // of it, the small group name too, sits on the dark part however bright the picture is
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: -36 * unit
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#00000000" }
                GradientStop { position: 0.3; color: "#b0000000" }
                GradientStop { position: 1.0; color: "#d0000000" }
            }
        }
        MouseArea { anchors.fill: parent; enabled: strip.visible && view.touch }

        // back to the list
        Item {
            id: backButton
            x: 6 * unit
            y: 8 * unit
            width: 44 * unit
            height: 52 * unit
            Text {
                anchors.centerIn: parent
                text: "‹"
                font.family: view.font
                font.pixelSize: 44 * unit
                color: backTap.pressed ? view.orange : "white"
                style: Text.Outline
                styleColor: "black"
            }
            MouseArea { id: backTap; anchors.fill: parent; anchors.margins: -8 * unit; enabled: view.touch; onClicked: flow.select() }
        }
        Text {
            id: groupName
            x: 52 * unit
            y: 10 * unit
            text: hasFlow && flow.groups.length > 0 ? flow.groups[flow.group].name.toUpperCase() : ""
            font.family: view.font
            font.pixelSize: 14 * unit
            font.letterSpacing: 1 * unit
            color: view.dim
        }
        Text {
            x: 52 * unit
            y: 26 * unit
            text: strip.setting ? strip.setting.name : ""
            font.family: view.font
            font.pixelSize: 27 * unit
            color: "white"
            style: Text.Outline
            styleColor: "black"
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 22 * unit
            y: 16 * unit
            text: strip.setting ? Recipe.shown(strip.setting, flow.value) : ""
            font.family: view.font
            font.pixelSize: 36 * unit
            color: hasFlow && strip.setting && flow.changedKeys[strip.setting.key] ? view.orange : "white"
            style: Text.Outline
            styleColor: "black"
        }

        // one scale
        ValueScale {
            id: single
            visible: !strip.twoScales && !strip.chips
            x: 40 * unit
            y: 64 * unit
            width: parent.width - 80 * unit
            unit: view.unit
            orange: view.orange
            from: strip.setting && strip.setting.min < 0 ? -4 : 0
            to: 4
            value: visible ? flow.value * 4 : 0
            saved: visible ? flow.savedValue * 4 : 0
            showSaved: visible && Math.abs(flow.value - flow.savedValue) > 0.0001
            ends: strip.setting && strip.setting.ends ? strip.setting.ends : null
            active: true
            // a press and hold on zero puts it back to zero, as on the camera's own sliders
            MouseArea {
                enabled: view.touch && single.visible
                x: single.zeroX - 24 * unit
                width: 48 * unit
                height: parent.height
                onPressAndHold: flow.reset()
            }
        }

        // a tint: its hue on the colour wheel, and how much (one wheel each)
        Column {
            visible: strip.twoScales
            x: 84 * unit
            y: 62 * unit
            spacing: 6 * unit
            Repeater {
                model: ["hue", "amount"]
                Item {
                    width: strip.width - 124 * unit
                    height: 36 * unit
                    Text {
                        x: -22 * unit - width
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData === "hue" ? "Hue" : "Amt"
                        font.family: view.font
                        font.pixelSize: 13 * unit
                        color: hasFlow && flow.axis === modelData ? "white" : view.dim
                    }
                    ValueScale {
                        anchors.fill: parent
                        unit: view.unit
                        orange: view.orange
                        hues: modelData === "hue"
                        from: 0
                        to: modelData === "hue" ? 360 : 4
                        tickEvery: 1
                        readonly property bool tint: strip.twoScales && typeof flow.value === "object" && typeof flow.savedValue === "object"
                        value: tint ? (modelData === "hue" ? flow.value.hue : flow.value.amount * 4) : 0
                        saved: tint ? (modelData === "hue" ? flow.savedValue.hue : flow.savedValue.amount * 4) : 0
                        showSaved: tint && !Recipe.sameValue(strip.setting, flow.value, flow.savedValue)
                        active: hasFlow && flow.axis === modelData
                    }
                }
            }
        }

        // a black-and-white filter: six colours, the chosen one ringed
        Row {
            visible: strip.chips
            anchors.horizontalCenter: parent.horizontalCenter
            y: 62 * unit
            spacing: 16 * unit
            Repeater {
                model: Recipe.FILTERS
                Item {
                    width: 78 * unit
                    height: 44 * unit
                    readonly property bool current: hasFlow && strip.chips && flow.value === index
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 24 * unit
                        height: width
                        radius: width / 2
                        color: modelData.colour
                        border.width: (parent.current ? 3 : 1) * unit
                        border.color: parent.current ? view.orange : "white"
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        text: modelData.name
                        font.family: view.font
                        font.pixelSize: 14 * unit
                        color: parent.current ? "white" : view.dim
                    }
                    MouseArea { anchors.fill: parent; enabled: view.touch; onClicked: flow.setValue(index) }
                }
            }
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 22 * unit
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6 * unit
            // the filter names sit on that line
            visible: view.touch && !strip.chips
            text: "Hold the picture to compare"
            font.family: view.font
            font.pixelSize: 13 * unit
            color: "#a0a0a0"
        }
    }

    // ---- done: the camera's list popup, with the four ways out ----
    Rectangle {
        visible: hasFlow && flow.mode === "done"
        anchors.fill: parent
        color: "#80000000"
        Rectangle {
            id: sheet
            anchors.centerIn: parent
            width: parent.width - 80 * unit
            height: 64 * unit + 4 * 62 * unit
            color: "black"
            border.width: 2 * unit
            border.color: view.border
            MouseArea { anchors.fill: parent; enabled: view.touch }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 20 * unit
                text: (hasFlow ? flow.name : "") + " · EDITED"
                font.family: view.font
                font.pixelSize: 18 * unit
                font.capitalization: Font.AllUppercase
                color: "white"
            }
            Column {
                id: choices
                y: 58 * unit
                x: 2 * unit
                width: parent.width - 4 * unit
                Repeater {
                    model: hasFlow ? flow.doneChoices : []
                    Rectangle {
                        width: choices.width
                        height: 62 * unit
                        readonly property bool current: hasFlow && flow.doneRow === index
                        color: current ? view.orange : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: modelData.text
                            font.family: view.font
                            font.pixelSize: 24 * unit
                            color: !modelData.enabled ? "#5a5a5a" : parent.current ? "white" : view.dim
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: view.touch && modelData.enabled
                            onClicked: { flow.doneRow = index; flow.select(); }
                        }
                    }
                }
            }
        }
    }

    // ---- name: the keyboard ----
    Rectangle {
        id: keyboard
        visible: hasFlow && flow.mode === "name"
        anchors.fill: parent
        color: "black"
        MouseArea { anchors.fill: parent; enabled: keyboard.visible && view.touch }
        readonly property real margin: 10 * unit
        readonly property real gap: 6 * unit
        readonly property real column: (width - 2 * margin - 9 * gap) / 10
        readonly property real rowHeight: 62 * unit

        Text {
            x: keyboard.margin
            y: 12 * unit
            text: "SAVE AS NEW · " + (hasFlow ? flow.freeSlot : "")
            font.family: view.font
            font.pixelSize: 15 * unit
            font.letterSpacing: 1 * unit
            color: view.dim
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: keyboard.margin
            y: 12 * unit
            text: hasFlow ? flow.typed.length + " / " + flow.nameMax : ""
            font.family: view.font
            font.pixelSize: 15 * unit
            color: hasFlow && flow.typed.length >= flow.nameMax ? view.orange : view.dim
        }

        // the name, ending at a blinking cursor
        Rectangle {
            id: field
            x: keyboard.margin
            y: 36 * unit
            width: parent.width - 2 * keyboard.margin
            height: 58 * unit
            color: "black"
            border.width: 2 * unit
            border.color: view.orange
            clip: true
            Text {
                id: typedText
                x: 14 * unit
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, field.width - 40 * unit)
                // the end stays in view, as when typing anywhere else
                elide: Text.ElideLeft
                text: hasFlow ? flow.typed : ""
                font.family: view.font
                font.pixelSize: 30 * unit
                color: "white"
            }
            Text {
                visible: hasFlow && flow.typed === ""
                x: 14 * unit
                anchors.verticalCenter: parent.verticalCenter
                text: "Recipe name"
                font.family: view.font
                font.pixelSize: 30 * unit
                color: "#5a5a5a"
            }
            Rectangle {
                id: cursor
                x: typedText.x + (hasFlow && flow.typed !== "" ? typedText.width + 2 * unit : 0)
                anchors.verticalCenter: parent.verticalCenter
                width: 3 * unit
                height: 34 * unit
                color: view.orange
                Timer {
                    interval: 530; repeat: true; running: keyboard.visible
                    onTriggered: cursor.visible = !cursor.visible
                    onRunningChanged: cursor.visible = true
                }
            }
        }
        Text {
            x: keyboard.margin
            y: 100 * unit
            text: hasFlow && flow.nameTakenBy !== "" ? flow.nameTakenBy + " is called this too" : ""
            font.family: view.font
            font.pixelSize: 15 * unit
            color: view.orange
        }

        Column {
            y: 126 * unit
            x: keyboard.margin
            spacing: keyboard.gap
            Repeater {
                model: hasFlow ? flow.keyRows : []
                Row {
                    id: keyRow
                    readonly property int rowIndex: index
                    spacing: keyboard.gap
                    Repeater {
                        model: modelData
                        Rectangle {
                            id: key
                            readonly property bool current: hasFlow && flow.keyRow === keyRow.rowIndex && flow.keyCol === index
                            readonly property bool special: modelData.id !== "char" && modelData.id !== "space"
                            readonly property bool disabled: modelData.id === "save" && hasFlow && flow.typedName === ""
                            readonly property bool lit: modelData.id === "shift" && hasFlow && flow.shift
                            width: modelData.span * keyboard.column + (modelData.span - 1) * keyboard.gap
                            height: keyboard.rowHeight
                            radius: 4 * unit
                            color: keyTap.pressed ? "white" : current ? view.orange : lit ? "#d8d8d8"
                                 : modelData.id === "save" ? "transparent" : special ? "#161616" : "#2a2a2a"
                            border.width: modelData.id === "save" ? 3 * unit : special ? 1 * unit : 0
                            border.color: modelData.id === "save" ? (key.disabled ? "#3a3a3a" : view.orange) : "#3a3a3a"
                            Text {
                                anchors.centerIn: parent
                                text: {
                                    var k = modelData;
                                    if (k.id === "char") return hasFlow && flow.shift ? k.ch.toUpperCase() : k.ch;
                                    return {shift: "Aa", "delete": "Del", back: "Back", clear: "Clear",
                                            space: "space", save: "Save"}[k.id];
                                }
                                font.family: view.font
                                font.pixelSize: (modelData.id === "char" ? 26 : 19) * unit
                                color: keyTap.pressed || (key.lit && !key.current) ? "black"
                                     : key.disabled ? "#5a5a5a"
                                     : modelData.id === "space" && !key.current ? view.dim : "white"
                            }
                            MouseArea {
                                id: keyTap
                                anchors.fill: parent
                                // the gaps belong to the keys either side, so a finger never misses
                                anchors.margins: -keyboard.gap / 2
                                enabled: view.touch && !key.disabled
                                onClicked: flow.tapKey(keyRow.rowIndex, index)
                            }
                        }
                    }
                }
            }
        }
    }
}
