-- What each verb does with the picked target.

local M = {}

-- argv with every "{}" replaced by target.
local function fill(argv, target)
  local out = {}
  for i, a in ipairs(argv) do out[i] = (a:gsub("{}", function() return target end)) end
  return out
end

-- The text the insert verb types for target, found by kind.
function M.insert_text(target, cwd, kind)
  -- Relative to the pane's cwd when inside it, as typed paths would be.
  local text = target:sub(1, #cwd + 1) == cwd .. "/" and target:sub(#cwd + 2) or target
  -- A path a shell would split or expand is single-quoted.
  if kind.file and text:find("[^%w%._%-/~+,:@=]") then
    text = "'" .. text:gsub("'", "'\\''") .. "'"
  end
  return text
end

function M.copy(target, copy, path)
  -- Output isn't captured: xclip and wl-copy stay running to serve the
  -- clipboard, and would hold the pipes open.
  local r, err = rex.exec(copy,
    { stdin = target, env = { PATH = path }, stdout = false, stderr = false })
  if r == nil or not r.ok then
    error("copy: " .. (err or copy[1] .. " exited with " .. r.code), 0)
  end
end

function M.open(target, kind, name, ctx, path)
  local open = kind.open
  if open == nil then error("rex_grab: kind " .. name .. " has no open command", 0) end
  if type(open) == "function" then return open(target, ctx) end
  local argv = fill(open, target)
  local h, err = rex.exec.start(argv,
    { env = { PATH = path }, detach = true, stdout = false, stderr = false })
  if h == nil then error(argv[1] .. ": " .. err, 0) end
end

return M
