local root = debug.getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/.."
local autostart = dofile(root .. "/hyprland/autostart.lua")

local function fixture()
  local active, commands, timers = nil, {}, {}
  local workspaces = { ["4"] = { name = "4", windows = {} } }
  hl = {
    on = function(event, callback)
      assert(event == "workspace.active")
      active = callback
    end,
    get_workspace = function(name) return workspaces[name] end,
    get_workspace_windows = function(workspace) return workspace.windows end,
    exec_cmd = function(command) commands[#commands + 1] = command end,
    timer = function(callback, options)
      assert(options.type == "oneshot")
      timers[#timers + 1] = { callback = callback, timeout = options.timeout }
    end,
  }
  return {
    workspaces = workspaces, commands = commands, timers = timers,
    activate = function(workspace) active(workspace) end,
  }
end

local ready = false
local h = fixture()
autostart.setup({ ["4"] = { cmd = "browser", needs = { "network" } } },
                { network = function() return ready end })
h.activate(nil)
h.activate({ name = "other", windows = {} })
assert(#h.commands == 0 and #h.timers == 0)
h.activate(h.workspaces["4"])
h.activate(h.workspaces["4"])
assert(#h.commands == 0 and #h.timers == 1 and h.timers[1].timeout == 1500)
ready = true
h.timers[1].callback()
assert(h.commands[1] == "browser" and h.timers[2].timeout == 10000)
h.activate(h.workspaces["4"])
assert(#h.commands == 1)
h.timers[2].callback()
h.workspaces["4"].windows = { {} }
h.activate(h.workspaces["4"])
assert(#h.commands == 1)
h.workspaces["4"].windows = {}
h.activate(h.workspaces["4"])
assert(#h.commands == 2)

local second = fixture()
autostart.setup({ ["4"] = { cmd = "terminal" } })
second.activate(second.workspaces["4"])
assert(second.commands[1] == "terminal")
assert(#h.commands == 2)

local waiting = fixture()
autostart.setup({ ["4"] = { cmd = "mail", needs = { "missing" } } }, {})
waiting.activate(waiting.workspaces["4"])
waiting.workspaces["4"] = nil
waiting.timers[1].callback()
assert(#waiting.commands == 0 and #waiting.timers == 1)

local original_open = io.open
local closed = false
io.open = function(path)
  assert(path == "/proc/net/route")
  local lines = { "Iface Destination", "eth0 00000000" }
  return {
    lines = function()
      local i = 0
      return function() i = i + 1; return lines[i] end
    end,
    close = function() closed = true end,
  }
end
assert(autostart.has_default_route() and closed)
io.open = function() return nil end
assert(not autostart.has_default_route())
io.open = original_open
print("PASS autostart gates, retries, debounce, empty workspaces, and instance isolation")
