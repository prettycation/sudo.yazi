# sudo.yazi

Forked from [JohWQ/sudo.yazi](https://github.com/JohWQ/sudo.yazi), which is a fork of [iandol/sudo.yazi](https://github.com/iandol/sudo.yazi), originally based on [TD-Sky/sudo.yazi](https://github.com/TD-Sky/sudo.yazi).

Call elevated file operations from Yazi.

This fork keeps the original plugin workflow, but adds better Windows support:

- Windows uses `gsudo`
- plugin assets are resolved from `YAZI_CONFIG_HOME`
- path handling works with both `/` and `\`
- common operations like `create`, `rename`, and `open` work more naturally on Windows

It also uses Ruby or Python as the backend instead of NuShell.

## Installation

```sh
ya pkg add prettycation/sudo
```

## Requirements

### Linux / macOS

- `sudo`
- either [Ruby](https://www.ruby-lang.org/) or [Python](https://www.python.org/)

### Windows

- [`gsudo`](https://github.com/gerardog/gsudo)
- either [Ruby](https://www.ruby-lang.org/) or [Python](https://www.python.org/)

## Functions

- copy files
- move files
- rename file
- remove files
- create absolute symbolic links
- create relative symbolic links
- create hard links
- create a new file
- create a new directory
- open file in `$EDITOR` / `$VISUAL`

### Platform notes

- On Windows, elevated operations use `gsudo`
- On Windows, `chmod` is not supported in this build
- The plugin resolves its backend scripts from `YAZI_CONFIG_HOME/plugins/sudo.yazi`
- If `YAZI_CONFIG_HOME` is not set, the default Yazi config directory is used

> You can use [conceal](https://github.com/tmke8/conceal) to browse and restore trashed files.

## Important behavior

### `paste`, `link`, and `hardlink` operate on yanked entries

`paste`, `link`, and `hardlink` do **not** use the hovered file directly.

They work on the current Yazi **yank buffer**, so you must first **yank** (or cut) one or more entries, then move to the destination directory, and then run the command.

That means the typical workflow is:

1. select or hover one or more files
2. yank them in Yazi
3. go to the destination directory
4. run one of:
   - `plugin sudo -- paste`
   - `plugin sudo -- paste --force`
   - `plugin sudo -- link`
   - `plugin sudo -- link --relative`
   - `plugin sudo -- hardlink`

### `rename`, `open`, and `remove` operate on the current file or selection

- `rename` uses the currently hovered item
- `open` uses the currently hovered item
- `remove` uses the current selection, or the hovered item if nothing is selected

## Usage

Below is an example keymap.

### Paste (copy / move yanked entries)

```toml
# sudo cp/mv using yanked entries
[[manager.keymap]]
on = ["R", "p", "p"]
run = "plugin sudo -- paste"
desc = "sudo paste yanked files"

# sudo cp/mv --force using yanked entries
[[manager.keymap]]
on = ["R", "P"]
run = "plugin sudo -- paste --force"
desc = "sudo paste yanked files (force)"
```

### Open / rename

```toml
# sudo open editor for hovered file
[[manager.keymap]]
on = ["R", "o"]
run = "plugin sudo -- open"
desc = "sudo open editor"

# sudo rename hovered file
[[manager.keymap]]
on = ["R", "r"]
run = "plugin sudo -- rename"
desc = "sudo rename"
```

### Links

```toml
# sudo ln -s using yanked entries
[[manager.keymap]]
on = ["R", "p", "l"]
run = "plugin sudo -- link"
desc = "sudo symlink yanked files"

# sudo ln -s --relative using yanked entries
[[manager.keymap]]
on = ["R", "p", "r"]
run = "plugin sudo -- link --relative"
desc = "sudo relative symlink yanked files"

# sudo hardlink using yanked entries
[[manager.keymap]]
on = ["R", "p", "L"]
run = "plugin sudo -- hardlink"
desc = "sudo hardlink yanked files"
```

### Create / remove

```toml
# sudo touch / mkdir
[[manager.keymap]]
on = ["R", "a"]
run = "plugin sudo -- create"
desc = "sudo create"

# sudo delete selected or hovered files
[[manager.keymap]]
on = ["R", "D"]
run = "plugin sudo -- remove --permanently"
desc = "sudo delete"
```

## Examples

### Copy protected files into the current directory

1. yank one or more files
2. change into the target directory
3. run:

```toml
plugin sudo -- paste
```

### Move protected files into the current directory

Cut the files in Yazi first, then run:

```toml
plugin sudo -- paste
```

If the yank buffer is in cut mode, the backend performs a move instead of a copy.

### Create a symbolic link in the current directory

1. yank the source file
2. change into the destination directory
3. run:

```toml
plugin sudo -- link
```

### Create a relative symbolic link in the current directory

1. yank the source file
2. change into the destination directory
3. run:

```toml
plugin sudo -- link --relative
```

### Create a hard link in the current directory

1. yank the source file
2. change into the destination directory
3. run:

```toml
plugin sudo -- hardlink
```

## Notes

- If `paste`, `link`, or `hardlink` seems to do nothing, make sure you have yanked something first
- `create` creates a directory if the entered name ends with `/` or `\`; otherwise it creates or touches a file
- `remove` without `--permanently` depends on the backend trash behavior
- `$VISUAL` is preferred over `$EDITOR` when opening a file

## License

MIT
