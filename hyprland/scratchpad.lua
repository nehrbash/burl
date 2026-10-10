local M = {}

function M.new(config)
  local name = assert(config.workspace, "Scratchpad workspace is required")
  local command = assert(config.command, "Scratchpad command is required")
  local delay = config.delay or 300

  local function toggle()
    hl.dispatch(hl.dsp.workspace.toggle_special(name))
  end

  return {
    toggle = function()
      local workspace = hl.get_workspace("special:" .. name)
      local windows = workspace and hl.get_workspace_windows(workspace) or {}
      if #windows == 0 then
        hl.exec_cmd(command)
        -- Window rules need time to route the new window before revealing it.
        hl.timer(toggle, { timeout = delay, type = "oneshot" })
      else
        toggle()
      end
    end,
  }
end

return M
