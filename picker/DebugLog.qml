pragma Singleton
import Quickshell

/** Debug logging, gated on EMOJIZASU_DEBUG. One place owns the on/off switch and
    the line format; callers pass a scope tag and a message. */
Singleton {
    readonly property bool enabled: {
        const e = Quickshell.env("EMOJIZASU_DEBUG")
        return e === "1" || e === "true"
    }

    function event(scope, msg) {
        if (!enabled) return
        console.warn("EMZ[" + scope + "] " + msg)
    }
}
