local burl = dofile("hyprland/init.lua")
local applied, rules
hl = {
  config = function(config) applied = config end,
  layer_rule = function(rule) rules[#rules + 1] = rule end,
}

local path = os.tmpname()
os.remove(path)
local theme = burl.theme(path)
assert(theme.rgb("primary") == "rgb(c7ae7b)")
theme.apply()
assert(applied.general.col.active_border == "rgba(c7ae7be6)")
assert(applied.plugin == nil)

local function save(text)
  local file = assert(io.open(path, "w"))
  file:write(text)
  file:close()
end

save("$primary = aabbcc\n$outlineVariant = 123456\n$surface = not-a-colour\n")
theme = burl.theme(path)
assert(theme.rgb("primary") == "rgb(aabbcc)")
assert(theme.rgb("surface") == "rgb(111319)")
hl.plugin = { hyprbars = {} }
theme.apply({ general = { col = { active_border = "rgb(ffffff)" } } })
assert(applied.general.col.active_border == "rgb(ffffff)")
assert(applied.general.col.inactive_border == "rgba(123456aa)")
assert(applied.plugin.hyprbars.bar_color == "rgb(1b1e26)")
theme.apply()
assert(applied.general.col.active_border == "rgba(aabbcce6)")

save("$primary = 010203\n")
assert(burl.theme(path).rgba("primary", "aa") == "rgba(010203aa)")
assert(theme.rgb("primary") == "rgb(aabbcc)")
rules = {}
burl.layer_rules()
assert(#rules == 3)
for _, rule in ipairs(rules) do
  assert(rule.name:match("^burl%-"))
  assert(rule.match.namespace:match("^qs%-"))
end
os.remove(path)
print("PASS: Hyprland palette defaults, reload, overrides, plugin gating and shell rules")
