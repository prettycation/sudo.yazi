# sudo.yazi

This is a Yazi plugin that allows you to run file operations with `sudo`.

## Implementations

This repository contains two implementations of the file operation logic:

1.  **Python:** A Python implementation, located in `assets/fs.py`.
2.  **Ruby:** A Ruby implementation, located in `assets/fs.rb`.

The main plugin logic is in `main.lua`. It will automatically detect if you have ruby or python installed and use the appropriate script.

## Lua Plugin (`main.lua`)

```lua
local function command_exists(cmd)
    local f = io.popen("command -v " .. cmd, "r")
    local result = f:read("*a")
    f:close()
    return result ~= ""
end

local interpreter
local script

if command_exists("ruby") then
    interpreter = "ruby"
    script = os.getenv("HOME") .. "/.config/yazi/plugins/sudo.yazi/assets/fs.rb"
elseif command_exists("python3") then
    interpreter = "python3"
    script = os.getenv("HOME") .. "/.config/yazi/plugins/sudo.yazi/assets/fs.py"
elseif command_exists("python") then
    interpreter = "python"
    script = os.getenv("HOME") .. "/.config/yazi/plugins/sudo.yazi/assets/fs.py"
end

function string:ends_with_char(suffix)
    return self:sub(-#suffix) == suffix
end

function string:is_path()
    local i = self:find("/")
    return self == "." or self == ".." or i and i ~= #self
end

local function list_map(self, f)
    local i = nil
    return function()
        local v
        i, v = next(self, i)
        if v then
            return f(v)
        else
            return nil
        end
    end
end

local get_state = ya.sync(function(_, cmd)
    if cmd == "paste" or cmd == "link" or cmd == "hardlink" then
        local yanked = {}
        for _, url in pairs(cx.yanked) do
            table.insert(yanked, tostring(url))
        end

        if #yanked == 0 then
            return {}
        end

        return {
            kind = cmd,
            value = {
                is_cut = cx.yanked.is_cut,
                yanked = yanked,
            },
        }
    elseif cmd == "create" then
        return { kind = cmd }
    elseif cmd == "remove" then
        local selected = {}

        if #cx.active.selected ~= 0 then
            for _, url in pairs(cx.active.selected) do
                table.insert(selected, tostring(url))
            end
        else
            table.insert(selected, tostring(cx.active.current.hovered.url))
        end

        return {
            kind = cmd,
            value = {
                selected = selected,
            },
        }
    elseif cmd == "rename" and #cx.active.selected == 0 then
        return {
            kind = cmd,
            value = {
                hovered = tostring(cx.active.current.hovered.url),
            },
        }
    else
        return {}
    end
end)

local function sudo_cmd()
    return { "sudo", "-k", "--" }
end

local function extend_list(self, list)
    for _, value in ipairs(list) do
        table.insert(self, value)
    end
end

local function extend_iter(self, iter)
    for item in iter do
        table.insert(self, item)
    end
end

local function execute(command)
    ya.emit("shell", {
        table.concat(command, " "),
        block = true,
        confirm = true,
    })
end

local function sudo_paste(value)
    local args = sudo_cmd()

    extend_list(args, { interpreter, script })
    if value.is_cut then
        table.insert(args, "mv")
    else
        table.insert(args, "cp")
    end
    if value.force then
        table.insert(args, "--force")
    end
    extend_iter(args, list_map(value.yanked, ya.quote))

    execute(args)
end

local function sudo_link(value)
    local args = sudo_cmd()

    extend_list(args, { interpreter, script, "ln" })
    if value.relative then
        table.insert(args, "--relative")
    end
    extend_iter(args, list_map(value.yanked, ya.quote))

    execute(args)
end

local function sudo_hardlink(value)
    local args = sudo_cmd()

    extend_list(args, { interpreter, script, "hardlink" })
    extend_iter(args, list_map(value.yanked, ya.quote))

    execute(args)
end

local function sudo_create()
    local name, event = ya.input({
        title = "sudo create:",
        position = { "top-center", y = 2, w = 40 },
    })

    -- Input and confirm
    if event == 1 and not name:is_path() then
        local args = sudo_cmd()

        if name:ends_with_char("/") then
            extend_list(args, { "mkdir", "-p" })
        else
            table.insert(args, "touch")
        end
        table.insert(args, ya.quote(name))

        execute(args)
    end
end

local function sudo_rename(value)
    local new_name, event = ya.input({
        title = "sudo rename:",
        position = { "top-center", y = 2, w = 40 },
    })

    -- Input and confirm
    if event == 1 and not new_name:is_path() then
        local args = sudo_cmd()
        extend_list(args, { "mv", ya.quote(value.hovered), ya.quote(new_name) })
        execute(args)
    end
end

local function sudo_remove(value)
    local args = sudo_cmd()

    extend_list(args, { interpreter, script, "rm" })
    if value.permanently then
        table.insert(args, "--permanent")
    end
    extend_iter(args, list_map(value.selected, ya.quote))

    execute(args)
end

return {
    entry = function(_, job)
        if not interpreter then
            ya.err("sudo.yazi: Neither ruby nor python is installed.")
            return
        end

        -- https://github.com/sxyazi/yazi/issues/1553#issuecomment-2309119135
        ya.emit("escape", { visual = true })

        local state = get_state(job.args[1])

        if state.kind == "paste" then
            state.value.force = job.args.force
            sudo_paste(state.value)
        elseif state.kind == "link" then
            state.value.relative = job.args.relative
            sudo_link(state.value)
        elseif state.kind == "hardlink" then
            sudo_hardlink(state.value)
        elseif state.kind == "create" then
            sudo_create()
        elseif state.kind == "remove" then
            state.value.permanently = job.args.permanently
            sudo_remove(state.value)
        elseif state.kind == "rename" then
            sudo_rename(state.value)
        end
    end,
}
```

