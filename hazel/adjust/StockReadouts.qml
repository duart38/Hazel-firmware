// The camera's own live-view readouts that would show through the adjust view, held out of sight
// while it is open: the touch shutter (the big orange circle, which can be dragged anywhere on the
// picture) and everything along the bottom edge, where the strip goes (the exposure scale,
// aperture, shutter speed, AE-L, shots left or "[ No Card ]"). ISO, battery and AF/MF at the top
// stay: they don't collide, and they are still worth seeing while the picture is judged.
//
// Each item is held at opacity 0 by a Binding, so nothing of the camera's is rewritten: when the
// Binding lets go, an opacity the camera binds (the touch shutter's) gets its own binding back.
// Qt 5.5's Binding does not put back a plain value, so uncover() does that itself. `visible` is
// left alone on purpose: the camera binds it on every one of these, and its onVisibleChanged
// handlers repaint canvases. Opacity 0 still takes touches, but the adjust view covers the whole
// screen with its own touch area while it is open, so none reach the camera's items.
// Written by Claude (Claude Code); see notes/17-on-camera-adjust.md.
import QtQuick 2.4

QtObject {
    id: readouts

    property bool covered: false
    // the bottom part of live view, as a share of its height, whose readouts are held
    property real bottomShare: 0.3
    // {item, binding, opacity}: each held item, and the opacity it had when covered
    property var held: []

    property Component holder: Component {
        Binding { property: "opacity"; value: 0; when: false }
    }

    // the camera's ExposureButton: dragged around, starts an exposure when tapped
    function isTouchShutter(item) {
        return typeof item.canDrag === "boolean" && typeof item.isVisible === "boolean"
            && typeof item.startExposure === "function";
    }

    function inBottomRow(item, overlay) {
        if (overlay.height <= 0 || item.height >= overlay.height * bottomShare) return false;
        return item.y >= overlay.height * (1 - bottomShare) && item.y + item.height <= overlay.height + 1;
    }

    function holds(item) {
        for (var i = 0; i < held.length; i++) if (held[i].item === item) return true;
        return false;
    }

    function hold(item) {
        if (!item || holds(item)) return;
        var h = {item: item, binding: holder.createObject(readouts, {target: item}), opacity: item.opacity};
        held.push(h);
        if (covered) hide(h);
    }

    function hide(h) {
        if (!h.item) return;
        h.opacity = h.item.opacity;
        h.binding.when = true;
    }

    function show(h) {
        h.binding.when = false;
        // a plain value (no binding came back): the one it had
        if (h.item && h.item.opacity === 0 && h.opacity !== 0) h.item.opacity = h.opacity;
    }

    // `overlay` is the camera's LiveViewOverlay (the item with infoVisible and sizeFactor). Its
    // children along the bottom are the readouts; the touch shutter is a sibling of the area it
    // sits in, one or two levels up (LiveViewImage). Safe to call again: each item is taken once.
    function take(overlay) {
        if (!overlay) return;
        var i;
        for (i = 0; i < overlay.children.length; i++)
            if (inBottomRow(overlay.children[i], overlay)) hold(overlay.children[i]);
        for (var p = overlay.parent, depth = 0; p && depth < 2; p = p.parent, depth++)
            for (i = 0; i < p.children.length; i++)
                if (isTouchShutter(p.children[i])) hold(p.children[i]);
    }

    function cover() {
        if (covered) return;
        covered = true;
        for (var i = 0; i < held.length; i++) hide(held[i]);
    }

    function uncover() {
        if (!covered) return;
        covered = false;
        for (var i = 0; i < held.length; i++) show(held[i]);
    }
}
