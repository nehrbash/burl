local M = {}

local function warn(fmt, ...)
  io.stderr:write("[hypr] " .. string.format(fmt, ...) .. "\n")
end

-- Lua cannot compile Hyprland’s RE2 patterns; only check delimiters.
local function check_balanced(pat, name, what)
  local depth = 0
  local bracket = false
  local i = 1
  while i <= #pat do
    local c = pat:sub(i, i)
    if c == "\\" then
      i = i + 2
    else
      if not bracket then
        if c == "(" then depth = depth + 1
        elseif c == ")" then depth = depth - 1
          if depth < 0 then
            warn("rule '%s' %s: unbalanced ')' in %q", name, what, pat)
            return false
          end
        elseif c == "[" then bracket = true end
      else
        if c == "]" then bracket = false end
      end
      i = i + 1
    end
  end
  if depth ~= 0 then
    warn("rule '%s' %s: unbalanced '(' in %q", name, what, pat)
    return false
  end
  if bracket then
    warn("rule '%s' %s: unbalanced '[' in %q", name, what, pat)
    return false
  end
  return true
end

local match_keys_with_regex = {
  class = true, title = true, initialClass = true, initialTitle = true,
}

local function validate_match(spec)
  local name = spec.name or "?"
  if type(spec.match) ~= "table" then return end
  for k, v in pairs(spec.match) do
    if match_keys_with_regex[k] and type(v) == "string" then
      check_balanced(v, name, k)
    end
  end
end

M.Rule = {}

function M.Rule.window(spec)
  validate_match(spec)
  hl.window_rule(spec)
end

function M.Rule.layer(spec)
  hl.layer_rule(spec)
end

function M.Rule.workspace(spec)
  hl.workspace_rule(spec)
end

function M.Rule.float(spec)
  local match = {}
  if spec.class then match.class = spec.class end
  if spec.title then match.title = spec.title end
  M.Rule.window({
    name = spec.name or ("float-" .. (spec.class or spec.title or "?"):gsub("%W", "_")),
    match = match,
    float = true,
  })
end

M.Bind = {}

-- Lua dispatchers hide descriptions from hyprctl; Burl reads this registry.
local registry = {}

local function record(key, desc, group)
  if not desc then return end
  registry[#registry + 1] = { key = key, desc = desc, group = group or "" }
end

local function json_escape(s)
  return (s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    return string.format("\\u%04x", c:byte())
  end))
end

function M.Bind.dump(path)
  local f = io.open(path, "w")
  if not f then
    warn("cannot write keybind dump to %s", path)
    return
  end
  local parts = {}
  for i, b in ipairs(registry) do
    parts[i] = string.format('{"key":"%s","desc":"%s","group":"%s"}',
      json_escape(b.key), json_escape(b.desc), json_escape(b.group))
  end
  f:write("[", table.concat(parts, ","), "]")
  f:close()
end

function M.Bind.keys(list)
  for _, b in ipairs(list) do
    if b[1] then
      hl.bind(b[1], b[2], b[3])
      record(b[1], b.desc)
    end
  end
end

function M.Bind.prefixed(prefix, group)
  return function(list)
    for _, b in ipairs(list) do
      if b[1] then
        hl.bind(prefix .. " + " .. b[1], b[2], b[3])
        record(prefix .. " + " .. b[1], b.desc, group)
      end
    end
  end
end

function M.Bind.range(prefix, first, last, fn, desc)
  for i = first, last do
    local r = fn(i)
    hl.bind(prefix .. " + " .. tostring(i), r[1], r[2])
  end
  if desc then
    record(prefix .. " + " .. first .. ".." .. last, desc)
  end
end

M.Submap = {}

local function as_action(v)
  if type(v) == "string" then return hl.dsp.exec_cmd(v) end
  return v
end

function M.Submap.define(spec)
  local name = spec.name
  if spec.enter then
    hl.bind(spec.enter, hl.dsp.submap(name))
  end
  hl.define_submap(name, function()
    if spec.on_enter then spec.on_enter() end

    for _, b in ipairs(spec.binds or {}) do
      hl.bind(b[1], as_action(b[2]), b[3])
    end

    for _, s in ipairs(spec.shot or {}) do
      local opts = s[3] or {}
      opts.release = true
      hl.bind(s[1], as_action(s[2]), opts)
      hl.bind(s[1], hl.dsp.submap("reset"), { release = true })
    end

    local escape = spec.escape or { "escape", "BackSpace" }
    for _, k in ipairs(escape) do
      hl.bind(k, hl.dsp.submap("reset"))
    end
  end)
end

return M
