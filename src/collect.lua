-- Builds the palette's items: targets found in the pane's text, newest
-- first, then each kind's repo files.

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

-- Returns the items for rex.ui.pick, and a map from each item's target to
-- the name of the kind that found it. kinds are matched in the given order.
return function(text, cwd, root, kinds, order)
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
  for line in text:gmatch("[^\n]+") do
    lines[#lines + 1] = line
  end
  for i = #lines, 1, -1 do
    local line = lines[i]
    for _, name in ipairs(order) do
      local k = kinds[name]
      -- A kind without find only lists repo files.
      if k.find then
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

  return items, found
end
