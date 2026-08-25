-- Tsugumori's authoritative Hyprland configuration.
-- Requires Hyprland 0.55.2 or newer.

local home = os.getenv("HOME")
assert(home and home ~= "", "HOME must be set")
local config_home = os.getenv("XDG_CONFIG_HOME")
if not config_home or config_home == "" then
    config_home = home .. "/.config"
end
local quickshell_dir = config_home .. "/quickshell"
local options = require("tsugumori_options")

local function shell_quote(value)
    return "'" .. value:gsub("'", [['"'"']]) .. "'"
end

local function quickshell_script(name)
    return shell_quote(quickshell_dir .. "/" .. name)
end

local function exec(command)
    return hl.dsp.exec_cmd(command)
end

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1,
})

hl.env("PATH", "/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin")
hl.env("XCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")

hl.config({
    input = {
        kb_layout = "us",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = {
            natural_scroll = true,
        },
    },
    general = {
        gaps_in = 4,
        gaps_out = 8,
        border_size = 1,
        col = {
            active_border = "rgba(cc1515ff)",
            inactive_border = "rgba(1a1814aa)",
        },
        layout = "dwindle",
    },
    decoration = {
        rounding = 0,
        blur = {
            enabled = false,
        },
        shadow = {
            enabled = false,
        },
    },
    animations = {
        enabled = true,
    },
    dwindle = {
        preserve_split = true,
    },
    master = {
        new_status = "master",
        mfact = 0.55,
    },
    misc = {
        -- Lets the supervised launcher replace a crashed session-lock client
        -- with Hyprlock instead of leaving the compositor on its lockdead UI.
        allow_session_lock_restore = true,
    },
})

hl.curve("tsugumori", {
    type = "bezier",
    points = { { 0.4, 0 }, { 0.2, 1 } },
})

hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "tsugumori", style = "slide" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "tsugumori", style = "slide" })
hl.animation({ leaf = "fade", enabled = true, speed = 4, bezier = "tsugumori" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "tsugumori", style = "slidevert" })

hl.window_rule({
    name = "tsugumori-quickshell",
    match = { class = "^(quickshell)$" },
    float = true,
    pin = true,
    no_blur = true,
    no_shadow = true,
})

hl.window_rule({
    name = "tsugumori-spotify",
    match = { class = "^(Spotify)$" },
    workspace = "special:spotify",
    fullscreen = true,
})

hl.window_rule({
    name = "tsugumori-yazi-picker",
    match = { class = "^(qs-yazi-picker)$" },
    float = true,
    size = { 900, 600 },
    center = true,
})

local quickshell_command = "env "
if options.vm_software_gl then
    quickshell_command = quickshell_command .. "LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe "
end
quickshell_command = quickshell_command
    .. "QT_MEDIA_BACKEND=ffmpeg QT_QPA_PLATFORM=wayland "
    .. "QT_WAYLAND_DISABLE_WINDOWDECORATION=1 /usr/bin/qs"

local session_start_command = quickshell_script("session-start.sh")
if options.boot_wallpaper then
    session_start_command = session_start_command .. " --restore-wallpaper"
end

hl.on("hyprland.start", function()
    hl.exec_cmd(quickshell_command)
    hl.exec_cmd(quickshell_script("lock.sh"))
    hl.exec_cmd("hypridle")
    hl.exec_cmd("udiskie")
    hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1")
    hl.exec_cmd(quickshell_script("wave-check.sh"))
    hl.exec_cmd(session_start_command)
end)

-- Launcher and Quickshell panels.
hl.bind("SUPER + Super_L", exec("qs ipc call tsugumoriShell toggleMenu"), { release = true })
hl.bind("SUPER + Tab", exec(quickshell_script("ctrl.sh")))
hl.bind("SUPER + L", exec(quickshell_script("lock.sh")), { release = true })
hl.bind("SUPER + Return", exec("qs ipc call tsugumoriShell togglePlayer"))
hl.bind("SUPER + SHIFT + Return", exec("qs ipc call tsugumoriShell toggleFront"))

-- Applications.
local kitty_command = "/usr/bin/kitty"
if options.vm_software_gl then
    kitty_command = "env LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe KITTY_GPU_DISABLED=1 /usr/bin/kitty"
end

hl.bind("SUPER + T", exec(kitty_command))
hl.bind("SUPER + M", function()
    if #hl.get_windows({ class = "Spotify" }) > 0 then
        hl.dispatch(hl.dsp.workspace.toggle_special("spotify"))
    else
        hl.exec_cmd("spotify")
    end
end)
hl.bind("SUPER + R", exec(quickshell_script("restart.sh")))
hl.bind("SUPER + P", exec(quickshell_script("wallpaper.sh")))

-- Window management.
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("SUPER + F", hl.dsp.window.fullscreen())
hl.bind("SUPER + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + Escape", hl.dsp.exit())
hl.bind("SUPER + D", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind("SUPER + W", function()
    hl.config({ general = { layout = "master" } })
end)
hl.bind("SUPER + SHIFT + W", function()
    hl.config({ general = { layout = "dwindle" } })
end)

-- Focus and directional movement.
hl.bind("ALT + Tab", hl.dsp.window.cycle_next())
hl.bind("ALT + SHIFT + Tab", hl.dsp.window.cycle_next({ next = false }))

local directions = {
    left = "left",
    right = "right",
    up = "up",
    down = "down",
}

for key, direction in pairs(directions) do
    hl.bind("SUPER + " .. key, hl.dsp.focus({ direction = direction }))
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ direction = direction }))
end

-- Workspaces.
hl.bind("SUPER + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind("SUPER + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

for workspace = 1, 10 do
    local key = workspace % 10
    hl.bind("ALT + " .. key, hl.dsp.focus({ workspace = workspace }))
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ workspace = workspace }))
end

hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" }))
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Audio, brightness, and screenshots.
hl.bind("XF86AudioRaiseVolume", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"))
hl.bind("XF86AudioLowerVolume", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"))
hl.bind("XF86AudioMute", exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
hl.bind("XF86MonBrightnessUp", exec("brightnessctl set 5%+"))
hl.bind("XF86MonBrightnessDown", exec("brightnessctl set 5%-"))
hl.bind("ALT + SHIFT + S", exec("hyprshot -m region"))
hl.bind("Print", exec([[grim -g "$(slurp)" "$HOME/Screenshots/$(date +%Y%m%d_%H%M%S).png"]]))

-- Loaded last so machine-specific settings can override Tsugumori defaults.
-- The installer always creates and preserves this module.
require("user")
