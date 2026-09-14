import QtQuick

// One shared timeline for every monitor. No application or system actions.
Item {
    id: motion
    property real progress: 0
    property bool started: false
    property bool opening: false
    property bool closing: false
    property bool finished: false
    readonly property bool inputReady: started && !opening && !closing && !finished && progress === 1
    signal closed()

    function open() {
        if (started || closing || finished) return;
        started = true;
        opening = true;
        appear.start();
    }
    function close() {
        if (closing || finished) return;
        appear.stop();
        opening = false;
        closing = true;
        disappear.from = progress;
        disappear.duration = Math.max(1, Math.round(950 * progress));
        disappear.start();
    }
    NumberAnimation {
        id: appear
        target: motion; property: "progress"
        from: 0; to: 1; duration: 1450
        onFinished: motion.opening = false
    }
    NumberAnimation {
        id: disappear
        target: motion; property: "progress"
        to: 0
        onFinished: { motion.finished = true; motion.closed(); }
    }
}
