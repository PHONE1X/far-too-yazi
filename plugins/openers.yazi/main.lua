--- @since 25.5.31

-- Popup for editing which program opens which file type (bound to F, see
-- keymap-vim.toml). Reads/writes the same data file that
-- plugins/smart-enter.yazi/main.lua reads on every Enter/l -- so a change
-- made here takes effect immediately, no restart needed.

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

local function config_dir()
	return os.getenv("YAZI_CONFIG_HOME") or (os.getenv("HOME") .. "/.config/yazi")
end

local function data_path()
	return config_dir() .. "/openers-data.lua"
end

local function read_file(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local content = f:read("*a")
	f:close()
	return content
end

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

local function serialize(openers)
	local lines = {
		"-- Edited via the openers popup (F in the file manager).",
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

local function fail(s, ...)
	ya.notify({ title = "Openers", content = string.format(s, ...), level = "error", timeout = 5 })
end

local function save(openers)
	local ok, err = fs.write(Url(data_path()), serialize(openers))
	if not ok then fail("Failed to save: %s", tostring(err)) end
end

local function load_openers()
	return load_data_file(data_path()) or DEFAULT_OPENERS
end

-- "a,b, c" -> {"a","b","c"}, lowercased, empty entries dropped
local function parse_ext_list(s)
	local out = {}
	for piece in s:gmatch("[^,%s]+") do
		out[#out + 1] = piece:lower():gsub("^%.", "")
	end
	return out
end

local toggle_ui = ya.sync(function(self)
	if self.children then
		Modal:children_remove(self.children)
		self.children = nil
	else
		self.children = Modal:children_add(self, 10)
	end
	if ui.render then ui.render() else ya.render() end
end)

local update_rows = ya.sync(function(self, rows)
	self.rows = rows
	self.cursor = math.max(0, math.min(self.cursor or 0, math.max(0, #self.rows - 1)))
	if ui.render then ui.render() else ya.render() end
end)

local active_row = ya.sync(function(self) return self.rows[self.cursor + 1] end)

local update_cursor = ya.sync(function(self, delta)
	if #self.rows == 0 then
		self.cursor = 0
	else
		self.cursor = ya.clamp(0, self.cursor + delta, #self.rows - 1)
	end
	if ui.render then ui.render() else ya.render() end
end)

local M = {
	keys = {
		{ on = "q", run = "quit" },
		{ on = "<Esc>", run = "quit" },
		{ on = "k", run = "up" },
		{ on = "j", run = "down" },
		{ on = "<Up>", run = "up" },
		{ on = "<Down>", run = "down" },
		{ on = "a", run = "add" },
		{ on = "e", run = "edit" },
		{ on = "<Enter>", run = "edit" },
		{ on = "d", run = "delete" },
		{ on = "x", run = "delete" },
	},
}

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

-- Called only once the modal's key-loop coroutine has fully exited (see
-- run_modal below) -- ya.input needs sole keyboard focus, and a `which`
-- listener left running in the background would steal keys (Enter, letters
-- that double as list shortcuts) intended for the input field.
function M.do_add()
	local ext_str, ev1 = ya.input({ title = "Extensions (comma-separated, e.g. jpg,jpeg):", pos = { "top-center", y = 3, w = 50 } })
	if ev1 ~= 1 or not ext_str or ext_str == "" then return end

	local cmd, ev2 = ya.input({ title = "Program (same as typing it in a terminal):", pos = { "top-center", y = 3, w = 50 } })
	if ev2 ~= 1 or not cmd or cmd == "" then return end

	local openers = load_openers()
	openers[#openers + 1] = { ext = parse_ext_list(ext_str), cmd = cmd }
	save(openers)
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
		save(openers)
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
	save(openers)
end

-- One pass of: show the modal, let the user browse with j/k, and exit as
-- soon as they ask for something that needs ya.input (add/edit) or is done
-- (quit) -- ya.join only returns once every joined coroutine has, so by the
-- time this function returns, nothing is left listening for keys and it's
-- safe to call ya.input.
function M:run_modal()
	toggle_ui()
	update_rows(load_openers())

	local tx, rx = ya.chan("mpsc")
	local action

	function producer()
		while true do
			local cand = self.keys[ya.which({ cands = self.keys, silent = true })]
			local run = cand and cand.run or nil
			if run then
				tx:send(run)
				if run == "quit" or run == "add" or run == "edit" or run == "delete" then
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

function M:entry()
	while true do
		local action = self:run_modal()
		if action == "add" then
			M.do_add()
		elseif action == "edit" then
			M.do_edit()
		elseif action == "delete" then
			M.do_delete()
		else
			return
		end
	end
end

function M:reflow() return { self } end

function M:redraw()
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
			:title(ui.Line("Openers  (a add, e edit, d delete, q quit)"):align(ui.Align.CENTER)),
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
