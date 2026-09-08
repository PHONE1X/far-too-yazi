--- @since 26.5.6
-- far-bookmarks.yazi -- FAR Manager's folder shortcuts for yazi.
--
-- Pin the folders you keep coming back to, then reach any of them with one
-- keypress. FAR Manager calls these "folder shortcuts", Total Commander
-- calls them the "directory hotlist"; yazi ships neither. `zoxide` and
-- `fzf` are close cousins, but both guess from history -- this list holds
-- exactly what you put in it and nothing else.
--
--   plugin far-bookmarks              open the bookmark menu (add/jump/edit)
--   plugin far-bookmarks jump         one-keypress jump list (no popup)
--   plugin far-bookmarks add          bookmark the current directory
--   plugin far-bookmarks -- add hovered   bookmark the hovered folder
--   plugin far-bookmarks -- go w      jump to the bookmark keyed "w"
--
-- Note the `--` on the last two: yazi passes a bare word after the plugin
-- name straight through as the single argument, but a SECOND bare word is
-- dropped on the floor. `--` is what makes yazi split the rest into real
-- arguments. From Lua the same rule applies to the string you hand
-- ya.emit: { "far-bookmarks", "add hovered" }, not three separate strings.
--
-- Bookmarks live in $YAZI_CONFIG_HOME/bookmarks-data.lua (a plain Lua
-- table, so you can hand-edit or version it), and every bookmark carries a
-- one-character shortcut key. Adding a bookmark picks a free key for you;
-- change it later with `s` in the popup.
--
-- The very first run seeds that file with the gaming folders nobody enjoys
-- retyping -- the Steam library, the Proton prefixes, the PortProton
-- prefixes, the installed Proton builds -- but only the ones that actually
-- exist on this machine. It happens exactly once: after the file exists,
-- the list is yours, and emptying it does not bring the seed back.
--
-- NOTE ON `add`: it bookmarks the directory the panel is IN, never the one
-- the cursor happens to sit on -- "bookmark where I am" stays predictable
-- whatever the cursor is doing. Use `add hovered` (or `A` in the popup)
-- when you do want the folder under the cursor.

------------------------------------------------------------------ file i/o

local function config_dir()
	return os.getenv("YAZI_CONFIG_HOME") or (os.getenv("HOME") .. "/.config/yazi")
end

local function data_path()
	return config_dir() .. "/bookmarks-data.lua"
end

