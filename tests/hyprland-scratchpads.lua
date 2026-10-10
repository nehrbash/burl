local root = debug.getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/.."
local scratchpads = dofile(root .. "/hyprland/scratchpads.lua")
local calls, timers, animations, visible = {}, {}, {}, {}
hl = {
  get_workspace = function(name) return { visible = visible[name] or false } end,
  dispatch = function(action) calls[#calls + 1] = action end,
  animation = function(value) animations[#animations + 1] = value end,
  timer = function(callback, options)
    assert(options.timeout == 600 and options.type == "oneshot")
    timers[#timers + 1] = callback
  end,
  dsp = {
    workspace = { toggle_special = function(name) return "toggle:" .. name end },
    window = { move = function(options) return "move:" .. options.workspace end },
  },
}
local state = { current = 1, max = 1 }
local animation = { navigate = { style = "horizontal" }, restore = { style = "vertical" }, timeout = 600 }
local mini = scratchpads.new({ name = "mini", state = state, animation = animation })
mini.toggle()
mini.move_window_to_current()
assert(calls[1] == "toggle:mini" and calls[2] == "move:special:mini")
mini.nav(-1)
assert(#calls == 2 and #timers == 0)
visible["special:mini"] = true
mini.nav(1)
assert(calls[3] == "toggle:mini" and calls[4] == "toggle:mini2")
assert(state.current == 2 and state.max == 2)
mini.nav(1)
assert(calls[5] == "toggle:mini3" and state.max == 3)
assert(#timers == 1 and #animations == 2)
timers[1]()
assert(animations[3] == animation.restore)
mini.nav(-1)
mini.nav(-1)
mini.nav(-1)
assert(state.current == 3 and state.max == 3)
assert(#timers == 2)
mini.move_window_to_current()
assert(calls[#calls] == "move:special:mini3")

local notes = scratchpads.new({ name = "notes" })
local before = #animations
notes.toggle()
notes.nav(1)
assert(calls[#calls - 1] == "toggle:notes" and calls[#calls] == "toggle:notes2")
assert(#animations == before and state.current == 3)
local reloaded = scratchpads.new({ name = "mini", state = state })
reloaded.toggle()
assert(calls[#calls] == "toggle:mini3")
local fresh = scratchpads.new({ name = "mini" })
fresh.toggle()
assert(calls[#calls] == "toggle:mini")
print("PASS scratchpad names, navigation, visibility, animation restoration, and instance state")
