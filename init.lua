-- rex-grab: pick a URL or file path from a Rex pane's output, or a file from
-- its git repo, in the command palette, then open, copy or insert it.
-- See README.md for setup and configuration.

-- The modules in src are required by this module's own name, so the plugin
-- works from a clone under any directory name.
local name = ...
local pane = require(name .. ".src.pane")
local collect = require(name .. ".src.collect")
local verbs = require(name .. ".src.verbs")

local M = {}

M.defaults = require(name .. ".src.defaults")

function M.setup(opts)
  opts = opts or {}

  -- A kind given in opts is merged over the default of the same name, field
  -- by field, so { markdown = { open = … } } changes only the opener; false
  -- drops the kind.
  local kinds = {}
  for kname, k in pairs(M.defaults.kinds) do kinds[kname] = k end
  for kname, k in pairs(opts.kinds or {}) do
    if k == false then
      kinds[kname] = nil
    else
      local merged = {}
      for f, v in pairs(kinds[kname] or {}) do merged[f] = v end
      for f, v in pairs(k) do merged[f] = v end
      kinds[kname] = merged
    end
  end
  -- Kinds that aren't files are matched first and cut out of the line, so a
  -- README.md inside a URL isn't also taken for a path.
  local order = {}
  for kname in pairs(kinds) do order[#order + 1] = kname end
  table.sort(order, function(a, b)
    local fa, fb = kinds[a].file and 1 or 0, kinds[b].file and 1 or 0
    if fa ~= fb then return fa < fb end
    return a < b
  end)

  local copy = opts.copy or M.defaults.copy
  -- The Rex server runs with a bare PATH; take the login shell's, as Rex
  -- does for its terminals.
  local path = opts.path
  if path == nil then
    local login = rex.exec{ os.getenv("SHELL") or "/bin/sh", "-lc", 'printf %s "$PATH"' }
    path = login and login.ok and login.stdout or nil
  end

  rex.action{
    name = "rex_grab",
    title = "Grab: URL or File…",
    keywords = "open copy insert url link file path markdown",
    args = { verb = "string?" },
    run = function(ctx, args)
      local verb = args.verb or "open"
      if verb ~= "open" and verb ~= "copy" and verb ~= "insert" then
        error("rex_grab: unknown verb " .. verb .. " (open, copy or insert)", 0)
      end
      local cwd, root = pane.dirs(ctx.block_id)
      local items, found = collect(pane.text(ctx.block_id), cwd, root, kinds, order)

      local target = rex.ui.pick{ title = "Grab (" .. verb .. ")",
        placeholder = "URL or file", items = items }
      if target == nil then return end

      local kname = found[target]
      if verb == "insert" then
        pane.write(ctx.block_id, verbs.insert_text(target, cwd, kinds[kname]))
      elseif verb == "copy" then
        verbs.copy(target, copy, path)
      elseif verb == "open" then
        return verbs.open(target, kinds[kname], kname, ctx, path)
      end
    end,
  }
end

return M
