-- rex-grab: pick a URL or file path from a Rex pane's output, or a file from
-- its git repo, in the command palette, then open, copy or insert it.
-- See README.md for setup and configuration.

local M = {}

local term = "com.superlogical.terminal"
local uname = rex.exec{ "uname" }
local darwin = uname and uname.ok and uname.stdout:match("^Darwin")
local OPEN = darwin and "open" or "xdg-open"
local COPY = darwin and { "pbcopy" }
  or os.getenv("WAYLAND_DISPLAY") and { "wl-copy" }
  or { "xclip", "-selection", "clipboard" }

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
  copy = COPY,
}

local function opens(path)
  local f = io.open(path, "r")
  if f then f:close() end
  return f ~= nil
end

-- A directory opens for reading too, but only a directory opens with a
-- trailing slash.
local function is_file(path)
  return opens(path) and not opens(path .. "/")
end

-- An absolute path without "." and ".." segments or doubled slashes, so one
-- file printed in several spellings is listed once.
local function clean(path)
  local segs = {}
  for seg in path:gmatch("[^/]+") do
    if seg == ".." then segs[#segs] = nil
    elseif seg ~= "." then segs[#segs + 1] = seg end
  end
  return "/" .. table.concat(segs, "/")
end

-- The pane's screen and scrollback as text. One reply holds at most 960 KiB,
-- oldest text first. When the pane has more, read its last 960 KiB instead:
-- the things worth grabbing are the recent ones. max_bytes counts
-- JSON-escaped bytes, so a read can stop short of the end; keep reading
-- until eof. A tail read starts partway through a line, so its first line is
-- dropped.
local function screen_text(block_id)
  local limit = 983040
  local screen = rex.block.call(term, "format",
    { block_id = block_id, trim = true, unwrap = true, max_bytes = limit })
  if screen == nil then return "" end
  if screen.id == nil then return screen.content end
  local parts, offset = {}, math.max(0, screen.total - limit)
  local tail = offset > 0
  repeat
    local r = rex.block.call(term, "blob_read",
      { block_id = block_id, id = screen.id, offset = offset, max_bytes = limit })
    if r == nil or r.data == "" then break end
    parts[#parts + 1] = r.data
    offset = offset + #r.data
  until r.eof
  local text = table.concat(parts)
  if tail then text = text:gsub("^[^\n]*\n", "") end
  return text
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
  -- A kind without find only lists repo files.
  local scan = {}
  for _, name in ipairs(order) do
    if kinds[name].find then scan[#scan + 1] = name end
  end

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
      local p = rex.block.call(term, "process", { block_id = ctx.block_id })
      local cwd = p and p.foreground and p.foreground.cwd or os.getenv("HOME")
      local g = rex.exec({ "git", "rev-parse", "--show-toplevel", "--show-prefix" }, { cwd = cwd })
      local root, prefix
      if g and g.ok then root, prefix = g.stdout:match("^([^\n]+)\n([^\n]*)") end
      -- git resolves symlinks in the root; spell cwd the same way, so a file
      -- found in the pane and the same file from ls-files have one path.
      if root then cwd = (root .. "/" .. prefix):gsub("/$", "") end

      local items, found, seen = {}, {}, {}
      local function add(target, name, title, icon, subtitle)
        if seen[target] or #items >= 2000 then return end
        seen[target] = true
        found[target] = name
        items[#items + 1] = { id = target, title = title, subtitle = subtitle, icon = icon, detail = name }
      end
      local function add_file(abs, name, icon)
        local base = root and abs:sub(1, #root + 1) == root .. "/" and root .. "/" or ""
        -- The palette cuts a long title at its end, so the title is the file
        -- name and the directory goes on the second line.
        local rel = abs:sub(#base + 1)
        local dir, file = rel:match("^(.*)/([^/]+)$")
        add(abs, name, file or rel, icon, dir)
      end

      local lines = {}
      for line in screen_text(ctx.block_id):gmatch("[^\n]+") do
        lines[#lines + 1] = line
      end
      for i = #lines, 1, -1 do
        local line = lines[i]
        for _, name in ipairs(scan) do
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
                c = clean(c)
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
            local r = rex.exec({ "git", "ls-files", "-z", "--", k.repo }, { cwd = root })
            for rel in ((r and r.ok and r.stdout) or ""):gmatch("[^%z]+") do
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
        -- A path a shell would split or expand is single-quoted.
        if kinds[found[target]].file and text:find("[^%w%._%-/~+,:@=]") then
          text = "'" .. text:gsub("'", "'\\''") .. "'"
        end
        rex.block.call(term, "write", { block_id = ctx.block_id, data = text })
      elseif verb == "copy" then
        -- Output isn't captured: xclip and wl-copy stay running to serve the
        -- clipboard, and would hold the pipes open.
        local r, err = rex.exec(copy,
          { stdin = target, env = { PATH = path }, stdout = false, stderr = false })
        if r == nil or not r.ok then
          error("copy: " .. (err or copy[1] .. " exited with " .. r.code), 0)
        end
      elseif verb == "open" then
        local open = kinds[found[target]].open
        if open == nil then error("rex_grab: kind " .. found[target] .. " has no open command", 0) end
        if type(open) == "function" then return open(target, ctx) end
        local argv = fill(open, target)
        local h, err = rex.exec.start(argv,
          { env = { PATH = path }, detach = true, stdout = false, stderr = false })
        if h == nil then error(argv[1] .. ": " .. err, 0) end
      end
    end,
  }
end

return M
