local M = {}
local directory = debug.getinfo(1, "S").source:sub(2):match("^(.*)/")

local function read_palette(path, colours)
  local file = io.open(path, "r")
  if not file then return end
  for line in file:lines() do
    local name, value = line:match("^%s*%$?([%w_]+)%s*=?%s+(%x+)%s*$")
    if name and #value == 6 then colours[name] = value end
  end
  file:close()
end

local function merge(target, overrides)
  for key, value in pairs(overrides or {}) do
    if type(value) == "table" and type(target[key]) == "table" then
      merge(target[key], value)
    else
      target[key] = value
    end
  end
  return target
end

function M.theme(path)
  local config = os.getenv("XDG_CONFIG_HOME") or os.getenv("HOME") .. "/.config"
  local colours = {}
  read_palette(directory .. "/default.txt", colours)
  read_palette(path or config .. "/hypr/scheme/current.conf", colours)
  local theme = {}

  function theme.rgb(name)
    return "rgb(" .. assert(colours[name], "Unknown palette role: " .. name) .. ")"
  end

  function theme.rgba(name, alpha)
    return "rgba(" .. assert(colours[name], "Unknown palette role: " .. name) .. (alpha or "ff") .. ")"
  end

  function theme.apply(overrides)
    local rgb, rgba = theme.rgb, theme.rgba
    local config = {
      general = { col = {
        active_border = rgba("primary", "e6"),
        inactive_border = rgba("outlineVariant", "aa"),
      } },
      decoration = { shadow = { color = rgba("surface", "d4") } },
      group = {
        col = {
          border_active = rgba("primary", "e6"),
          border_inactive = rgba("outlineVariant", "aa"),
          border_locked_active = rgba("primary", "e6"),
          border_locked_inactive = rgba("outlineVariant", "aa"),
        },
        groupbar = {
          text_color = rgb("onPrimary"),
          col = {
            active = rgba("primary", "d4"),
            inactive = rgba("outline", "d4"),
            locked_active = rgba("primary", "d4"),
            locked_inactive = rgba("secondary", "d4"),
          },
        },
      },
      misc = { background_color = rgb("surfaceContainer") },
    }
    if hl.plugin and hl.plugin.hyprbars then
      config.plugin = { hyprbars = {
        bar_color = rgb("surfaceContainer"),
        ["col.text"] = rgb("onSurface"),
        inactive_button_color = rgb("surfaceContainerLow"),
      } }
    end
    hl.config(merge(config, overrides))
  end

  return theme
end

function M.layer_rules()
  hl.layer_rule({ name = "burl-noanim",
    match = { namespace = "qs-(border-exclusion|area-picker)" }, no_anim = true })
  hl.layer_rule({ name = "burl-fade",
    match = { namespace = "qs-(drawers|background|task-nudge)" }, animation = "fade" })
  hl.layer_rule({ name = "burl-blur", match = { namespace = "qs-drawers" },
    blur = true, ignore_alpha = 0.57 })
end

return M
