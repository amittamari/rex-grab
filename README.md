# rex-grab

Pick a URL or file path from a [Rex](https://www.superlogical.com/rex) pane's
output, in Rex's own command palette, then open it, copy it, or type it into
the pane.

Say an agent in the focused pane just printed:

```
PR: https://github.com/acme/app/pull/12.
Wrote docs/plan.md, see [the spec](https://example.com/spec).
```

Press the key and the palette lists, newest first:

```
★ plan.md                           markdown
  docs
🌐 https://example.com/spec          url
🌐 https://github.com/acme/app/pull/12  url
📄 README.md                         markdown   ← every other .md in the pane's git repo
📄 setup.md                          markdown
  docs
```

A file shows its name first and its directory on a second line, so a long
path never hides the name.

Type to filter, Enter to act on the pick, Escape to cancel.

- **Searches the scrollback, not only the screen.** It reads the pane's last
  960 KiB of output, so a link that scrolled away an hour ago is still there.
- **Lists files that were never printed.** Each kind can add matching files
  from the pane's git repo (`git ls-files`).
- **Pure Lua, no dependencies.** It uses Rex's palette (`rex.ui.pick`), not
  fzf in a popup.
- **Configurable.** You choose what counts as a target and what opens it.

## Install

```sh
git clone https://github.com/amittamari/rex-grab ~/.config/rex/rex-grab
```

In `~/.config/rex/init.lua`:

```lua
require("rex-grab").setup()
rex.bind("alt+shift+m", "rex_grab", { verb = "open" })
rex.bind("alt+shift+y", "rex_grab", { verb = "copy" })
rex.bind("alt+shift+i", "rex_grab", { verb = "insert" })
```

Then `rex config reload`. The plugin binds no keys of its own; bind the verbs
you want. **Grab: URL or File…** is also in the command palette (it opens).

## Verbs

| Verb | What happens to the pick |
| --- | --- |
| `open` | Runs the kind's `open` command, in the background. |
| `copy` | Pipes it to the clipboard command (see `copy` below). URLs and absolute paths. |
| `insert` | Types it into the pane, relative to the pane's directory when it's inside it. A path with spaces or other shell characters is single-quoted. Handy for dropping a path into an agent's prompt. |

## Configuration

`setup` takes a table; every field is optional.

```lua
require("rex-grab").setup{
  kinds = {
    -- Change one field of a built-in kind: the rest stays.
    markdown = { open = { "gh", "markdown-preview", "{}" } },
    -- Add a kind.
    pdf = { find = "[%w%._%-/~]+%.pdf", file = true, open = { "open", "-a", "Preview", "{}" } },
    -- Drop a built-in kind.
    -- url = false,
  },
  copy = { "pbcopy" },  -- command that reads the text on stdin; the default
                        -- is pbcopy on macOS, wl-copy or xclip on Linux
  path = nil,           -- PATH for commands; defaults to your login shell's
}
```

A **kind** is one sort of target. Built in are `url` and `markdown`. Fields:

| Field | Meaning |
| --- | --- |
| `find` | Lua pattern that matches the target in the pane's text. Leave it out to only list `repo` files. |
| `file` | `true` if the match is a path that must exist. Relative paths are tried against the pane's directory, then its git root; `~/` is expanded. Kinds without `file` are matched first and cut out of the line, so a `README.md` inside a URL isn't also taken for a path. |
| `repo` | A `git ls-files` pattern such as `"*.md"`: also list these files from the pane's repo. |
| `icon` | A Rex palette icon: `globe`, `document`, `code`, `link`, … Files found in the pane's output always get `star`, so they stand out from `repo` files. |
| `open` | The command for the `open` verb, with `{}` replaced by the target (an absolute path for files). Or a function `open(target, ctx)`, e.g. to open it in a Rex split. A kind without `open` can still be copied and inserted. |

The defaults open both kinds with `open` on macOS, `xdg-open` elsewhere.

## Notes

- Tested with Rex 0.1.0-preview.21 on macOS. Rex is in beta, so its API may change.
- Linux is supported but untested: `open` uses `xdg-open`, and `copy` uses
  `wl-copy` when the Rex server has `WAYLAND_DISPLAY` set, `xclip` otherwise.
  Set `copy` if the server doesn't see your display variables.
- `open` and `copy` run on the machine the Rex server runs on, so on a
  remote host they act on that host, not on the machine you're sitting at.
- Rex runs commands with a bare `PATH`, so the plugin borrows your login
  shell's once per config load. Set `path` if that doesn't find your tools.
- A trailing `.`, `,`, `;`, `:`, `!` or `?` is dropped from URLs. A URL is
  cut at `(` or `)`, which keeps Markdown links clean but truncates URLs that
  contain parentheses.
- The palette shows at most 2,000 items.

## License

MIT
