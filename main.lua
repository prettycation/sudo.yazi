local SEP = package.config:sub(1, 1)
local IS_WINDOWS = SEP == "\\"

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function first_line(s)
	if not s then
		return nil
	end
	s = trim(s)
	if s == "" then
		return nil
	end
	return s:match("([^\r\n]+)") or s
end

local function shell_capture(cmd)
	local f = io.popen(cmd, "r")
	if not f then
		return nil
	end
	local result = f:read("*a")
	f:close()
	return result
end

local function command_path(cmd)
	local probe
	if IS_WINDOWS then
		probe = "where.exe " .. cmd .. " 2>nul"
	else
		probe = "command -v " .. cmd .. " 2>/dev/null"
	end
	return first_line(shell_capture(probe))
end

local function path_join(...)
	local parts = { ... }
	local out = nil

	for _, part in ipairs(parts) do
		if part and part ~= "" then
			part = tostring(part)
			if not out then
				out = part
			else
				local left = out:gsub("[/\\\\]+$", "")
				local right = part:gsub("^[/\\\\]+", "")
				out = left .. SEP .. right
			end
		end
	end

	return out
end

local function config_home()
	local env = os.getenv("YAZI_CONFIG_HOME")
	if env and env ~= "" then
		return env
	end

	if IS_WINDOWS then
		local appdata = os.getenv("APPDATA")
		if appdata and appdata ~= "" then
			return path_join(appdata, "yazi", "config")
		end

		local userprofile = os.getenv("USERPROFILE")
		if userprofile and userprofile ~= "" then
			return path_join(userprofile, "AppData", "Roaming", "yazi", "config")
		end
	end

	local home = os.getenv("HOME") or os.getenv("USERPROFILE")
	if home and home ~= "" then
		return path_join(home, ".config", "yazi")
	end

	return nil
end

local CONFIG_HOME = config_home()
local PLUGIN_DIR = CONFIG_HOME and path_join(CONFIG_HOME, "plugins", "sudo.yazi") or nil

local interpreter = nil
local script = nil

local function set_interpreter(argv, script_name)
	interpreter = argv
	script = PLUGIN_DIR and path_join(PLUGIN_DIR, "assets", script_name) or nil
end

if command_path("ruby") then
	set_interpreter({ command_path("ruby") }, "fs.rb")
elseif command_path("python3") then
	set_interpreter({ command_path("python3") }, "fs.py")
elseif command_path("python") then
	set_interpreter({ command_path("python") }, "fs.py")
elseif IS_WINDOWS and command_path("py") then
	set_interpreter({ command_path("py"), "-3" }, "fs.py")
end

