local M = {}

function M.new(options)
  local api = hl
  local name = assert(options.name, "Scratchpad name is required")
  local state = options.state or { current = 1, max = 1 }
  local animation = options.animation
  local restore_pending = false
  local controller = {}

  local function workspace_name(index)
    return index == 1 and name or (name .. tostring(index))
  end

  local function full_name(index)
    return "special:" .. workspace_name(index)
  end

  local function toggle(index)
    api.dispatch(api.dsp.workspace.toggle_special(workspace_name(index)))
  end

  local function animate(action)
    if not animation then action(); return end
    api.animation(animation.navigate)
    action()
    if restore_pending then return end
    restore_pending = true
    -- Hyprland animation styles apply globally, including other scratchpads.
    api.timer(function()
      api.animation(animation.restore)
      restore_pending = false
    end, { timeout = animation.timeout, type = "oneshot" })
  end

  function controller.toggle()
    toggle(state.current)
  end

  function controller.move_window_to_current()
    api.dispatch(api.dsp.window.move({ workspace = full_name(state.current) }))
  end

  function controller.nav(direction)
    local previous = state.current
    local target
    if direction > 0 and previous == state.max then
      state.max = state.max + 1
      target = state.max
    else
      target = ((previous - 1 + direction + state.max) % state.max) + 1
    end
    if target == previous then return end
    state.current = target
    animate(function()
      local workspace = api.get_workspace(full_name(previous))
      if workspace and workspace.visible then toggle(previous) end
      toggle(target)
    end)
  end

  return controller
end

return M
