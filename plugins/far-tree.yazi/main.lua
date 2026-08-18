--- @since 26.5.6
-- far-tree.yazi -- FAR Manager's Alt+F10 "find folder" dialog.
--
-- yazi has no tree panel and no core support for one (sxyazi/yazi#3070 is
-- still open), and a real tree panel means reimplementing the file list.
-- What FAR users reach for Alt+F10 to do, though, is "show me the folders
-- under here and take me to one" -- which is a directory list in a fuzzy
-- picker. That is what this does.
--
--   plugin far-tree          folders under the current directory
--   plugin far-tree home     folders under $HOME
--   plugin far-tree root     folders under /
--
-- Needs `fzf`; uses `fd` when present and falls back to `find`.

local M = {}

local TAG = "far-tree: "
local function log(msg)
	ya.err(TAG .. tostring(msg))
end

local cwd = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

local function build(root)
	-- `fd` is much faster and honours .gitignore-style excludes; `find` is
	-- there so the plugin still works on a bare system.
	return string.format(
		"if command -v fd >/dev/null 2>&1; then "
			.. "fd --type d --hidden --follow --exclude .git --exclude node_modules . %s; "
			.. "else find %s -type d -not -path '*/.git/*' 2>/dev/null; fi "
			.. "| fzf --prompt='Folder> ' --reverse --height=100%% --header=%s",
		string.format("%q", root),
		string.format("%q", root),
		string.format("%q", "Alt+F10  " .. root)
	)
end

function M:entry(job)
	local scope = job and job.args and job.args[1]
	local root
	if scope == "home" then
		root = os.getenv("HOME") or "/"
	elseif scope == "root" then
		root = "/"
	else
		root = cwd()
	end
	log("entry fired, root=" .. root)

	local permit = (ui.hide or ya.hide)()

	local child, err = Command("sh")
		:arg({ "-c", build(root) })
		:stdin(Command.INHERIT)
		:stdout(Command.PIPED)
		:spawn()

	if not child then
		permit:drop()
		log("failed to start picker: " .. tostring(err))
		return ya.notify {
			title = "far-tree",
			content = "Failed to start the picker: " .. tostring(err),
			timeout = 5,
			level = "error",
		}
	end

	local output, oerr = child:wait_with_output()
	permit:drop()

	if not output then
		log("picker failed: " .. tostring(oerr))
		return ya.notify {
			title = "far-tree",
			content = "Picker failed: " .. tostring(oerr),
			timeout = 5,
			level = "error",
		}
	end
	-- 130 = cancelled with Esc/Ctrl-C, which is not an error.
	if not output.status.success and output.status.code ~= 130 then
		log("picker exited with code " .. tostring(output.status.code))
		return
	end

	local line = output.stdout and output.stdout:match("[^\r\n]+")
	if not line then
		log("no selection (cancelled)")
		return
	end

	local url = Url(line)
	if not url.is_absolute then
		url = Url(root):join(line)
	end
	log("cd -> " .. tostring(url))
	ya.emit("cd", { url, raw = true })
end

return M