local function read_file(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local content = f:read("*a")
	f:close()
	return content
end

local function notify(level, s, ...)
	ya.notify {
		title = "Bookmarks",
		content = string.format(s, ...),
		level = level,
		timeout = level == "error" and 5 or 3,
	}
end

local function lua_quote(s)
	return string.format("%q", s)
end

-- The data file is plain Lua returning a table, same as openers-data.lua --
-- running it beats shipping a JSON parser, and it stays readable by hand.
local function load_bookmarks()
	local content = read_file(data_path())
	if not content then return {} end

	local chunk = load(content, "@" .. data_path())
	if not chunk then return {} end

	local ok, result = pcall(chunk)
	if not (ok and type(result) == "table") then return {} end

	-- Drop anything malformed rather than letting a hand-edit crash the
	-- popup later, when there is no good place left to report it.
	local out = {}
	for _, b in ipairs(result) do
		if type(b) == "table" and type(b.path) == "string" and b.path ~= "" then
			out[#out + 1] = {
				key = type(b.key) == "string" and b.key:sub(1, 1) or "",
				name = type(b.name) == "string" and b.name or b.path,
				path = b.path,
			}
		end
	end
	return out
end

local function serialize(list)
	local lines = {
		"-- far-bookmarks.yazi -- your pinned folders.",
		"-- Edited from the bookmark popup, but it is just a Lua table:",
		"-- hand-editing and version-controlling this file both work fine.",
		"return {",
	}
	for _, b in ipairs(list) do
		lines[#lines + 1] = string.format(
			"\t{ key = %s, name = %s, path = %s },",
			lua_quote(b.key or ""),
			lua_quote(b.name or b.path),
			lua_quote(b.path)
		)
	end
	lines[#lines + 1] = "}\n"
	return table.concat(lines, "\n")
end

local function save_bookmarks(list)
	local ok, err = fs.write(Url(data_path()), serialize(list))
	if not ok then
		notify("error", "Could not save the bookmarks: %s", tostring(err))
	end
	return ok
end

---------------------------------------------------------------- first run

-- Paths are given relative to $HOME and tried in order, because the same
-- folder sits somewhere different under a native Steam, a Flatpak Steam and
-- the old ~/.steam symlink layout. The first one that exists wins; an entry
-- that matches nothing is simply left out.
local SEED = {
	{
		key = "g",
		name = "Steam games",
		paths = {
			".local/share/Steam/steamapps/common",
			".steam/steam/steamapps/common",
			".var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common",
		},
	},
	{
		key = "p",
		name = "Proton prefixes",
		paths = {
			".local/share/Steam/steamapps/compatdata",
			".steam/steam/steamapps/compatdata",
			".var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/compatdata",
		},
	},
	{
		key = "o",
		name = "PortProton prefixes",
		paths = {
			"PortProton/data/prefixes",
			"Games/PortProton/data/prefixes",
			".var/app/ru.linux_gaming.PortProton/data/prefixes",
		},
	},
	{
		key = "b",
		name = "Proton builds",
		paths = {
			".local/share/Steam/compatibilitytools.d",
			".steam/root/compatibilitytools.d",
		},
	},
}

------------------------------------------------------------------- helpers

-- Keys the popup itself listens for. A bookmark may still be given one of
-- these by hand -- it simply won't be directly pressable inside the popup
-- (Enter on its row, or the `jump` list, still reach it).
local RESERVED = {
	q = true, j = true, k = true, a = true, A = true, r = true,
	s = true, d = true, x = true, t = true, J = true, K = true,
}

-- Digits first, so the first nine bookmarks get FAR's numbered shortcuts;
-- then the letters the popup does not already spend on its own actions.
local KEY_POOL = "123456789" .. "0" .. "bcefghilmnopuvwyz"

local function key_taken(list, key, except)
	for _, b in ipairs(list) do
		if b ~= except and b.key == key then return true end
	end
	return false
end

local function free_key(list)
	for i = 1, #KEY_POOL do
		local c = KEY_POOL:sub(i, i)
		if not key_taken(list, c) then return c end
	end
	return "" -- pool exhausted: the bookmark still works from its row
end

local function home()
	return os.getenv("HOME") or ""
end

-- "/home/void/WORKSPASE" -> "~/WORKSPASE", purely for display.
local function shorten(path)
	local h = home()
	if h ~= "" and path:sub(1, #h) == h then
		return "~" .. path:sub(#h + 1)
	end
	return path
end

local function basename(path)
	return path:match("([^/]+)/?$") or path
end

local function find_by_key(list, key)
	for _, b in ipairs(list) do
		if b.key == key then return b end
	end
end

local function index_of(list, bm)
	for i, b in ipairs(list) do
		if b.path == bm.path and b.name == bm.name then return i end
	end
end

------------------------------------------------------------------- actions

local cwd = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

local hovered_dir = ya.sync(function()
	local h = cx.active.current.hovered
	if h and h.cha and h.cha.is_dir then
		return tostring(h.url)
	end
	return nil
end)

-- A bookmarked folder can be renamed, unmounted or deleted behind our back.
-- Say so instead of emitting a `cd` that quietly does nothing.
local function jump(bm, new_tab)
	if not bm then return end

	local cha = fs.cha(Url(bm.path), true)
	if not cha or not cha.is_dir then
		return notify("error", "%s is gone: %s", bm.name, shorten(bm.path))
	end

	if new_tab then
		ya.emit("tab_create", { Url(bm.path), raw = true })
	else
		ya.emit("cd", { Url(bm.path), raw = true })
	end
end

-- Runs OUTSIDE the modal (openers.yazi hit this first): ya.input needs the
-- keyboard focus that the popup's own key loop would otherwise be holding.
local function add_path(path)
	if not path or path == "" then
		return notify("warn", "Nothing to bookmark here.")
	end

	local list = load_bookmarks()
	for _, b in ipairs(list) do
		if b.path == path then
			return notify("warn", "Already bookmarked as \"%s\".", b.name)
		end
	end

	local name, ev = ya.input {
		title = "Bookmark name:",
		value = basename(path),
		pos = { "top-center", y = 3, w = 50 },
	}
	if ev ~= 1 or not name or name == "" then return end

	local key = free_key(list)
	list[#list + 1] = { key = key, name = name, path = path }
	if save_bookmarks(list) then
		if key == "" then
			notify("info", "Bookmarked %s (no free shortcut key left).", name)
		else
			notify("info", "Bookmarked %s as \"%s\".", name, key)
		end
	end
end

local function rename(bm)
	if not bm then return end

	local name, ev = ya.input {
		title = "Rename the bookmark:",
		value = bm.name,
		pos = { "top-center", y = 3, w = 50 },
	}
	if ev ~= 1 or not name or name == "" then return end

	local list = load_bookmarks()
	local i = index_of(list, bm)
	if i then
		list[i].name = name
		save_bookmarks(list)
	end
end

local function set_key(bm)
	if not bm then return end

	local key, ev = ya.input {
		title = "Shortcut key (one character, empty to clear):",
		value = bm.key,
		pos = { "top-center", y = 3, w = 50 },
	}
	if ev ~= 1 or not key then return end
	key = key:sub(1, 1)

	local list = load_bookmarks()
	local i = index_of(list, bm)
	if not i then return end

	if key ~= "" and key_taken(list, key, list[i]) then
		return notify("error", "The key \"%s\" is already taken.", key)
	end

	list[i].key = key
	save_bookmarks(list)
end

local function delete(bm)
	if not bm then return end

	local list = load_bookmarks()
	local i = index_of(list, bm)
	if i then
		table.remove(list, i)
		save_bookmarks(list)
	end
end

local function reorder(bm, delta)
	if not bm then return 0 end

	local list = load_bookmarks()
	local i = index_of(list, bm)
	if not i then return 0 end

	local j = i + delta
	if j < 1 or j > #list then return 0 end

	list[i], list[j] = list[j], list[i]
	save_bookmarks(list)
	return delta
end

-- Writes the starter list, once, on the first run that finds no data file
-- at all. An empty-but-present file is a deliberate "I deleted them all"
-- and is left alone -- re-seeding over that would be the plugin arguing
-- with the user.
local function ensure_seeded()
	if read_file(data_path()) then return end

	local h = home()
	if h == "" then return end

	local list = {}
	for _, entry in ipairs(SEED) do
		for _, rel in ipairs(entry.paths) do
			local path = h .. "/" .. rel
			local cha = fs.cha(Url(path), true)
			if cha and cha.is_dir then
				list[#list + 1] = { key = entry.key, name = entry.name, path = path }
				break
			end
		end
	end

	save_bookmarks(list)
end

-- The one-keypress jump list: no modal, no cursor, just `ya.which`.
local function which_jump()
	local list = load_bookmarks()
	if #list == 0 then
		return notify("warn", "No bookmarks yet -- add one with the bookmark popup.")
	end

	local cands, mapped = {}, {}
	for _, b in ipairs(list) do
		if b.key ~= "" then
			cands[#cands + 1] = { on = b.key, desc = b.name .. "   " .. shorten(b.path) }
			mapped[#mapped + 1] = b
		end
	end
	if #cands == 0 then
		return notify("warn", "No bookmark has a shortcut key -- assign one with `s` in the popup.")
	end

	local idx = ya.which { cands = cands }
	if idx then jump(mapped[idx]) end
end

--------------------------------------------------------------- popup shell

local toggle_ui = ya.sync(function(self)
	if self.children then
		Modal:children_remove(self.children)
		self.children = nil
	else
		self.children = Modal:children_add(self, 10)
	end
	if ui.render then ui.render() else ya.render() end
end)

local set_rows = ya.sync(function(self, rows, cursor)
	self.rows = rows
	if cursor then
		self.cursor = ya.clamp(0, cursor, math.max(0, #rows - 1))
	else
		self.cursor = math.max(0, math.min(self.cursor or 0, math.max(0, #rows - 1)))
	end
	if ui.render then ui.render() else ya.render() end
end)

local active_row = ya.sync(function(self)
	return self.rows and self.rows[(self.cursor or 0) + 1]
end)

local cursor_pos = ya.sync(function(self) return self.cursor or 0 end)

local update_cursor = ya.sync(function(self, delta)
	if not self.rows or #self.rows == 0 then
		self.cursor = 0
	else
		self.cursor = ya.clamp(0, (self.cursor or 0) + delta, #self.rows - 1)
	end
	if ui.render then ui.render() else ya.render() end
end)

local ACTIONS = {
	{ on = "q", run = "quit" },
	{ on = "<Esc>", run = "quit" },
	{ on = "k", run = "up" },
	{ on = "j", run = "down" },
	{ on = "<Up>", run = "up" },
	{ on = "<Down>", run = "down" },
	{ on = "<Enter>", run = "open" },
	{ on = "t", run = "open_tab" },
	{ on = "a", run = "add" },
	{ on = "A", run = "add_hovered" },
	{ on = "r", run = "rename" },
	{ on = "s", run = "set_key" },
	{ on = "d", run = "delete" },
	{ on = "x", run = "delete" },
	{ on = "K", run = "move_up" },
	{ on = "J", run = "move_down" },
}

local M = {}

function M:new(area)
	self:layout(area)
	return self
end

function M:layout(area)
	local chunks = ui.Layout()
		:constraints({
			ui.Constraint.Percentage(15),
			ui.Constraint.Percentage(70),
			ui.Constraint.Percentage(15),
		})
		:split(area)

	chunks = ui.Layout()
		:direction(ui.Layout.HORIZONTAL)
		:constraints({
			ui.Constraint.Percentage(10),
			ui.Constraint.Percentage(80),
			ui.Constraint.Percentage(10),
		})
		:split(chunks[2])

	self._area = chunks[2]
end

-- One pass of: show the popup, let the user browse, and return as soon as
-- they ask for something that needs ya.input or ends the popup. ya.join
-- only returns once every joined coroutine has, so by the time this
-- returns nothing is still listening for keys and ya.input is safe.
function M:run_modal()
	-- Rows first, popup second: adding the modal renders it immediately, and
	-- with the rows still unset that first frame flashes the "No bookmarks
	-- yet" placeholder even when the list is full.
	local rows = load_bookmarks()
	set_rows(rows, cursor_pos())
	toggle_ui()

	local tx, rx = ya.chan("mpsc")
	local action, picked

	local function producer()
		while true do
			-- Bookmark keys are offered alongside the popup's own actions,
			-- so the key shown in the list is also the key that works here.
			-- Actions come first: a hand-assigned key that collides with one
			-- of them loses, rather than silently shadowing `d` or `q`.
			local cands, extra = {}, {}
			for _, c in ipairs(ACTIONS) do cands[#cands + 1] = c end
			for _, b in ipairs(rows) do
				if b.key ~= "" and not RESERVED[b.key] then
					cands[#cands + 1] = { on = b.key, desc = b.name }
					extra[#cands] = b
				end
			end

			local idx = ya.which { cands = cands, silent = true }
			if idx then
				local bm = extra[idx]
				if bm then
					tx:send("go:" .. bm.key)
					return
				end

				local run = cands[idx].run
				tx:send(run)
				if run ~= "up" and run ~= "down" and run ~= "move_up" and run ~= "move_down" then
					return
				end
			end
		end
	end

	local function consumer()
		while true do
			local run = rx:recv()
			if run == "up" then
				update_cursor(-1)
			elseif run == "down" then
				update_cursor(1)
			elseif run == "move_up" or run == "move_down" then
				local bm = active_row()
				local moved = reorder(bm, run == "move_up" and -1 or 1)
				if moved ~= 0 then
					rows = load_bookmarks()
					set_rows(rows, cursor_pos() + moved)
				end
			else
				action = run
				picked = active_row()
				return
			end
		end
	end

	ya.join(producer, consumer)
	toggle_ui()

	local key = action and action:match("^go:(.+)$")
	if key then
		return "open", find_by_key(rows, key)
	end
	return action, picked
end

function M:entry(job)
	ensure_seeded()

	local args = (job and job.args) or {}
	local act = args[1]

	-- `go:w` as well as `go w`: keymap entries and internal re-emits have
	-- historically disagreed about how multiple plugin args survive.
	local inline = type(act) == "string" and act:match("^go:(.+)$")
	if inline then
		return jump(find_by_key(load_bookmarks(), inline))
	end

	if act == "go" then
		local key = args[2]
		if not key or key == "" then
			return notify("error", "`go` needs a bookmark key, e.g. `plugin far-bookmarks go w`.")
		end
		local bm = find_by_key(load_bookmarks(), tostring(key):sub(1, 1))
		if not bm then
			return notify("error", "No bookmark is keyed \"%s\".", tostring(key))
		end
		return jump(bm)
	end

	if act == "add" then
		if args[2] == "hovered" then
			return add_path(hovered_dir() or cwd())
		end
		return add_path(cwd())
	end

	if act == "jump" then
		return which_jump()
	end

	while true do
		local action, bm = self:run_modal()
		if action == "open" then
			return jump(bm)
		elseif action == "open_tab" then
			return jump(bm, true)
		elseif action == "add" then
			add_path(cwd())
		elseif action == "add_hovered" then
			add_path(hovered_dir() or cwd())
		elseif action == "rename" then
			rename(bm)
		elseif action == "set_key" then
			set_key(bm)
		elseif action == "delete" then
			delete(bm)
		else
			return -- quit, or cancelled
		end
	end
end

function M:reflow() return { self } end

function M:redraw()
	local rows = {}
	for _, b in ipairs(self.rows or {}) do
		rows[#rows + 1] = ui.Row({
			ui.Line(b.key == "" and "-" or b.key),
			ui.Line(b.name),
			ui.Line(shorten(b.path)),
		})
	end
	if #rows == 0 then
		rows[1] = ui.Row({ ui.Line(""), ui.Line("No bookmarks yet"), ui.Line("press  a  to pin this folder") })
	end

	return {
		ui.Clear(self._area),
		ui.Border(ui.Edge.ALL)
			:area(self._area)
			:type(ui.Border.ROUNDED)
			:style(ui.Style():fg("blue"))
			:title(ui.Line("Bookmarks  (Enter go, t new tab, a add, A add hovered, r rename, s key, d delete, J/K move, q quit)")
				:align(ui.Align.CENTER)),
		ui.Table(rows)
			:area(self._area:pad(ui.Pad(1, 1, 1, 1)))
			:header(ui.Row({ "Key", "Name", "Path" }):style(ui.Style():bold()))
			:row(self.cursor)
			:row_style(ui.Style():fg("blue"):underline())
			:widths({
				ui.Constraint.Length(5),
				ui.Constraint.Percentage(35),
				ui.Constraint.Fill(1),
			}),
	}
end

function M:click() end
function M:scroll() end
function M:touch() end

return M
