local M = {}

local function exec(cmd) return hl.dsp.exec_cmd(cmd) end
local function quote(value) return "'" .. tostring(value):gsub("'", "'\"'\"'") .. "'" end

M.Media = {
  play_pause = function(player)
    return exec("playerctl play-pause" .. (player and " -p " .. quote(player) or ""))
  end,
  pause              = function() return exec("playerctl pause") end,
  next               = function() return exec("playerctl next") end,
  prev               = function() return exec("playerctl previous") end,
  mute_sink          = function() return exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle") end,
  mute_source        = function() return exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle") end,
  volume_up = function(step)
    return exec(string.format('wpctl set-volume -l "1.0" @DEFAULT_AUDIO_SINK@ %d%%+', step))
  end,
  volume_down = function(step)
    return exec(string.format('wpctl set-volume -l "1.0" @DEFAULT_AUDIO_SINK@ %d%%-', step))
  end,
  bright_up   = function() return exec("brightnessctl set 10%+") end,
  bright_down = function() return exec("brightnessctl set 10%-") end,
}

local function burl_ipc(target, fn, ...)
  local args = { ... }
  local cmd = "burl-shell ipc --any-display call " .. quote(target) .. " " .. quote(fn)
  for _, a in ipairs(args) do cmd = cmd .. " " .. quote(a) end
  return exec(cmd)
end

M.Qs = {
  drawer    = function(name) return burl_ipc("drawers", "toggle", name) end,
  focus     = function() return burl_ipc("focusMode", "toggle") end,
  dnd       = function() return burl_ipc("notifs", "toggleDnd") end,
  task      = function() return burl_ipc("taskNudge", "toggle") end,
  switcher  = function() return burl_ipc("switcher", "toggle") end,
  cheatsheet = function() return burl_ipc("cheatsheet", "toggle") end,
  launcher  = function() return burl_ipc("drawers", "toggle", "launcher") end,
  session   = function() return burl_ipc("session", "toggle") end,

  idle      = function() return burl_ipc("idleInhibitor", "toggle") end,

  clipboard   = function() return burl_ipc("launcher", "query", ">clip ") end,
  clipboard_d = function()
    return exec("pkill fuzzel || cliphist list | fuzzel --dmenu --prompt='del > ' --placeholder='Delete from clipboard' | cliphist delete")
  end,

  pip = function() return burl_ipc("resizer", "pip") end,

  emoji = function() return burl_ipc("launcher", "query", ">emoji ") end,

  shot_full   = function() return exec("burl-screenshot") end,
  shot_region = function() return burl_ipc("picker", "open") end,

  shot_history = function() return burl_ipc("screenshots", "toggle") end,

  record         = function() return exec("burl-record") end,
  record_sound   = function() return exec("burl-record -s") end,
  record_region  = function() return exec("burl-record -r") end,
}

M.Sys = {
  lock      = function() return burl_ipc("lock", "lock") end,
  picker    = function() return exec("hyprpicker -a") end,
  shift_del = function() return exec("wtype -k delete") end,
}

return M
