--- @since 25.5.31

-- Popup for editing which program opens which file type, AND the state
-- Yazi starts up in (keymap mode, panel layout, hidden files, sort order).
-- Bound to F / Alt+F4, see keymap-vim.toml / keymap-far.toml. <Tab> inside
-- the popup switches between the two pages -- one shortcut, two jobs, so we
-- don't need to hunt for a second free key.

------------------------------------------------------------------ file i/o

local function config_dir()
	return os.getenv("YAZI_CONFIG_HOME") or (os.getenv("HOME") .. "/.config/yazi")
end

local function read_file(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local content = f:read("*a")
	f:close()
	return content
end

local function write_file(path, content)
	local f, err = io.open(path, "w")
	if not f then return false, err end
	f:write(content)
	f:close()
	return true
end

-- Loads a file that is plain Lua returning a table (openers-data.lua,
-- startup-data.lua) -- running it is simpler than shipping a JSON parser.
local function load_data_file(path)
	local content = read_file(path)
	if not content then return nil end
	local chunk = load(content, "@" .. path)
	if not chunk then return nil end
	local ok, result = pcall(chunk)
	if ok and type(result) == "table" then return result end
	return nil
end

local function lua_quote(s)
	return string.format("%q", s)
end

local function fail(s, ...)
	ya.notify({ title = "Yazi config", content = string.format(s, ...), level = "error", timeout = 5 })
end

------------------------------------------------------------- openers page

local DEFAULT_OPENERS = {
	{ ext = { "jpg", "jpeg", "png", "gif", "bmp", "webp", "svg", "ico", "tiff", "tif", "heic", "avif" }, cmd = "gwenview" },
	{ ext = { "mp4", "mkv", "webm", "avi", "mov", "flv", "wmv", "m4v" }, cmd = "haruna" },
	{ ext = { "mp3", "flac", "wav", "ogg", "m4a", "opus" }, cmd = "mpv" },
	{ ext = { "pdf" }, cmd = "okular" },
	{ ext = { "doc", "docx", "odt" }, cmd = "libreoffice", args = { "--writer" } },
	{ ext = { "xls", "xlsx", "ods" }, cmd = "libreoffice", args = { "--calc" } },
	{ ext = { "ppt", "pptx", "odp" }, cmd = "libreoffice", args = { "--impress" } },
	{ ext = { "zip", "tar", "gz", "bz2", "7z", "rar", "xz", "zst", "jar" }, cmd = "ouch", args = { "decompress" } },
	{ ext = { "exe", "msi", "bat", "lnk" }, cmd = "portproton" },
}

local function openers_path()
	return config_dir() .. "/openers-data.lua"
end

local function serialize_openers(openers)
	local lines = {
		"-- Edited via the Yazi config popup (F, Openers page).",
		"-- You can also hand-edit this, it's just a Lua table.",
		"return {",
	}
	for _, rule in ipairs(openers) do
		local ext_parts = {}
		for _, e in ipairs(rule.ext) do ext_parts[#ext_parts + 1] = lua_quote(e) end
		local line = string.format("\t{ ext = { %s }, cmd = %s", table.concat(ext_parts, ", "), lua_quote(rule.cmd))
		if rule.args and #rule.args > 0 then
			local arg_parts = {}
			for _, a in ipairs(rule.args) do arg_parts[#arg_parts + 1] = lua_quote(a) end
			line = line .. string.format(", args = { %s }", table.concat(arg_parts, ", "))
		end
		lines[#lines + 1] = line .. " },"
	end
	lines[#lines + 1] = "}\n"
	return table.concat(lines, "\n")
end

local function save_openers(openers)
	local ok, err = fs.write(Url(openers_path()), serialize_openers(openers))
	if not ok then fail("Failed to save: %s", tostring(err)) end
end

local function load_openers()
	return load_data_file(openers_path()) or DEFAULT_OPENERS
end

-- "a,b, c" -> {"a","b","c"}, lowercased, empty entries dropped
local function parse_ext_list(s)
	local out = {}
	for piece in s:gmatch("[^,%s]+") do
		out[#out + 1] = piece:lower():gsub("^%.", "")
	end
	return out
end

----------------------------------------------------------- yazi.toml [mgr]

local function yazi_toml_path()
	return config_dir() .. "/yazi.toml"
end

-- Rewrites specific `key = value` lines inside the [mgr] section of
-- yazi.toml, leaving every other line (comments, other sections) untouched.
-- Appends any key not already present right after the [mgr] header. This is
-- the only way to change Yazi's actual startup defaults for these settings
-- -- they are read by the Rust core before any Lua runs, so nothing short of
-- editing the file itself takes effect on the next launch.
local function patch_yazi_toml(overrides)
	local path = yazi_toml_path()
	local content = read_file(path)
	if not content then
		fail("Could not read %s", path)
		return false
	end

	local remaining = {}
	for k, v in pairs(overrides) do remaining[k] = v end

	local out = {}
	local in_mgr = false
	local mgr_header_idx = nil
	for line in (content .. "\n"):gmatch("(.-)\n") do
		local section = line:match("^%[([%w_.]+)%]%s*$")
		if section then
			in_mgr = section == "mgr"
			if in_mgr then mgr_header_idx = #out + 1 end
		end

		local replaced = false
		if in_mgr then
			local key = line:match("^(%a[%w_]*)%s*=")
			if key and remaining[key] ~= nil then
				out[#out + 1] = key .. " = " .. remaining[key]
				remaining[key] = nil
				replaced = true
			end
		end
		if not replaced then out[#out + 1] = line end
	end

	-- Anything left in `remaining` wasn't found in [mgr] -- insert it right
	-- after the section header (or create the section if it's missing).
	local leftover = {}
	for k, v in pairs(remaining) do leftover[#leftover + 1] = k .. " = " .. v end
	if #leftover > 0 then
		if mgr_header_idx then
			for i, l in ipairs(leftover) do table.insert(out, mgr_header_idx + i, l) end
		else
			table.insert(out, 1, "[mgr]")
			for i, l in ipairs(leftover) do table.insert(out, 1 + i, l) end
		end
	end

	-- Drop the trailing empty element the gmatch pattern above always
	-- produces (it matches the string's final, artificial "\n").
	if out[#out] == "" then out[#out] = nil end

	local ok, err = write_file(path, table.concat(out, "\n") .. "\n")
	if not ok then fail("Failed to save %s: %s", path, tostring(err)) end
	return ok
end

------------------------------------------------------------- startup page

-- The only setting here with nowhere else to live: dual-pane is a runtime
-- feature of split-tabs.yazi, not a yazi.toml key, so "start in dual-pane"
-- has to be remembered somewhere of our own. Keymap mode doesn't need an
-- entry -- the keymap.toml symlink itself is already the persisted state.
-- Hidden/sort don't either -- those are patched straight into yazi.toml.
local function startup_path()
	return config_dir() .. "/startup-data.lua"
end

local function load_startup()
	return load_data_file(startup_path()) or { panels = "single" }
end

local function save_startup(overrides)
	local data = load_startup()
	for k, v in pairs(overrides) do data[k] = v end
	local ok, err = fs.write(Url(startup_path()), string.format(
		"-- Edited via the Yazi config popup (F, Startup page).\nreturn { panels = %s }\n",
		lua_quote(data.panels)
	))
	if not ok then fail("Failed to save: %s", tostring(err)) end
end

local SORT_BY_OPTIONS = { "natural", "alphabetical", "mtime", "btime", "extension", "size", "random", "none" }

local function current_keymap_mode()
	local m = os.getenv("YAZI_KEYMAP_MODE")
	if m and m:find("far", 1, true) then return "far" end
	return "vim"
end

-- SYNC: rt.mgr and SPLIT_TABS are live plugin/runtime state.
-- rt.mgr.* is the yazi.toml *default*, not the live value -- it does not
-- move when a "hidden"/"sort" command changes the active tab, so comparing
-- against it here would make apply_live_mgr wrongly believe a toggle is a
-- no-op forever after the first live change. cx.active.pref is the tab's
-- actual current preference (per Yazi's tab::Pref) and is what stays in
-- sync with commands like `hidden toggle` / `sort natural`.
local get_live_mgr = ya.sync(function()
	local pref = cx.active.pref
	return {
		hidden = pref.show_hidden,
		sort_by = pref.sort_by,
		sort_dir_first = pref.sort_dir_first,
		sort_reverse = pref.sort_reverse,
	}
end)

local get_dual_raw = ya.sync(function()
	return SPLIT_TABS and SPLIT_TABS.state and SPLIT_TABS.state()
end)

local function panels_label(d)
	if not d then return "single" end
	return d.preview and "dual_preview" or "dual"
end

local function build_settings_rows()
	local mgr = get_live_mgr()
	return {
		{ key = "keymap", label = "Keymap mode", value = current_keymap_mode(),
			options = { "vim", "far" }, hint = "relaunches yazi" },
		{ key = "panels", label = "Panels", value = panels_label(get_dual_raw()),
			options = { "single", "dual", "dual_preview" } },
		{ key = "hidden", label = "Hidden files", value = mgr.hidden and "shown" or "hidden",
			options = { "hidden", "shown" } },
		{ key = "sort_by", label = "Sort by", value = mgr.sort_by, options = SORT_BY_OPTIONS },
		{ key = "sort_dir_first", label = "Folders first", value = mgr.sort_dir_first and "on" or "off",
			options = { "off", "on" } },
		{ key = "sort_reverse", label = "Reverse sort", value = mgr.sort_reverse and "on" or "off",
			options = { "off", "on" } },
	}
end

local function next_value(row, forward)
	local idx = 1
	for i, v in ipairs(row.options) do
		if v == row.value then idx = i break end
	end
	local n = #row.options
	idx = forward and (idx % n) + 1 or ((idx - 2) % n) + 1
	return row.options[idx]
end

-- Applies the current [mgr] settings live via the same "sort"/"hidden"
-- manager commands the keymap already binds (e.g. `hidden toggle`,
-- `sort mtime --reverse=no`) -- ya.emit's positional/named args mirror that
-- exact CLI-style syntax. Called after any of hidden/sort_by/dir_first/
-- reverse changes, so the running session always matches what was just
-- written to yazi.toml, not just the next launch.
local function apply_live_mgr(desired)
	local live = get_live_mgr()
	if live.hidden ~= (desired.hidden == "shown") then
		ya.emit("hidden", { "toggle" })
	end
	if live.sort_by ~= desired.sort_by
		or live.sort_dir_first ~= (desired.sort_dir_first == "on")
		or live.sort_reverse ~= (desired.sort_reverse == "on")
	then
		ya.emit("sort", { desired.sort_by, reverse = desired.sort_reverse == "on", dir_first = desired.sort_dir_first == "on" })
	end
end

local function patch_mgr_from_rows(rows)
	local by_key = {}
	for _, r in ipairs(rows) do by_key[r.key] = r.value end
	patch_yazi_toml({
		show_hidden = tostring(by_key.hidden == "shown"),
		sort_by = lua_quote(by_key.sort_by),
		sort_dir_first = tostring(by_key.sort_dir_first == "on"),
		sort_reverse = tostring(by_key.sort_reverse == "on"),
	})
	apply_live_mgr(by_key)
end

-- Brings dual-pane to the desired on/off + quick-preview state. spl_activate
-- is not synchronous from here (it lands as its own later plugin command),
-- so bringing preview up right after it -- like far-mode's restore chain
-- warns about -- can silently no-op if dual-pane isn't actually up yet.
-- Self-re-emitting wait, capped, same technique far-mode.yazi uses.
local function sync_preview_step(act)
	local want, n = act:match("^sync_preview:(%d):(%d+)$")
	if not want then return end
	local d = get_dual_raw()
	if not d then
		local i = tonumber(n) or 0
		if i < 40 then
			ya.emit("plugin", { "openers", "sync_preview:" .. want .. ":" .. (i + 1) })
		end
		return
	end
	if want == "1" and not d.preview then
		ya.emit("plugin", { "split-tabs", "spl_preview" })
	elseif want == "0" and d.preview then
		ya.emit("plugin", { "split-tabs", "spl_preview" })
	end
end

local function set_panels(target, persist)
	local d = get_dual_raw()
	local now = panels_label(d)
	if target ~= now then
		if target == "single" then
			if d then ya.emit("plugin", { "split-tabs", "spl_deactivate" }) end
		elseif not d then
			ya.emit("plugin", { "split-tabs", "spl_activate" })
			ya.emit("plugin", { "openers", "sync_preview:" .. (target == "dual_preview" and "1" or "0") .. ":0" })
		else
			-- already dual, just the preview pane needs to flip
			ya.emit("plugin", { "split-tabs", "spl_preview" })
		end
	end
	if persist then save_startup({ panels = target }) end
end

-- Returns the rows to display right after the change. Built with the just-
-- requested value forced in, rather than re-reading rt.mgr/SPLIT_TABS
-- fresh -- ya.emit is fire-and-forget, so a live re-read done this soon
-- routinely still sees the pre-change state and the popup would flash the
-- old value right after the user picked the new one (and, worse, cycling
-- again would compute the next step from that stale value).
local function apply_setting(row, new_value)
	if row.key == "keymap" then
		if new_value ~= current_keymap_mode() then
			ya.emit("plugin", { "far-mode", new_value == "far" and "to_far" or "to_vim" })
		end
	elseif row.key == "panels" then
		set_panels(new_value, true)
	else
		-- hidden / sort_by / sort_dir_first / sort_reverse: patch+apply the
		-- WHOLE group together, since yazi's "sort" command takes all three
		-- sort fields at once and we'd rather not desync yazi.toml from the
		-- live session by only handling the one field that changed.
		local rows = build_settings_rows()
		for _, r in ipairs(rows) do
			if r.key == row.key then r.value = new_value end
		end
		patch_mgr_from_rows(rows)
		return rows
	end

	local rows = build_settings_rows()
	for _, r in ipairs(rows) do
		if r.key == row.key then r.value = new_value end
	end
	return rows
end

-- Called once from init.lua on every launch. Only acts if the user asked
-- for something other than the (default) single-pane start, and only when
-- there is nothing for far-mode to restore -- a real, non-empty
-- $YAZI_STATE_FILE means this launch is a mode-swap relaunch with a
-- captured session (including its own dual-pane state), which far-mode
-- itself is about to restore; stepping on that here would race it.
local function boot()
	local panels = load_startup().panels
	if not panels or panels == "single" then return end

	local state_file = os.getenv("YAZI_STATE_FILE")
	if not state_file or state_file == "" then
		set_panels(panels, false)
		return
	end

	ya.async(function()
		local out, cerr = Command("cat"):arg({ state_file }):output()
		if cerr or not out or not out.stdout or out.stdout == "" then
			set_panels(panels, false)
		end
	end)
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

local set_page = ya.sync(function(self, page, rows)
	self.page = page
	self.rows = rows
	self.cursor = 0
	if ui.render then ui.render() else ya.render() end
end)

local update_rows = ya.sync(function(self, rows)
	self.rows = rows
	self.cursor = math.max(0, math.min(self.cursor or 0, math.max(0, #self.rows - 1)))
	if ui.render then ui.render() else ya.render() end
end)

local active_row = ya.sync(function(self) return self.rows[self.cursor + 1] end)
local current_page = ya.sync(function(self) return self.page end)

local update_cursor = ya.sync(function(self, delta)
	if #self.rows == 0 then
		self.cursor = 0
	else
		self.cursor = ya.clamp(0, self.cursor + delta, #self.rows - 1)
	end
	if ui.render then ui.render() else ya.render() end
end)

local OPENERS_KEYS = {
	{ on = "q", run = "quit" },
	{ on = "<Esc>", run = "quit" },
	{ on = "k", run = "up" },
	{ on = "j", run = "down" },
	{ on = "<Up>", run = "up" },
	{ on = "<Down>", run = "down" },
	{ on = "<Tab>", run = "page" },
	{ on = "a", run = "add" },
	{ on = "e", run = "edit" },
	{ on = "<Enter>", run = "edit" },
	{ on = "d", run = "delete" },
	{ on = "x", run = "delete" },
}

local SETTINGS_KEYS = {
	{ on = "q", run = "quit" },
	{ on = "<Esc>", run = "quit" },
	{ on = "k", run = "up" },
	{ on = "j", run = "down" },
	{ on = "<Up>", run = "up" },
	{ on = "<Down>", run = "down" },
	{ on = "<Tab>", run = "page" },
	{ on = "l", run = "cycle_fwd" },
	{ on = "<Right>", run = "cycle_fwd" },
	{ on = "<Enter>", run = "cycle_fwd" },
	{ on = "<Space>", run = "cycle_fwd" },
	{ on = "h", run = "cycle_back" },
	{ on = "<Left>", run = "cycle_back" },
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

	local chunks = ui.Layout()
		:direction(ui.Layout.HORIZONTAL)
		:constraints({
			ui.Constraint.Percentage(10),
			ui.Constraint.Percentage(80),
			ui.Constraint.Percentage(10),
		})
		:split(chunks[2])

	self._area = chunks[2]
end

-- Runs OUTSIDE the modal (it's hidden first) since ya.input needs the
-- keyboard focus that the modal's own key loop would otherwise be holding.
function M.do_add()
	local ext_str, ev1 = ya.input({ title = "Extensions (comma-separated, e.g. jpg,jpeg):", pos = { "top-center", y = 3, w = 50 } })
	if ev1 ~= 1 or not ext_str or ext_str == "" then return end

	local cmd, ev2 = ya.input({ title = "Program (same as typing it in a terminal):", pos = { "top-center", y = 3, w = 50 } })
	if ev2 ~= 1 or not cmd or cmd == "" then return end

	local openers = load_openers()
	openers[#openers + 1] = { ext = parse_ext_list(ext_str), cmd = cmd }
	save_openers(openers)
end

function M.do_edit()
	local row = active_row()
	if not row then return M.do_add() end

	local cmd, ev = ya.input({
		title = string.format("Program for .%s (Enter to keep):", table.concat(row.ext, ", .")),
		value = row.cmd,
		pos = { "top-center", y = 3, w = 50 },
	})
	if ev == 1 and cmd and cmd ~= "" then
		local openers = load_openers()
		for _, r in ipairs(openers) do
			if r == row or (r.cmd == row.cmd and table.concat(r.ext, ",") == table.concat(row.ext, ",")) then
				r.cmd = cmd
				break
			end
		end
		save_openers(openers)
	end
end

function M.do_delete()
	local row = active_row()
	if not row then return end

	local openers = load_openers()
	for i, r in ipairs(openers) do
		if r.cmd == row.cmd and table.concat(r.ext, ",") == table.concat(row.ext, ",") then
			table.remove(openers, i)
			break
		end
	end
	save_openers(openers)
end

function M.do_keymap_switch(forward)
	local row = { key = "keymap", value = current_keymap_mode(), options = { "vim", "far" } }
	local nv = next_value(row, forward)
	apply_setting(row, nv)
end

local function rows_for(page)
	return page == "settings" and build_settings_rows() or load_openers()
end

-- One pass of: show the modal, let the user browse/cycle, and exit as soon
-- as they ask for something that needs ya.input (openers add/edit) or is
-- done (quit) -- ya.join only returns once every joined coroutine has, so
-- by the time this function returns, nothing is left listening for keys and
-- it's safe to call ya.input.
function M:run_modal()
	toggle_ui()
	set_page(self.page or "openers", rows_for(self.page or "openers"))

	local tx, rx = ya.chan("mpsc")
	local action

	function producer()
		-- Tracked locally instead of re-reading current_page() every loop:
		-- consumer() is what actually calls set_page() (on its own coroutine,
		-- via the tx/rx channel), so a current_page() read done here right
		-- after sending "page" can still see the pre-switch value -- tx:send
		-- doesn't wait for the consumer to catch up. That stale read got
		-- picked as *this* loop's candidate table and only self-corrected on
		-- the iteration *after* -- meaning the very first key pressed right
		-- after <Tab> was always matched against the OLD page's keys (e.g.
		-- <Enter> landing as Openers' "edit" instead of Settings' "cycle_fwd").
		-- Updating this local immediately when WE see "page" ourselves avoids
		-- the round trip.
		local page = current_page() or "openers"
		while true do
			local keys = page == "settings" and SETTINGS_KEYS or OPENERS_KEYS
			local cand = keys[ya.which({ cands = keys, silent = true })]
			local run = cand and cand.run or nil
			if run then
				if run == "page" then
					page = page == "settings" and "openers" or "settings"
				-- Changing keymap mode always ends in far-mode quitting the
				-- process (relaunch), which pops yazi's own "unfinished tasks,
				-- quit anyway?" confirm dialog if our key-listener is still
				-- running -- it would silently eat the keys meant for that
				-- dialog, same problem ya.input had. Route it out to the exit
				-- path like add/edit/delete instead of handling it inline.
				elseif page == "settings" and (run == "cycle_fwd" or run == "cycle_back") then
					local row = active_row()
					if row and row.key == "keymap" then
						run = "keymap_" .. run
					end
				end
				tx:send(run)
				if run == "quit" or run == "add" or run == "edit" or run == "delete"
					or run == "keymap_cycle_fwd" or run == "keymap_cycle_back"
				then
					return
				end
			end
		end
	end

	function consumer()
		repeat
			local run = rx:recv()
			if run == "up" then
				update_cursor(-1)
			elseif run == "down" then
				update_cursor(1)
			elseif run == "page" then
				local page = current_page() == "settings" and "openers" or "settings"
				set_page(page, rows_for(page))
			elseif run == "cycle_fwd" or run == "cycle_back" then
				local row = active_row()
				if row then
					local new_value = next_value(row, run == "cycle_fwd")
					update_rows(apply_setting(row, new_value))
				end
			else
				action = run
				return
			end
		until not run
	end

	ya.join(producer, consumer)
	toggle_ui()
	return action
end

function M:entry(job)
	local act = job and job.args and job.args[1]
	if act == "boot" then
		boot()
		return
	end
	if type(act) == "string" and act:find("^sync_preview:") then
		sync_preview_step(act)
		return
	end

	while true do
		local action = self:run_modal()
		if action == "add" then
			M.do_add()
		elseif action == "edit" then
			M.do_edit()
		elseif action == "delete" then
			M.do_delete()
		elseif action == "keymap_cycle_fwd" or action == "keymap_cycle_back" then
			M.do_keymap_switch(action == "keymap_cycle_fwd")
			return -- a relaunch is coming; don't reopen and race its quit-confirm
		else
			return
		end
	end
end

function M:reflow() return { self } end

function M:redraw()
	if self.page == "settings" then
		local rows = {}
		for _, r in ipairs(self.rows or {}) do
			local value = r.value
			if r.hint then value = value .. "  (" .. r.hint .. ")" end
			rows[#rows + 1] = ui.Row({ ui.Line(r.label), ui.Line(value) })
		end
		return {
			ui.Clear(self._area),
			ui.Border(ui.Edge.ALL)
				:area(self._area)
				:type(ui.Border.ROUNDED)
				:style(ui.Style():fg("blue"))
				:title(ui.Line("Startup settings  (h/l cycle, Tab: Openers, q quit)"):align(ui.Align.CENTER)),
			ui.Table(rows)
				:area(self._area:pad(ui.Pad(1, 1, 1, 1)))
				:header(ui.Row({ "Setting", "Value" }):style(ui.Style():bold()))
				:row(self.cursor)
				:row_style(ui.Style():fg("blue"):underline())
				:widths({
					ui.Constraint.Percentage(50),
					ui.Constraint.Fill(1),
				}),
		}
	end

	local rows = {}
	for _, r in ipairs(self.rows or {}) do
		local ext_str = "." .. table.concat(r.ext, ", .")
		local cmd_str = r.cmd
		if r.args and #r.args > 0 then cmd_str = cmd_str .. " " .. table.concat(r.args, " ") end
		rows[#rows + 1] = ui.Row({ ui.Line(ext_str), ui.Line(cmd_str) })
	end

	return {
		ui.Clear(self._area),
		ui.Border(ui.Edge.ALL)
			:area(self._area)
			:type(ui.Border.ROUNDED)
			:style(ui.Style():fg("blue"))
			:title(ui.Line("Openers  (a add, e edit, d delete, Tab: Startup, q quit)"):align(ui.Align.CENTER)),
		ui.Table(rows)
			:area(self._area:pad(ui.Pad(1, 1, 1, 1)))
			:header(ui.Row({ "Extensions", "Program" }):style(ui.Style():bold()))
			:row(self.cursor)
			:row_style(ui.Style():fg("blue"):underline())
			:widths({
				ui.Constraint.Percentage(50),
				ui.Constraint.Fill(1),
			}),
	}
end

function M:click() end
function M:scroll() end
function M:touch() end

return M
