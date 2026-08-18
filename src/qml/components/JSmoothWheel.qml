import QtQuick

// Smooth, fast mouse-wheel scrolling for any Flickable-derived view (GridView,
// ListView, Flickable). Qt's built-in wheel handling moves in small unanimated
// steps that feel sluggish on desktop; this replaces it with a longer eased
// glide. Declare directly inside the view:
//     GridView { JSmoothWheel {} }
// (pointer handlers declared in a Flickable attach to the Flickable itself,
// not its content item). Touchpads keep native pixel-precise scrolling — only
// discrete mouse-wheel notches are animated.
WheelHandler {
    id: wheel

    property real step: 260   // px per wheel notch
    property int glideMs: 220

    readonly property Flickable flick: parent as Flickable

    target: null
    acceptedDevices: PointerDevice.Mouse

    // Where the glide is headed; consecutive notches stack onto this instead of
    // the current position so fast spins accelerate rather than restart.
    property real pendingY: 0

    property NumberAnimation glide: NumberAnimation {
        target: wheel.flick
        property: "contentY"
        duration: wheel.glideMs
        easing.type: Easing.OutCubic
    }

    // A manual drag (or scrollbar grab) takes over instantly.
    property Connections dragWatch: Connections {
        target: wheel.flick
        function onDraggingChanged() {
            if (wheel.flick.dragging)
                wheel.glide.stop()
        }
    }

    onWheel: (event) => {
        if (!flick || flick.contentHeight <= flick.height)
            return
        const minY = flick.originY - flick.topMargin
        const maxY = Math.max(minY, flick.originY + flick.contentHeight + flick.bottomMargin - flick.height)
        const from = glide.running ? pendingY : flick.contentY
        pendingY = Math.max(minY, Math.min(from - (event.angleDelta.y / 120) * step, maxY))
        glide.stop()
        glide.from = flick.contentY
        glide.to = pendingY
        glide.start()
    }
}
