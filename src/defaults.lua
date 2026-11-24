-- The built-in kinds and clipboard command, chosen for the server's OS.

local uname = rex.exec{ "uname" }
local darwin = uname and uname.ok and uname.stdout:match("^Darwin")
local OPEN = darwin and "open" or "xdg-open"
local COPY = darwin and { "pbcopy" }
  or os.getenv("WAYLAND_DISPLAY") and { "wl-copy" }
  or { "xclip", "-selection", "clipboard" }

return {
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
