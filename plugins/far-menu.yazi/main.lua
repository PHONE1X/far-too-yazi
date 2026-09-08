--- @since 26.5.6
-- far-menu.yazi -- FAR Manager's menus for yazi.
--
--   F2  -> "user"    the user menu
--   F9  -> "main"    the menu bar (with "view", "sort", "panel" and
--                     "bookmarks" sub-menus)
--   F11 -> "plugins" plugin commands
--
-- Entries are plain data, so overriding them from init.lua needs no code:
--
--   require("far-menu"):setup {
--     user = {
--       { on = "b", desc = "Build the project", cmd = "shell",
--         args = { "cargo build", block = true } },
--     },
--   }
--
-- An entry runs one command (`cmd` + `args`), several in order (`cmds`),
-- or opens another list (`menu`).
--
-- NOTE ON CONTEXTS: setup() runs in the sync Lua state (init.lua), the
-- entry runs in the async one (ya.which yields, so it cannot be sync).
-- The two states hold separate copies of this module, which is why the
-- menu table is read back through a ya.sync block instead of being used
-- directly -- otherwise the async side would only ever see DEFAULTS and
-- silently ignore the user's setup().

local M = {}

local TAG = "far-menu: "
local function log(msg)
	ya.err(TAG .. tostring(msg))
end

local DEFAULTS = {}

DEFAULTS.user = {
	{ on = "f", desc = "Bookmarked folders",          cmd = "plugin", args = { "far-bookmarks" } },
	{ on = "s", desc = "Send to phone (KDE Connect)", cmd = "plugin", args = { "kdeconnect", "send" } },
	{ on = "p", desc = "Browse phone (KDE Connect)",  cmd = "plugin", args = { "kdeconnect", "browse" } },
	{ on = "a", desc = "Archive selected files",      cmd = "plugin", args = { "compress" } },
	{ on = "x", desc = "Extract archive",             cmd = "shell",  args = { "ouch decompress %s", block = true } },
	{ on = "m", desc = "Drives / mount points",       cmd = "plugin", args = { "mount" } },
	{ on = "c", desc = "Attributes (chmod)",          cmd = "plugin", args = { "chmod" } },
	{ on = "b", desc = "Recycle bin",                 cmd = "plugin", args = { "recycle-bin" } },
	{ on = "u", desc = "Undo the last delete",        cmd = "plugin", args = { "restore" } },
	{ on = "t", desc = "Shell in this directory",     cmd = "shell",  args = { "$SHELL", block = true } },
	{ on = "y", desc = "Copy the full path",          cmd = "copy",   args = { "path" } },
	{ on = "e", desc = "Go to ~/.config/yazi",        cmd = "cd",     args = { "~/.config/yazi" } },
}

DEFAULTS.main = {
	{ on = "v", desc = "View mode",              menu = "view" },
	{ on = "s", desc = "Sort by",                menu = "sort" },
	{ on = "p", desc = "Panels",                 menu = "panel" },
	{ on = "h", desc = "Show / hide hidden files", cmd = "hidden", args = { "toggle" } },
	{ on = "f", desc = "Filter the panel",       cmd = "filter", args = { smart = true } },
	{ on = "b", desc = "Bookmarked folders",     menu = "bookmarks" },
	{ on = "w", desc = "Task manager",           cmd = "tasks:show" },
	{ on = "k", desc = "Keyboard help",          cmd = "help" },
	{ on = "u", desc = "User menu",              menu = "user" },
	{ on = "g", desc = "Plugin commands",        menu = "plugins" },
	{ on = "m", desc = "Switch to the vim keymap", cmd = "plugin", args = { "far-mode", "to_vim" } },
}

DEFAULTS.view = {
	{ on = "n", desc = "Names only",   cmd = "linemode", args = { "none" } },
	{ on = "s", desc = "Size",         cmd = "linemode", args = { "size" } },
	{ on = "m", desc = "Modified time", cmd = "linemode", args = { "mtime" } },
	{ on = "b", desc = "Created time", cmd = "linemode", args = { "btime" } },
	{ on = "p", desc = "Permissions",  cmd = "linemode", args = { "permissions" } },
	{ on = "o", desc = "Owner",        cmd = "linemode", args = { "owner" } },
}

DEFAULTS.sort = {
	{ on = "n", desc = "Name",          cmd = "sort", args = { "alphabetical", reverse = false } },
	{ on = "N", desc = "Name (desc)",   cmd = "sort", args = { "alphabetical", reverse = true } },
	{ on = "e", desc = "Extension",     cmd = "sort", args = { "extension", reverse = false } },
	{ on = "E", desc = "Extension (desc)", cmd = "sort", args = { "extension", reverse = true } },
	{ on = "m", desc = "Modified time", cmds = { { "sort", { "mtime", reverse = false } }, { "linemode", { "mtime" } } } },
	{ on = "M", desc = "Modified time (desc)", cmds = { { "sort", { "mtime", reverse = true } }, { "linemode", { "mtime" } } } },
	{ on = "s", desc = "Size",          cmds = { { "sort", { "size", reverse = false } }, { "linemode", { "size" } } } },
	{ on = "S", desc = "Size (desc)",   cmds = { { "sort", { "size", reverse = true } }, { "linemode", { "size" } } } },
	{ on = "b", desc = "Created time",  cmds = { { "sort", { "btime", reverse = false } }, { "linemode", { "btime" } } } },
	{ on = "t", desc = "Natural",       cmd = "sort", args = { "natural", reverse = false } },
	{ on = "r", desc = "Random",        cmd = "sort", args = { "random", reverse = false } },
}

