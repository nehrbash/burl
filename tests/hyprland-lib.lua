local calls, scope = {}, nil
local function record(kind, ...)
  calls[#calls + 1] = { kind = kind, scope = scope, args = { ... } }
end
hl = {
  bind = function(...) record("bind", ...) end,
  window_rule = function(spec) record("window", spec) end,
  layer_rule = function(spec) record("layer", spec) end,
  workspace_rule = function(spec) record("workspace", spec) end,
  define_submap = function(name, callback)
    scope = name
    callback()
    scope = nil
  end,
  dsp = {
    exec_cmd = function(command) return { exec = command } end,
    submap = function(name) return { submap = name } end,
  },
}
local lib = dofile("hyprland/lib.lua")
local action, options = function() end, { repeatable = true }
lib.Bind.keys({ { "SUPER + A", action, options, desc = 'Open "A"\nnext\\line' }, {} })
assert(#calls == 1 and calls[1].args[1] == "SUPER + A")
assert(calls[1].args[2] == action and calls[1].args[3] == options)
lib.Bind.prefixed("SUPER + SHIFT", "Windows")({ { "B", action, desc = "Move" } })
assert(calls[2].args[1] == "SUPER + SHIFT + B")
lib.Bind.range("SUPER", 1, 3, function(i) return { { workspace = i }, options } end, "Select workspace")
assert(#calls == 5)
for i = 1, 3 do
  assert(calls[i + 2].args[1] == "SUPER + " .. i)
  assert(calls[i + 2].args[2].workspace == i)
  assert(calls[i + 2].args[3] == options)
end
local path = os.tmpname()
lib.Bind.dump(path)
local stream = assert(io.open(path))
local json = stream:read("*a")
stream:close()
os.remove(path)
assert(json == '[{"key":"SUPER + A","desc":"Open \\"A\\"\\u000anext\\\\line","group":""},{"key":"SUPER + SHIFT + B","desc":"Move","group":"Windows"},{"key":"SUPER + 1..3","desc":"Select workspace","group":""}]')

calls = {}
local rule = { name = "editor", match = { class = "^(editor|terminal)$" }, opacity = 1 }
lib.Rule.window(rule)
assert(calls[1].kind == "window" and calls[1].args[1] == rule)
lib.Rule.float({ class = "org.Example", title = "Settings" })
local floated = calls[2].args[1]
assert(floated.float and floated.name == "float-org_Example")
assert(floated.match.class == "org.Example" and floated.match.title == "Settings")
lib.Rule.layer(rule)
lib.Rule.workspace(rule)
assert(calls[3].kind == "layer" and calls[4].kind == "workspace")

local warnings, stderr = {}, io.stderr
io.stderr = { write = function(_, message) warnings[#warnings + 1] = message end }
lib.Rule.window({ name = "bad", match = { class = "(broken" } })
lib.Rule.window({ name = "escaped", match = { title = "\\(literal\\)" } })
lib.Bind.dump("/nonexistent/burl-test/keybinds.json")
io.stderr = stderr
assert(#warnings == 2 and warnings[1]:find("unbalanced", 1, true))
assert(warnings[2]:find("cannot write keybind dump", 1, true))
assert(calls[5].kind == "window" and calls[6].kind == "window")

calls = {}
local entered = false
lib.Submap.define({
  name = "Capture", enter = "SUPER + C", on_enter = function() entered = true end,
  binds = { { "T", "terminal", options }, { "N", action } },
  shot = { { "S", "screenshot", { locked = true } } },
})
assert(entered and #calls == 7)
assert(calls[1].scope == nil and calls[1].args[2].submap == "Capture")
assert(calls[2].scope == "Capture" and calls[2].args[2].exec == "terminal")
assert(calls[2].args[3] == options and calls[3].args[2] == action)
assert(calls[4].args[2].exec == "screenshot" and calls[4].args[3].release and calls[4].args[3].locked)
assert(calls[5].args[2].submap == "reset" and calls[5].args[3].release)
assert(calls[6].args[1] == "escape" and calls[7].args[1] == "BackSpace")
calls = {}
lib.Submap.define({ name = "Empty", escape = {} })
assert(#calls == 0)
lib.Submap.define({ name = "Custom", escape = { "Q" } })
assert(#calls == 1 and calls[1].args[1] == "Q" and calls[1].args[2].submap == "reset")
print("PASS: Hyprland bindings, description export, rules and submap dispatch")

local pending, windows, workspaceExists = {}, {}, false
hl.get_workspace = function(name)
  assert(name == "special:files")
  return workspaceExists and { name = name } or nil
end
hl.get_workspace_windows = function(workspace)
  assert(workspace.name == "special:files")
  return windows
end
hl.exec_cmd = function(command) record("exec", command) end
hl.dispatch = function(action) record("dispatch", action) end
hl.dsp.workspace = { toggle_special = function(name) return { special = name } end }
hl.timer = function(callback, options) pending[#pending + 1] = { callback, options } end
local scratchpads = dofile("hyprland/scratchpad.lua")
local files = scratchpads.new({ workspace = "files", command = "nautilus" })
calls = {}
files.toggle()
assert(#calls == 1 and calls[1].kind == "exec" and calls[1].args[1] == "nautilus")
assert(#pending == 1 and pending[1][2].timeout == 300 and pending[1][2].type == "oneshot")
pending[1][1]()
assert(calls[2].kind == "dispatch" and calls[2].args[1].special == "files")
workspaceExists = true
windows = { { class = "org.gnome.Nautilus" } }
calls, pending = {}, {}
files.toggle()
assert(#calls == 1 and calls[1].kind == "dispatch" and #pending == 0)
windows = nil
local custom = scratchpads.new({ workspace = "files", command = "custom-manager", delay = 450 })
calls = {}
custom.toggle()
assert(calls[1].args[1] == "custom-manager" and pending[1][2].timeout == 450)
assert(not pcall(scratchpads.new, { command = "nautilus" }))
assert(not pcall(scratchpads.new, { workspace = "files" }))
print("PASS: scratchpad spawning, mapped-window toggles and configurable delay")