## Python Implementation (`assets/fs.py`)

```python
#!/usr/bin/env python3

import os
import sys
import shutil
import argparse

def legit_name(path):
    if not os.path.exists(path):
        return path
    name, ext = os.path.splitext(path)
    i = 1
    while True:
        new_name = f"{name}_{i}{ext}"
        if not os.path.exists(new_name):
            return new_name
        i += 1

def cp(paths, force=False):
    for src in paths:
        dest = os.path.basename(src)
        if not force:
            dest = legit_name(dest)
        if os.path.isdir(src):
            shutil.copytree(src, dest, dirs_exist_ok=True)
        else:
            shutil.copy2(src, dest)
        print(f"Copied {src} to {dest}")

def mv(paths, force=False):
    for src in paths:
        dest = os.path.basename(src)
        if not force:
            dest = legit_name(dest)
        shutil.move(src, dest)
        print(f"Moved {src} to {dest}")

def ln(paths, relative=False):
    for src in paths:
        dest = legit_name(os.path.basename(src))
        if relative:
            os.symlink(os.path.relpath(src), dest)
        else:
            os.symlink(src, dest)
        print(f"Linked {src} to {dest}")

def hardlink(paths):
    for src in paths:
        dest = legit_name(os.path.basename(src))
        os.link(src, dest)
        print(f"Hardlinked {src} to {dest}")

def rm(paths, permanent=False):
    for path in paths:
        if permanent:
            if os.path.isdir(path):
                shutil.rmtree(path)
            else:
                os.remove(path)
            print(f"Permanently removed {path}")
        else:
            # A more robust solution would use a trash library
            print(f"Moved {path} to trash (simulation)")


def main():
    parser = argparse.ArgumentParser(description="Sudo file operations")
    subparsers = parser.add_subparsers(dest="command")

    cp_parser = subparsers.add_parser("cp")
    cp_parser.add_argument("paths", nargs="+")
    cp_parser.add_argument("--force", action="store_true")

    mv_parser = subparsers.add_parser("mv")
    mv_parser.add_argument("paths", nargs="+")
    mv_parser.add_argument("--force", action="store_true")

    ln_parser = subparsers.add_parser("ln")
    ln_parser.add_argument("paths", nargs="+")
    ln_parser.add_argument("--relative", action="store_true")

    hardlink_parser = subparsers.add_parser("hardlink")
    hardlink_parser.add_argument("paths", nargs="+")

    rm_parser = subparsers.add_parser("rm")
    rm_parser.add_argument("paths", nargs="+")
    rm_parser.add_argument("--permanent", action="store_true")

    args = parser.parse_args()

    if args.command == "cp":
        cp(args.paths, args.force)
    elif args.command == "mv":
        mv(args.paths, args.force)
    elif args.command == "ln":
        ln(args.paths, args.relative)
    elif args.command == "hardlink":
        hardlink(args.paths)
    elif args.command == "rm":
        rm(args.paths, args.permanent)

if __name__ == "__main__":
    main()
```

## Ruby Implementation (`assets/fs.rb`)

```ruby
#!/usr/bin/env ruby

require 'fileutils'
require 'optparse'

def legit_name(path)
  return path unless File.exist?(path)

  name = File.basename(path, ".*")
  ext = File.extname(path)
  i = 1
  loop do
    new_name = "#{name}_#{i}#{ext}"
    return new_name unless File.exist?(new_name)
    i += 1
  end
end

def cp(paths, force: false)
  paths.each do |src|
    dest = File.basename(src)
    dest = legit_name(dest) unless force
    if File.directory?(src)
      FileUtils.cp_r(src, dest, verbose: true)
    else
      FileUtils.cp(src, dest, verbose: true)
    end
  end
end

def mv(paths, force: false)
  paths.each do |src|
    dest = File.basename(src)
    dest = legit_name(dest) unless force
    FileUtils.mv(src, dest, verbose: true)
  end
end

def ln(paths, relative: false)
  paths.each do |src|
    dest = legit_name(File.basename(src))
    if relative
      FileUtils.ln_s(Pathname.new(src).relative_path_from(Pathname.new(Dir.pwd)), dest, verbose: true)
    else
      FileUtils.ln_s(src, dest, verbose: true)
    end
  end
end

def hardlink(paths)
  paths.each do |src|
    dest = legit_name(File.basename(src))
    FileUtils.ln(src, dest, verbose: true)
  end
end

def rm(paths, permanent: false)
  paths.each do |path|
    if permanent
      FileUtils.rm_r(path, verbose: true)
    else
      # A more robust solution would use a trash library
      puts "Moved #{path} to trash (simulation)"
    end
  end
end

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: fs.rb [command] [options]"

  opts.on("--force", "Force overwrite") do |f|
    options[:force] = f
  end
  opts.on("--relative", "Create relative symlink") do |r|
    options[:relative] = r
  end
  opts.on("--permanent", "Permanently delete") do |p|
    options[:permanent] = p
  end
end.parse!

command = ARGV.shift

case command
when "cp"
  cp(ARGV, force: options[:force])
when "mv"
  mv(ARGV, force: options[:force])
when "ln"
  ln(ARGV, relative: options[:relative])
when "hardlink"
  hardlink(ARGV)
when "rm"
  rm(ARGV, permanent: options[:permanent])
end
```