pragma Singleton
import QtQml

// QtTest cannot load Quickshell's executable-only plugin. Player only needs env.
QtObject {
    property bool reduceMotion: false
    function env(name) {
        return name === "TSUGUMORI_REDUCED_MOTION" && reduceMotion ? "1" : ""
    }
}
