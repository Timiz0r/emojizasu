.pragma library

/** fcitx keysyms (X11 keysym values) for the keys we act on. */
const keyBackspace = 0xff08
const keyReturn    = 0xff0d
const keyKpEnter   = 0xff8d
const keyEscape    = 0xff1b
const keyLeft      = 0xff51
const keyUp        = 0xff52
const keyRight     = 0xff53
const keyDown      = 0xff54
const keyTab       = 0xff09
const keyShiftTab  = 0xfe20
const keyA         = 0x61
const keyC         = 0x63
const keyV         = 0x76
const keyX         = 0x78

/**
 * Parse a wire-format key line "<sym> <states> <text>" (text may be empty or
 * contain spaces) into [sym, states, text], or null if malformed.
 */
function parseKeyLine(line) {
    const firstSpace = line.indexOf(' ')
    if (firstSpace < 0) return null
    const secondSpace = line.indexOf(' ', firstSpace + 1)
    if (secondSpace < 0) return null
    return [
        parseInt(line.substring(0, firstSpace)),
        parseInt(line.substring(firstSpace + 1, secondSpace)),
        line.substring(secondSpace + 1)
    ]
}

/**
 * Pure key router: given a raw wire-format key line and the focused zone
 * (internalFocus: "search"|"categories"|"grid"), decide what should happen and
 * return an intent for the panel to apply. Intents: close | activate |
 * insert{text} | clipboard{op} | deleteBack | cursorLeft | cursorRight |
 * advanceFromSearch | setCategory{direction} | engageSearch | focusGrid |
 * leaveGridBackward | navGrid{direction} | none. The router owns all
 * keysym/modifier decisions; the panel never inspects sym/states, it only applies
 * intents against its widgets. Category and grid moves emit a direction
 * ("left"/"right" for categories; "up"/"down"/"left"/"right" for the grid) and the
 * panel resolves it against its own data/geometry (list bounds, exit-up).
 */
function route(line, internalFocus) {
    const parsed = parseKeyLine(line)
    if (parsed === null) return { kind: "none" }
    const [sym, states, text] = parsed

    const shiftHeld = (states & 1) !== 0
    const ctrlHeld  = (states & 4) !== 0

    if (sym === keyEscape) return { kind: "close" }
    if (sym === keyReturn || sym === keyKpEnter) return { kind: "activate" }

    if (!ctrlHeld && text && text.length > 0 && sym !== keyTab && sym !== keyShiftTab)
        return { kind: "insert", text: text }

    if (ctrlHeld && shiftHeld) {
        const step = 10
        if (sym === keyLeft)  return { kind: "moveWindow", dx: -step, dy: 0 }
        if (sym === keyRight) return { kind: "moveWindow", dx:  step, dy: 0 }
        if (sym === keyUp)    return { kind: "moveWindow", dx: 0, dy: -step }
        if (sym === keyDown)  return { kind: "moveWindow", dx: 0, dy:  step }
    }

    if (ctrlHeld) {
        let op = ""
        // Not clipboard, but meh
        if (sym === keyA) op = "selectAll"
        else if (sym === keyC) op = "copy"
        else if (sym === keyX) op = "cut"
        else if (sym === keyV) op = "paste"
        return { kind: "clipboard", op: op }
    }

    if (internalFocus === "search") {
        if (sym === keyBackspace) return { kind: "deleteBack" }
        if (sym === keyLeft) return { kind: "cursorLeft" }
        if (sym === keyRight) return { kind: "cursorRight" }
        if (sym === keyShiftTab || (sym === keyTab && shiftHeld)) return { kind: "none" }
        if (sym === keyDown || sym === keyTab) return { kind: "advanceFromSearch" }
        return { kind: "none" }
    }

    if (internalFocus === "categories") {
        if (sym === keyLeft)  return { kind: "setCategory", direction: "left" }
        if (sym === keyRight) return { kind: "setCategory", direction: "right" }
        if (sym === keyUp) return { kind: "engageSearch" }
        if (sym === keyDown) return { kind: "focusGrid" }
        if (sym === keyShiftTab || (sym === keyTab && shiftHeld)) return { kind: "engageSearch" }
        if (sym === keyTab) return { kind: "focusGrid" }
        return { kind: "none" }
    }

    if (internalFocus === "grid") {
        if (sym === keyShiftTab || (sym === keyTab && shiftHeld)) return { kind: "leaveGridBackward" }
        if (sym === keyTab) return { kind: "none" }
        if (sym === keyLeft)  return { kind: "navGrid", direction: "left" }
        if (sym === keyRight) return { kind: "navGrid", direction: "right" }
        if (sym === keyUp)    return { kind: "navGrid", direction: "up" }
        if (sym === keyDown)  return { kind: "navGrid", direction: "down" }
        return { kind: "none" }
    }

    return { kind: "none" }
}

/**
 * Grid-navigation math for the category browse view (a `cols`-wide grid of
 * `total` emoji). Given a direction and current index, returns the new index,
 * clamped at the grid edges. Does not clamp negatives — callers seed ≥ 0.
 */
function nextBrowseIndex(direction, current, cols, total) {
    let idx = current
    if (direction === "left") { if (idx % cols > 0) idx-- }
    else if (direction === "right") { if (idx % cols < cols - 1 && idx + 1 < total) idx++ }
    else if (direction === "up") { if (idx - cols >= 0) idx -= cols }
    else if (direction === "down") { if (idx + cols < total) idx += cols }
    return idx
}

/**
 * Grid-navigation math for the kaomoji view (a single vertical list of `total`
 * items). Only up/down move; returns the new index clamped to the list ends.
 */
function nextKaomojiIndex(direction, current, total) {
    let idx = current
    if (direction === "up") { if (idx > 0) idx-- }
    else if (direction === "down") { if (idx < total - 1) idx++ }
    return idx
}

/**
 * Grid-navigation math for the search results view: a `cols`-wide emoji flow of
 * `emojiCount` items, followed by a vertical list of `kaomojiCount` kaomoji (one
 * flat index space, emoji first). Down from the emoji flow's last row crosses
 * into the kaomoji list; Up from its top crosses back. Returns the new index.
 */
function nextSearchIndex(direction, current, emojiCount, kaomojiCount, cols) {
    let idx = current
    const total = emojiCount + kaomojiCount
    if (idx < emojiCount) {
        if (direction === "left") {
            if (idx % cols > 0) idx--
        } else if (direction === "right") {
            if (idx % cols < cols - 1 && idx + 1 < emojiCount) idx++
        } else if (direction === "up") {
            if (idx - cols >= 0) idx -= cols
        } else if (direction === "down") {
            if (idx + cols < emojiCount) idx += cols
            else if (kaomojiCount > 0) idx = emojiCount
        }
    } else {
        const ki = idx - emojiCount
        if (direction === "up") {
            if (ki > 0) idx--
            else if (emojiCount > 0) idx = emojiCount - 1
        } else if (direction === "down") {
            if (idx + 1 < total) idx++
        }
    }
    return idx
}
