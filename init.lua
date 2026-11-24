-- rex-grab: pick a URL or file path from a Rex pane's output, or a file from
-- its git repo, in the command palette, then open, copy or insert it.
-- See README.md for setup and configuration.

local M = {}

local term = "com.superlogical.terminal"
local uname = rex.exec{ "uname" }
local OPEN = uname and uname.ok and uname.stdout:match("^Darwin") and "open" or "xdg-open"

M.defaults = {
  kinds = {
    url = {
      find = "https?://[%w%-%._~:/%?#%[%]@!%$&%*%+,;=%%]+",
      icon = "globe",
      open = { OPEN, "{}" },
    },
    markdown = {
      find = "[%w%._%-/~]+%.md",
      file = true,
      repo = "*.md",
      icon = "document",
      open = { OPEN, "{}" },
    },
  },
  copy = { "pbcopy" },
}

local function is_file(path)
  local f = io.open(path, "r")
  if f == nil then return false end
  local _, err = f:read(0) -- a directory opens, then fails to read
  f:close()
  return err == nil
end

-- The pane's screen and scrollback as text. One reply holds at most 960 KiB,
-- oldest text first. When the pane has more, read its last 960 KiB instead:
-- the things worth grabbing are the recent ones. max_bytes counts
-- JSON-escaped bytes, so a read can stop short of the end; keep reading
-- until eof.
local function screen_text(block_id)
  local limit = 983040
  local screen = rex.block.call(term, "format",
    { block_id = block_id, trim = true, unwrap = true, max_bytes = limit })
  if screen == nil then return "" end
  if screen.id == nil then return screen.content end
  local parts, offset = {}, math.max(0, screen.total - limit)
  repeat
    local r = rex.block.call(term, "blob_read",
      { block_id = block_id, id = screen.id, offset = offset, max_bytes = limit })
    if r == nil or r.data == "" then break end
    parts[#parts + 1] = r.data
    offset = offset + #r.data
  until r.eof
  return table.concat(parts)
end

-- argv with every "{}" replaced by target.
local function fill(argv, target)
  local out = {}
  for i, a in ipairs(argv) do out[i] = (a:gsub("{}", function() return target end)) end
  return out
end

function M.setup(opts)
  opts = opts or {}

  -- A kind given in opts is merged over the default of the same name, field
  -- by field, so { markdown = { open = … } } changes only the opener; false
  -- drops the kind.
  local kinds = {}
  for name, k in pairs(M.defaults.kinds) do kinds[name] = k end
  for name, k in pairs(opts.kinds or {}) do
    if k == false then
      kinds[name] = nil
    else
      local merged = {}
      for f, v in pairs(kinds[name] or {}) do merged[f] = v end
      for f, v in pairs(k) do merged[f] = v end
      kinds[name] = merged
    end
  end
  -- Kinds that aren't files are matched first and cut out of the line, so a
  -- README.md inside a URL isn't also taken for a path.
  local order = {}
  for name in pairs(kinds) do order[#order + 1] = name end
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
      local p = rex.block.call(term, "process", { block_id = ctx.block_id })
      local cwd = p and p.foreground and p.foreground.cwd or os.getenv("HOME")
      local g = rex.exec({ "git", "rev-parse", "--show-toplevel" }, { cwd = cwd })
      local root = g and g.ok and g.stdout:gsub("%s+$", "") or nil

      local items, found, seen = {}, {}, {}
      local function add(target, name, title, icon)
        if seen[target] or #items >= 2000 then return end
        seen[target] = true
        found[target] = name
        items[#items + 1] = { id = target, title = title, icon = icon, detail = name }
      end
      local function add_file(abs, name, icon)
        local base = root and abs:sub(1, #root + 1) == root .. "/" and root .. "/" or ""
        add(abs, name, abs:sub(#base + 1), icon)
      end

      local lines = {}
      for line in screen_text(ctx.block_id):gmatch("[^\n]+") do
        lines[#lines + 1] = line
      end
      for i = #lines, 1, -1 do
        local line = lines[i]
        for _, name in ipairs(order) do
          local k = kinds[name]
          for m in line:gmatch(k.find) do
            if not k.file then
              m = m:gsub("[%.,;:!%?]+$", "")
              add(m, name, m, k.icon or "link")
            else
              local candidates = m:sub(1, 1) == "/" and { m }
                or m:sub(1, 2) == "~/" and { os.getenv("HOME") .. m:sub(2) }
                or { cwd .. "/" .. m, root and root .. "/" .. m }
              for _, c in ipairs(candidates) do
                if is_file(c) then add_file(c, name, "star"); break end
              end
            end
          end
          if not k.file then line = line:gsub(k.find, "") end
        end
      end

      if root then
        for _, name in ipairs(order) do
          local k = kinds[name]
          if k.repo then
            local r = rex.exec({ "git", "ls-files", "--", k.repo }, { cwd = root })
            for rel in ((r and r.ok and r.stdout) or ""):gmatch("[^\n]+") do
              add_file(root .. "/" .. rel, name, k.icon or "document")
            end
          end
        end
      end

      local target = rex.ui.pick{ title = "Grab (" .. verb .. ")",
        placeholder = "URL or file", items = items }
      if target == nil then return end

      if verb == "insert" then
        -- Relative to the pane's cwd when inside it, as typed paths would be.
        local text = target:sub(1, #cwd + 1) == cwd .. "/" and target:sub(#cwd + 2) or target
        rex.block.call(term, "write", { block_id = ctx.block_id, data = text })
      elseif verb == "copy" then
        local r, err = rex.exec(copy, { stdin = target, env = { PATH = path } })
        if r == nil or not r.ok then error("copy: " .. (err or r.stderr), 0) end
      elseif verb == "open" then
        local open = kinds[found[target]].open
        if type(open) == "function" then return open(target, ctx) end
        local argv = fill(open, target)
        local h, err = rex.exec.start(argv,
          { env = { PATH = path }, detach = true, stdout = false, stderr = false })
        if h == nil then error(argv[1] .. ": " .. err, 0) end
      else
        error("rex_grab: unknown verb " .. verb .. " (open, copy or insert)", 0)
      end
    end,
  }
end

return M
