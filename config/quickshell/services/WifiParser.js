.pragma library

// nmcli --terse escapes both ':' and '\\' inside a field.
function fields(line) {
    const result = []
    let value = ""

    for (let i = 0; i < line.length; ++i) {
        const character = line[i]

        if (character === "\\" && i + 1 < line.length) {
            value += line[++i]
        } else if (character === ":") {
            result.push(value)
            value = ""
        } else {
            value += character
        }
    }

    result.push(value)
    return result
}

function parse(text) {
    const lines = text.trim().split("\n")
    const seen = new Map()
    let currentSsid = ""

    for (let i = 1; i < lines.length; ++i) {
        const parts = fields(lines[i])

        if (parts.length !== 4 || !parts[1]) continue

        const active = parts[0] === "*"
        const ssid = parts[1]
        const signal = parseInt(parts[2], 10) || 0
        const previous = seen.get(ssid)

        if (active) currentSsid = ssid
        if (previous && (previous.active || (previous.signal >= signal && !active))) continue

        seen.set(ssid, {ssid: ssid, signal: signal, security: parts[3] || "Open", active: active})
    }

    const networks = Array.from(seen.values())
    networks.sort(function(a, b) {
        if (a.active !== b.active) return a.active ? -1 : 1
        return b.signal - a.signal
    })

    return {enabled: lines[0] === "enabled", currentSsid: currentSsid, networks: networks}
}
