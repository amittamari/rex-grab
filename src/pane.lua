-- What the plugin reads from a pane: its text and its directory.

local M = {}

local term = "com.superlogical.terminal"

-- The pane's screen and scrollback as text. One reply holds at most 960 KiB,
-- oldest text first. When the pane has more, read its last 960 KiB instead:
-- the things worth grabbing are the recent ones. max_bytes counts
-- JSON-escaped bytes, so a read can stop short of the end; keep reading
-- until eof. A tail read starts partway through a line, so its first line is
-- dropped.
function M.text(block_id)
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

-- The pane's directory, and the root of its git repo (nil outside one).
function M.dirs(block_id)
  local p = rex.block.call(term, "process", { block_id = block_id })
  local cwd = p and p.foreground and p.foreground.cwd or os.getenv("HOME")
  local g = rex.exec({ "git", "rev-parse", "--show-toplevel", "--show-prefix" }, { cwd = cwd })
  local root, prefix
  if g and g.ok then root, prefix = g.stdout:match("^([^\n]+)\n([^\n]*)") end
  -- git resolves symlinks in the root; spell cwd the same way, so a file
  -- found in the pane and the same file from ls-files have one path.
  if root then cwd = (root .. "/" .. prefix):gsub("/$", "") end
  return cwd, root
end

-- Types text into the pane.
function M.write(block_id, text)
  rex.block.call(term, "write", { block_id = block_id, data = text })
end

return M