DEFAULTS.panel = {
	{ on = "t", desc = "Show / hide the second pane", cmd = "plugin", args = { "split-tabs", "spl_toggle" } },
	{ on = "q", desc = "Quick view (preview pane)",   cmd = "plugin", args = { "far-mode", "far_preview" } },
	{ on = "s", desc = "Switch to the other pane",    cmd = "plugin", args = { "far-mode", "far_switch_pane" } },
	{ on = "w", desc = "Swap the panes",              cmd = "tab_swap", args = { 1 } },
	{ on = "n", desc = "New tab here",                cmd = "tab_create", args = { current = true } },
	{ on = "c", desc = "Close this tab",              cmd = "close" },
}

-- Every entry here is one of far-bookmarks' own commands. The pinned
-- folders themselves are NOT mirrored into this table -- they live in
-- bookmarks-data.lua and are read fresh each time, so a folder pinned a
-- second ago is reachable without touching this file.
DEFAULTS.bookmarks = {
	{ on = "j", desc = "Jump to a bookmark (one keypress)", cmd = "plugin", args = { "far-bookmarks", "jump" } },
	{ on = "l", desc = "Open the bookmark list",            cmd = "plugin", args = { "far-bookmarks" } },
	{ on = "a", desc = "Bookmark the current directory",    cmd = "plugin", args = { "far-bookmarks", "add" } },
	-- "add hovered" is ONE argument string, not two. yazi hands the plugin
	-- everything after the plugin name as a single argument and splits it
	-- itself; passing { "far-bookmarks", "add", "hovered" } silently drops
	-- "hovered" and quietly bookmarks the wrong folder.
	{ on = "h", desc = "Bookmark the hovered folder",       cmd = "plugin", args = { "far-bookmarks", "add hovered" } },
}

DEFAULTS.plugins = {
	{ on = "f", desc = "Jump to a file (fzf)",        cmd = "plugin", args = { "fzf" } },
	{ on = "z", desc = "Jump to a directory (zoxide)", cmd = "plugin", args = { "zoxide" } },
	{ on = "d", desc = "Bookmarked folders",          cmd = "plugin", args = { "far-bookmarks" } },
	{ on = "t", desc = "Find folder (tree)",          cmd = "plugin", args = { "far-tree" } },
	{ on = "a", desc = "Archive selected files",      cmd = "plugin", args = { "compress" } },
	{ on = "m", desc = "Drives / mount points",       cmd = "plugin", args = { "mount" } },
	{ on = "c", desc = "Attributes (chmod)",          cmd = "plugin", args = { "chmod" } },
	{ on = "k", desc = "Send to phone (KDE Connect)", cmd = "plugin", args = { "kdeconnect", "send" } },
	{ on = "b", desc = "Recycle bin",                 cmd = "plugin", args = { "recycle-bin" } },
	{ on = "u", desc = "Undo the last delete",        cmd = "plugin", args = { "restore" } },
	{ on = "p", desc = "Paste (conflict prompt)",     cmd = "plugin", args = { "merge-paste" } },
	{ on = "v", desc = "Switch to the vim keymap",    cmd = "plugin", args = { "far-mode", "to_vim" } },
}

local menus = DEFAULTS

function M:setup(opts)
	if type(opts) ~= "table" then
		return
	end
	local merged = {}
	for k, v in pairs(DEFAULTS) do
		merged[k] = v
	end
	for k, v in pairs(opts) do
		merged[k] = v
	end
	menus = merged
end

-- Runs in the sync state, where setup() has actually been called.
local get_menus = ya.sync(function()
	return menus
end)

local function run(item)
	if item.cmd then
		ya.emit(item.cmd, item.args or {})
	end
	for _, c in ipairs(item.cmds or {}) do
		ya.emit(c[1], c[2] or {})
	end
end

function M:entry(job)
	local all = get_menus() or DEFAULTS
	local name = (job and job.args and job.args[1]) or "user"
	log("entry fired, menu=" .. tostring(name))

	for _ = 1, 8 do -- bounded: a mis-typed `menu = ...` cannot loop forever
		local items = all[name]
		if not items then
			log("no such menu: " .. tostring(name))
			return ya.notify {
				title = "far-menu",
				content = "No such menu: " .. tostring(name),
				timeout = 5,
				level = "error",
			}
		end

		local cands = {}
		for i, it in ipairs(items) do
			cands[i] = { on = it.on, desc = it.desc }
		end

		local idx = ya.which { cands = cands }
		if not idx then
			log("cancelled at menu=" .. name)
			return -- cancelled
		end

		local item = items[idx]
		log("picked '" .. tostring(item.on) .. "' (" .. tostring(item.desc) .. ") in menu=" .. name)
		if not item.menu then
			return run(item)
		end
		name = item.menu
		log("descending into submenu=" .. name)
	end
end

return M
