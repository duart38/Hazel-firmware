// ValueScale (not "Scale": QtQuick has a Scale transform, and an import wins over this folder). One value scale of the adjust view, drawn like the camera's own exposure-adjust slider: a thin
// white line, a tick for every whole step, a taller tick at zero, and a round marker that turns
// Hasselblad orange while it moves. Added: the stretch from zero to the value in orange, so how far
// a setting is pushed reads at a glance, and a small grey mark where the saved recipe has it.
// Colour settings draw the line as the colours they move between; a hue scale as the colour wheel.
// Written by Claude (Claude Code); see notes/17-on-camera-adjust.md.
import QtQuick 2.4

Item {
    id: bar
    // all in shown units (the scale of four): -4..4 or 0..4; a hue scale 0..360
    property real from: -4
    property real to: 4
    property real value: 0
    property real saved: 0
    property bool showSaved: false
    property bool active: false
    // two colours for the ends, or none for white
    property var ends: null
    property bool hues: false
    property real unit: 1
    property color orange: "#de4200"
    property real tickEvery: 1

    readonly property real lineWidth: 3 * unit
    readonly property real span: width
    function xOf(v) { return (Math.max(from, Math.min(to, v)) - from) / (to - from) * span; }
    readonly property real zeroX: xOf(hues ? from : Math.max(from, Math.min(to, 0)))

    height: 34 * unit

    // the line: a vertical gradient turned on its side, since Qt 5.5 gradients only run downwards
    Item {
        id: line
        width: bar.span
        height: bar.lineWidth
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
            visible: !bar.ends && !bar.hues
            anchors.fill: parent
            color: "white"
            border.width: 1
            border.color: "#80000000"
        }
        Rectangle {
            visible: !!bar.ends || bar.hues
            width: parent.height * 2
            height: parent.width
            anchors.centerIn: parent
            rotation: -90
            gradient: Gradient {
                GradientStop { position: 0.0; color: bar.hues ? "#ff0000" : bar.ends ? bar.ends[0] : "white" }
                GradientStop { position: bar.hues ? 0.1667 : 0.5; color: bar.hues ? "#ffff00" : "#d0d0d0" }
                GradientStop { position: bar.hues ? 0.3333 : 1.0; color: bar.hues ? "#00ff00" : bar.ends ? bar.ends[1] : "white" }
                GradientStop { position: bar.hues ? 0.5 : 1.0; color: bar.hues ? "#00ffff" : bar.ends ? bar.ends[1] : "white" }
                GradientStop { position: bar.hues ? 0.6667 : 1.0; color: bar.hues ? "#0000ff" : bar.ends ? bar.ends[1] : "white" }
                GradientStop { position: bar.hues ? 0.8333 : 1.0; color: bar.hues ? "#ff00ff" : bar.ends ? bar.ends[1] : "white" }
                GradientStop { position: 1.0; color: bar.hues ? "#ff0000" : bar.ends ? bar.ends[1] : "white" }
            }
        }
    }

    // ticks: one per whole step, zero taller
    Repeater {
        model: bar.hues ? 0 : Math.round((bar.to - bar.from) / bar.tickEvery) + 1
        Rectangle {
            readonly property real v: bar.from + index * bar.tickEvery
            readonly property bool zero: Math.abs(v) < 0.001
            width: (zero ? 3 : 2) * bar.unit
            height: (zero ? 18 : 9) * bar.unit
            x: bar.xOf(v) - width / 2
            y: (bar.height - height) / 2
            color: "white"
            border.width: 1
            border.color: "#60000000"
        }
    }

    // how far from zero, in orange
    Rectangle {
        visible: !bar.ends && !bar.hues && Math.abs(bar.value) > 0.001
        x: Math.min(bar.zeroX, bar.xOf(bar.value))
        width: Math.abs(bar.xOf(bar.value) - bar.zeroX)
        height: 5 * bar.unit
        anchors.verticalCenter: parent.verticalCenter
        color: bar.orange
    }

    // where the saved recipe has it
    Rectangle {
        visible: bar.showSaved
        width: 8 * bar.unit
        height: 8 * bar.unit
        radius: width / 2
        x: bar.xOf(bar.saved) - width / 2
        y: parent.height / 2 - 16 * bar.unit - height / 2
        color: "#b0b0b0"
        border.width: 1
        border.color: "black"
    }

    Rectangle {
        id: marker
        width: 26 * bar.unit
        height: width
        radius: width / 2
        x: bar.xOf(bar.value) - width / 2
        anchors.verticalCenter: parent.verticalCenter
        color: bar.active ? bar.orange : "black"
        border.width: 3 * bar.unit
        border.color: "white"
        Behavior on x { NumberAnimation { duration: 60 } }
    }
}
