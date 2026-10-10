hl = { dsp = { exec_cmd = function(command) return command end } }
local actions = dofile("hyprland/actions.lua")
assert(actions.Media.play_pause() == "playerctl play-pause")
assert(actions.Media.play_pause("player one") == "playerctl play-pause -p 'player one'")
assert(actions.Qs.clipboard() == "burl-shell ipc --any-display call 'launcher' 'query' '>clip '")
assert(actions.Qs.drawer("a'b") == "burl-shell ipc --any-display call 'drawers' 'toggle' 'a'\"'\"'b'")
assert(actions.Sys.lock() == "burl-shell ipc --any-display call 'lock' 'lock'")
assert(actions.Qs.record_region() == "burl-record -r")
print("PASS: Hyprland actions preserve IPC arguments and configurable player selection")