function string:ends_with(suffix)
	return suffix == "" or self:sub(-#suffix) == suffix
end

function string:ends_with_dir_sep()
	local last = self:sub(-1)
	return last == "/" or last == "\\"
end

function string:is_path()
	local i = self:find(IS_WINDOWS and "[/\\\\]" or "/")
	return self == "." or self == ".." or (i and i ~= #self)
end

function string:file_name()
	local file_name = self:match("^.*[/\\\\](.*)$")
	return file_name or self
end

local function sibling_path(path, new_name)
	local dir = path:match("^(.*)[/\\\\][^/\\\\]+$")
	if dir and dir ~= "" then
		return path_join(dir, new_name)
	end
	return new_name
end

local function list_map(self, f)
	local i = nil
	return function()
		local v
		i, v = next(self, i)
		if v then
			return f(v)
		end
		return nil
	end
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

local function shell_join(args)
	local parts = {}
	for _, arg in ipairs(args) do
		table.insert(parts, ya.quote(tostring(arg)))
	end
	return table.concat(parts, " ")
end

local function execute(command)
	ya.emit("shell", {
		shell_join(command),
		block = true,
		confirm = true,
	})
end

local function sudo_cmd()
	if IS_WINDOWS then
		local gsudo = command_path("gsudo") or command_path("sudo")
		if gsudo then
			return { gsudo, "--copyEV" }
		end
		return nil
	end

	local sudo = command_path("sudo")
	if sudo then
		return { sudo, "-E", "-k", "--" }
	end

	return nil
end

local function require_sudo_cmd()
	local args = sudo_cmd()
	if args then
		return args
	end

	if IS_WINDOWS then
		ya.err("sudo.yazi: gsudo is not installed or not in PATH.")
	else
		ya.err("sudo.yazi: sudo is not installed or not in PATH.")
	end
	return nil
end

local function split_words(s)
	local result = {}
	if not s or s == "" then
		return result
	end

	local token = ""
	local quote = nil
	local i = 1

	while i <= #s do
		local ch = s:sub(i, i)

		if quote then
			if ch == quote then
				quote = nil
			else
				token = token .. ch
			end
		else
			if ch == "'" or ch == '"' then
				quote = ch
			elseif ch:match("%s") then
				if token ~= "" then
					table.insert(result, token)
					token = ""
				end
			else
				token = token .. ch
			end
		end

		i = i + 1
	end

	if token ~= "" then
		table.insert(result, token)
	end

	return result
end

local function ps_quote(s)
	return "'" .. tostring(s):gsub("'", "''") .. "'"
end

local function powershell_exe()
	return command_path("powershell") or command_path("pwsh") or "powershell.exe"
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
	elseif cmd == "chmod" then
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
	elseif cmd == "open" and #cx.active.selected == 0 then
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

local function sudo_paste(value)
	local args = require_sudo_cmd()
	if not args then
		return
	end

	extend_list(args, interpreter)
	table.insert(args, script)

	if value.is_cut then
		table.insert(args, "mv")
	else
		table.insert(args, "cp")
	end

	if value.force then
		table.insert(args, "--force")
	end

	extend_iter(args, list_map(value.yanked, tostring))
	execute(args)
end

local function sudo_link(value)
	local args = require_sudo_cmd()
	if not args then
		return
	end

	extend_list(args, interpreter)
	table.insert(args, script)
	table.insert(args, "ln")

	if value.relative then
		table.insert(args, "--relative")
	end

	extend_iter(args, list_map(value.yanked, tostring))
	execute(args)
end

local function sudo_hardlink(value)
	local args = require_sudo_cmd()
	if not args then
		return
	end

	extend_list(args, interpreter)
	extend_list(args, { script, "hardlink" })
	extend_iter(args, list_map(value.yanked, tostring))
	execute(args)
end

local function sudo_create()
	local name, event = ya.input({
		title = "sudo create:",
		pos = { "top-center", y = 2, w = 40 },
	})

	if event ~= 1 or name:is_path() then
		return
	end

	local args = require_sudo_cmd()
	if not args then
		return
	end

	if IS_WINDOWS then
		local ps = powershell_exe()
		local ps_cmd

		if name:ends_with_dir_sep() then
			local dir = name:gsub("[/\\\\]+$", "")
			ps_cmd = "$ErrorActionPreference='Stop'; New-Item -ItemType Directory -Path "
				.. ps_quote(dir)
				.. " -Force | Out-Null"
		else
			ps_cmd = "$ErrorActionPreference='Stop'; if (-not (Test-Path -LiteralPath "
				.. ps_quote(name)
				.. ")) { New-Item -ItemType File -Path "
				.. ps_quote(name)
				.. " | Out-Null } else { (Get-Item -LiteralPath "
				.. ps_quote(name)
				.. ").LastWriteTime = Get-Date }"
		end

		extend_list(args, { ps, "-NoProfile", "-Command", ps_cmd })
	else
		if name:ends_with_dir_sep() then
			extend_list(args, { "mkdir", "-p", name })
		else
			extend_list(args, { "touch", name })
		end
	end

	execute(args)
end

local function sudo_rename(value)
	local new_name, event = ya.input({
		title = "sudo rename:",
		pos = { "top-center", y = 2, w = 40 },
		value = value.hovered:file_name(),
	})

	if event ~= 1 or new_name:is_path() then
		return
	end

	local args = require_sudo_cmd()
	if not args then
		return
	end

	local dest = sibling_path(value.hovered, new_name)

	if IS_WINDOWS then
		local ps = powershell_exe()
		local ps_cmd = "$ErrorActionPreference='Stop'; Move-Item -LiteralPath "
			.. ps_quote(value.hovered)
			.. " -Destination "
			.. ps_quote(dest)
		extend_list(args, { ps, "-NoProfile", "-Command", ps_cmd })
	else
		extend_list(args, { "mv", value.hovered, dest })
	end

	execute(args)
end

local function sudo_open(value)
	local args = require_sudo_cmd()
	if not args then
		return
	end

	local editor = os.getenv("VISUAL") or os.getenv("EDITOR") or (IS_WINDOWS and "notepad.exe" or "vi")
	local editor_argv = split_words(editor)

	if #editor_argv == 0 then
		editor_argv = { IS_WINDOWS and "notepad.exe" or "vi" }
	end

	extend_list(args, editor_argv)
	table.insert(args, value.hovered)
	execute(args)
end

local function sudo_remove(value)
	local args = require_sudo_cmd()
	if not args then
		return
	end

	extend_list(args, interpreter)
	extend_list(args, { script, "rm" })

	if value.permanently then
		table.insert(args, "--permanent")
	end

	extend_iter(args, list_map(value.selected, tostring))
	execute(args)
end

local function sudo_chmod(value)
	if IS_WINDOWS then
		ya.err("sudo.yazi: chmod is not supported on Windows in this build.")
		return
	end

	local mode, event = ya.input({
		title = "sudo chmod:",
		pos = { "top-center", y = 2, w = 40 },
	})

	if event ~= 1 then
		return
	end

	local args = require_sudo_cmd()
	if not args then
		return
	end

	extend_list(args, { "chmod", mode })
	extend_iter(args, list_map(value.selected, tostring))
	execute(args)
end

return {
	entry = function(_, job)
		if not PLUGIN_DIR or not script then
			ya.err("sudo.yazi: could not locate plugin assets under YAZI_CONFIG_HOME/plugins/sudo.yazi.")
			return
		end

		if not interpreter then
			ya.err("sudo.yazi: neither ruby nor python is installed.")
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
		elseif state.kind == "chmod" then
			sudo_chmod(state.value)
		elseif state.kind == "open" then
			sudo_open(state.value)
		end
	end,
}
