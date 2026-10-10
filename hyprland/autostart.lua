local M = {}

-- Hyprland owns SIGCHLD; gates must not run blocking child processes.
function M.has_default_route()
  local file = io.open("/proc/net/route", "r")
  if not file then return false end
  for line in file:lines() do
    local _, destination = line:match("^(%S+)%s+(%S+)")
    if destination == "00000000" then file:close(); return true end
  end
  file:close()
  return false
end

function M.setup(specs, gates)
  local api = hl
  local pending = {}
  gates = gates or { network = M.has_default_route }

  local function ready(needs)
    for _, name in ipairs(needs or {}) do
      if not (gates[name] and gates[name]()) then return false end
    end
    return true
  end

  local function try_launch(name, workspace)
    local spec = specs[name]
    if not spec or pending[name] then return end
    if not workspace or #api.get_workspace_windows(workspace) > 0 then return end
    if not ready(spec.needs) then
      pending[name] = true
      api.timer(function()
        pending[name] = false
        try_launch(name, api.get_workspace(name))
      end, { timeout = 1500, type = "oneshot" })
      return
    end
    pending[name] = true
    api.exec_cmd(spec.cmd)
    -- Window creation lags command dispatch.
    api.timer(function() pending[name] = false end,
              { timeout = 10000, type = "oneshot" })
  end

  api.on("workspace.active", function(workspace)
    if workspace then
      try_launch(workspace.name or tostring(workspace.id), workspace)
    end
  end)
end

return M
