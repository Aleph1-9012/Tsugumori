.pragma library

// Sanitize notification markup for Text.StyledText. Only b, i, u and br
// survive; all other tags are dropped while their inner text is kept.
const _ALLOWED = {b: true, i: true, u: true}
const _TAG = /<\/?([A-Za-z][A-Za-z0-9-]*)(\s[^<>]*)?\/?>/g
const _ENTITY = /&(#x[0-9A-Fa-f]+|#[0-9]+|amp|lt|gt|quot|apos);/g

function _decodeEntities(text) {
    return text.replace(_ENTITY, function(match, name) {
        if (name[0] === "#") {
            const value = name[1] === "x" || name[1] === "X"
                ? parseInt(name.substring(2), 16) : parseInt(name.substring(1), 10)
            if (value > 0 && value <= 0x10FFFF && !(value >= 0xD800 && value <= 0xDFFF))
                return String.fromCodePoint(value)
            return match
        }
        switch (name) {
        case "amp":  return "&"
        case "lt":   return "<"
        case "gt":   return ">"
        case "quot": return '"'
        case "apos": return "'"
        }
        return match
    })
}

function _escape(text) {
    return _decodeEntities(text)
        .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function toStyledText(markup) {
    if (markup === null || markup === undefined || markup === "") return ""

    const source = String(markup).replace(/\r\n|\r|\n/g, "<br>")
    const open = []
    let output = ""
    let cursor = 0

    _TAG.lastIndex = 0
    let match
    while ((match = _TAG.exec(source)) !== null) {
        output += _escape(source.substring(cursor, match.index))
        cursor = match.index + match[0].length

        const closing = match[0][1] === "/"
        const selfClosing = match[0][match[0].length - 2] === "/"
        const name = match[1].toLowerCase()

        if (name === "br" && !closing) {
            output += "<br>"
        } else if (!_ALLOWED[name]) {
            // Drop the tag; inner text is preserved by the text cursor.
        } else if (closing) {
            const index = open.lastIndexOf(name)
            if (index >= 0) {
                // Close the tag plus anything opened after it, then reopen
                // those inner tags so nesting stays well formed.
                const above = open.splice(index).reverse()
                for (let i = 0; i < above.length; ++i) output += "</" + above[i] + ">"
                for (let i = above.length - 2; i >= 0; --i) {
                    open.push(above[i])
                    output += "<" + above[i] + ">"
                }
            }
        } else if (!selfClosing) {
            open.push(name)
            output += "<" + name + ">"
        } else {
            // Self-closing allowed tag: emit a balanced pair.
            output += "<" + name + "></" + name + ">"
        }
    }

    output += _escape(source.substring(cursor))
    for (let i = open.length - 1; i >= 0; --i) output += "</" + open[i] + ">"
    return output
}
