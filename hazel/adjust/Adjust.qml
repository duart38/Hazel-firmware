// Adjusting the film recipe on the camera, over live view. On the camera as
// /tmp/x1d/adjust/Adjust.qml with the files beside it; recipelabel.c creates it once at start-up
// under the interface's main item, next to recipe-label.qml, and it adds itself to the back screen
// the same way the recipe name does. Not to the viewfinder: it has no touch to open it with and
// too little room, so putting the camera to the eye closes the view, as a half press does.
//
// This file is the only part that knows the camera: its windows and live view, its keys
// (qrc:///scripts/Keys.js, the X1D's own mapping), its body state, its constants. The flow is
// AdjustState.qml, the look AdjustView.qml.
//
// The camera's settings menu stops live view (notes/07), so none of this is a menu page. It is a
// layer over live view, like the camera's own ISO and white-balance strip: while it is open the
// body is in its menu state, which is what that strip does too, so both wheels arrive here as
// keys instead of changing aperture and shutter speed. A half press, Play, or live view ending
// closes it at once and hands the body back, keeping whatever is on screen.
// Written by Claude (Claude Code); see notes/17-on-camera-adjust.md.
import QtQuick 2.4
import com.hasselblad.video 1.0
import com.hasselblad.bodysync 1.0
import com.hasselblad.globalstateinfo 1.0
import "qrc:///common"
import "qrc:///scripts/Keys.js" as MKeys

Item {
    id: adjust

    GlobalConstants { id: constants }

    AdjustState {
        id: flow
        keys: ({match: MKeys.pressedFn})
        onOpened: {
            BodySync.currentState = BodySync.MENU;
            for (var w in adjust.views) adjust.views[w].forceActiveFocus();
            for (var l in adjust.liveViews) stock.take(adjust.liveViews[l]);
            stock.cover();
        }
        onClosed: {
            stock.uncover();
            BodySync.currentState = BodySync.MAIN;
            for (var w in adjust.liveViews) if (adjust.liveViews[w]) adjust.liveViews[w].forceActiveFocus();
        }
    }

    // the camera's touch shutter and bottom readouts, out of sight while the view is open
    StockReadouts { id: stock }

    property var views: ({})
    property var liveViews: ({})
    property var live: ({})

    function attach() {
        for (var i = 0; i < parent.children.length; i++) {
            var loader = parent.children[i];
            var which = loader.objectName === "TouchWindow_loader" ? "screen" : "";
            if (!which || views[which] || !loader.item || !loader.item.contentItem) continue;
            var content = loader.item.contentItem;
            var made = holder.createObject(content, {flow: flow, constants: constants, touch: which === "screen"});
            if (!made) continue;
            // a binding, not a value: the window may not have its size yet when this runs (on the
            // camera's interface it is still 0x0 then, and every size came out 0)
            made.unit = Qt.binding(function (c) {
                return function () { return Math.min(c.width / 1024.0, c.height / 728.0) / 0.625; };
            }(content));
            views[which] = made;
            console.log("Adjust.qml: added to the " + which);
        }
    }

    Timer {
        interval: 1000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: { adjust.attach(); flow.refresh(); }
    }

    Component {
        id: holder
        AdjustView {
            id: view
            anchors.fill: parent
            z: 1001

            property Item liveView: null
            function findLiveView(item) {
                for (var i = 0; i < item.children.length && !liveView; i++) {
                    var child = item.children[i];
                    if (child === view) continue;
                    if (typeof child.infoVisible === "boolean" && typeof child.sizeFactor === "number") liveView = child;
                    else findLiveView(child);
                }
            }
            // the recipe name recipe-label.qml draws: the entry button goes just after it
            function findName(item) {
                for (var i = 0; i < item.children.length; i++) {
                    var child = item.children[i];
                    if (child === view) continue;
                    if (typeof child.liveViewName === "string") {
                        for (var k = 0; k < child.children.length; k++) {
                            var t = child.children[k];
                            if (t.visible && typeof t.text === "string" && t.text !== "" && t.text === child.liveViewName) return t;
                        }
                        return null;
                    }
                }
                return null;
            }

            Timer {
                interval: 300; repeat: true; running: true
                onTriggered: {
                    if (!view.liveView) view.findLiveView(view.parent);
                    var lv = view.liveView;
                    adjust.liveViews.screen = lv;
                    if (flow.mode !== "closed") stock.take(lv);
                    var live = lv !== null && lv.visible && VideoControl.videoMode === VideoControl.View
                            && !GlobalStateInfo.evfActive;
                    view.entryShown = live && lv.infoVisible && flow.lookOn && BodySync.currentState === BodySync.MAIN;
                    var name = view.findName(view.parent);
                    if (name) {
                        var left = name.mapToItem(view, 0, name.height / 2);
                        view.placeEntry(left.x, left.x + name.width, left.y);
                    } else {
                        view.entryX = 30 * view.unit;
                        view.entryY = 112 * view.unit;
                    }
                    // live view left the back screen (the eye at the viewfinder, Play, the menu,
                    // sleep): out of the way, edits kept
                    adjust.live.screen = live;
                    if (flow.mode !== "closed" && !live) flow.hide();
                }
            }
        }
    }
}
