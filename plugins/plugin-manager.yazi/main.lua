--- @since 26.5.6
-- plugin-manager.yazi -- a full-window popup (same style as openers.yazi's F
-- popup) for browsing yazi plugins and installing one with `ya pkg add`
-- (yazi's own package manager -- this is a catalog + picker on top of it,
-- not a reimplementation).
--
-- The list is a small bundled catalog (guaranteed to work offline) merged
-- with a live pull from GitHub (repos tagged `topic:yazi-plugin`, currently
-- 100+) whenever curl+jq are available and the network answers in time --
-- so this isn't capped at a hand-picked few. Press `r` inside the popup to
-- (re)fetch; it works fine without ever pressing that, just with a shorter
-- list.
--
-- Bound to Alt+P (vim keymap) / Alt+P (FAR keymap).

local TAG = "plugin-manager: "
local function log(msg)
	ya.err(TAG .. tostring(msg))
end

------------------------------------------------------------- bundled catalog

-- Guaranteed-available baseline (no network needed): the official
-- yazi-rs/plugins set plus the community plugins already vetted for this
-- project (see package.toml / README credits). Live-fetched entries are
-- merged on top of this, not instead of it.
local BUNDLED = {
	{ id = "yazi-rs/plugins:smart-enter", desc = "Enter directories or open files with one key" },
	{ id = "yazi-rs/plugins:full-border", desc = "Draw a full border around the UI" },
	{ id = "yazi-rs/plugins:toggle-pane", desc = "Show, hide, or maximize individual panes" },
	{ id = "yazi-rs/plugins:jump-to-char", desc = "Vim-like jump to a file by its leading character" },
	{ id = "yazi-rs/plugins:git", desc = "Show git status as a linemode column" },
	{ id = "yazi-rs/plugins:mount", desc = "Mount, unmount, and eject disks" },
	{ id = "yazi-rs/plugins:vcs-files", desc = "Show per-file git change status" },
	{ id = "yazi-rs/plugins:piper", desc = "Pipe any shell command as a file previewer" },
	{ id = "yazi-rs/plugins:zoom", desc = "Zoom the image preview in and out" },
	{ id = "yazi-rs/plugins:smart-filter", desc = "Live filtering that also enters matching directories" },
	{ id = "yazi-rs/plugins:chmod", desc = "Change permissions on selected files" },
	{ id = "yazi-rs/plugins:mime-ext", desc = "Guess MIME type from file extension" },
	{ id = "yazi-rs/plugins:smart-paste", desc = "Paste into the hovered directory automatically" },
	{ id = "yazi-rs/plugins:diff", desc = "Diff two selected files and view the patch" },
	{ id = "yazi-rs/plugins:no-status", desc = "Hide the status bar for a cleaner look" },
	{ id = "yazi-rs/plugins:mactag", desc = "Read/write macOS Finder tags" },
	{ id = "yazi-rs/plugins:visual-pivot", desc = "Move the cursor without losing the current selection" },
	{ id = "yazi-rs/plugins:term-cwd", desc = "Tell the terminal the cwd changed (OSC 7)" },
	{ id = "ndtoan96/ouch", desc = "Compress/decompress via the ouch CLI" },
	{ id = "KKV9/compress", desc = "Archive selected files (zip/7z/tar/...)" },
	{ id = "dedukun/relative-motions", desc = "Vim-style relative-count motions (3j, 5k, ...)" },
	{ id = "XYenon/clipboard", desc = "Copy files to the system clipboard" },
	{ id = "Sonico98/allmytoes", desc = "Thumbnail previews via the AllMyToes daemon" },
	{ id = "boydaihungst/restore", desc = "Undo the last delete" },
	{ id = "uhs-robert/recycle-bin", desc = "Route deletes through a recoverable recycle bin" },
	{ id = "boydaihungst/ucp", desc = "Progress bar for large copy/move operations" },
}

-- Ids that resolve to a monorepo/umbrella rather than a single installable
-- plugin -- `ya pkg add` on these alone doesn't make sense, so a live fetch
-- result matching one is dropped rather than shown as a false lead.
local SKIP_IDS = { ["yazi-rs/plugins"] = true }

------------------------------------------------------------------ live fetch

-- One shell call: curl the GitHub search API for `topic:yazi-plugin` repos,
-- pipe through jq to TSV (id, description). No JSON decoder in yazi's Lua
-- API, so jq does that job instead of a hand-rolled parser.
local FETCH_CMD = [[curl -s --max-time 6 'https://api.github.com/search/repositories?q=topic:yazi-plugin&per_page=100&sort=stars&order=desc' | jq -r '.items[]? | "\(.full_name)\t\(.description // "")"']]

local function fetch_live()
	local child, err = Command("sh"):arg({ "-c", FETCH_CMD }):stdout(Command.PIPED):stderr(Command.PIPED):spawn()
	if not child then
		log("fetch spawn failed: " .. tostring(err))
		return nil
	end
	local out = child:wait_with_output()
	if not out or not out.status.success or not out.stdout or out.stdout == "" then
		log("fetch produced no output (offline, or no curl/jq)")
		return nil
	end

	local live = {}
	for line in out.stdout:gmatch("[^\n]+") do
		local id, desc = line:match("^([^\t]+)\t(.*)$")
		if id and not SKIP_IDS[id] then
			live[#live + 1] = { id = id, desc = (desc ~= "" and desc or "(no description)") }
		end
	end
	return live
end

-- Bundled entries win on id collision (hand-written descriptions), live
-- entries are appended after, in the order GitHub returned them (by stars).
local function merge_catalog(live)
	local seen, merged = {}, {}
	for _, e in ipairs(BUNDLED) do
		merged[#merged + 1] = e
		seen[e.id] = true
	end
	for _, e in ipairs(live or {}) do
		if not seen[e.id] then
			merged[#merged + 1] = e
			seen[e.id] = true
		end
	end
	return merged
end

local function filtered(catalog, needle)
	if not needle or needle == "" then return catalog end
	needle = needle:lower()
	local out = {}
	for _, e in ipairs(catalog) do
		if e.id:lower():find(needle, 1, true) or e.desc:lower():find(needle, 1, true) then
			out[#out + 1] = e
		end
	end
	return out
end

--------------------------------------------------------------- install step

-- Runs OUTSIDE the modal, same as openers.yazi's do_add/do_edit -- the
-- modal is hidden first so this can safely show its own notify() calls.
local function do_install(entry)
	if not entry then return end
	ya.notify { title = "plugin-manager", content = "Installing " .. entry.id .. "...", timeout = 3 }

	local child, spawn_err = Command("ya"):arg({ "pkg", "add", entry.id }):stdout(Command.PIPED):stderr(Command.PIPED):spawn()
	if not child then
		return ya.notify {
			title = "plugin-manager",
			content = "Failed to run `ya pkg add`: " .. tostring(spawn_err),
			timeout = 8,
			level = "error",
		}
	end

	local output, wait_err = child:wait_with_output()
	if not output then
		return ya.notify {
			title = "plugin-manager",
			content = "`ya pkg add " .. entry.id .. "` failed: " .. tostring(wait_err),
			timeout = 8,
			level = "error",
		}
	end

	if output.status.success then
		ya.notify {
			title = "plugin-manager",
			content = entry.id .. " installed. Wire up its keymap entry / init.lua require() if it needs one -- see the plugin's own README.",
			timeout = 8,
		}
	else
		local detail = output.stderr ~= "" and output.stderr or output.stdout
		ya.notify {
			title = "plugin-manager",
			content = "Failed to install " .. entry.id .. ": " .. detail,
			timeout = 10,
			level = "error",
		}
	end
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

local set_rows = ya.sync(function(self, rows, status)
	self.rows = rows
	self.status = status
	self.cursor = math.max(0, math.min(self.cursor or 0, math.max(0, #rows - 1)))
	if ui.render then ui.render() else ya.render() end
end)

local active_row = ya.sync(function(self) return self.rows[(self.cursor or 0) + 1] end)
local get_state = ya.sync(function(self) return self.catalog, self.filter, self.live_count end)
local set_state = ya.sync(function(self, catalog, filter, live_count)
	self.catalog, self.filter = catalog, filter
	if live_count ~= nil then self.live_count = live_count end
end)

local update_cursor = ya.sync(function(self, delta)
	if not self.rows or #self.rows == 0 then
		self.cursor = 0
	else
		self.cursor = ya.clamp(0, (self.cursor or 0) + delta, #self.rows - 1)
	end
	if ui.render then ui.render() else ya.render() end
end)

local KEYS = {
	{ on = "q", run = "quit" },
	{ on = "<Esc>", run = "quit" },
	{ on = "k", run = "up" },
	{ on = "j", run = "down" },
	{ on = "<Up>", run = "up" },
	{ on = "<Down>", run = "down" },
	{ on = "<Enter>", run = "install" },
	{ on = "i", run = "install" },
	{ on = "/", run = "filter" },
	{ on = "c", run = "clear" },
	{ on = "r", run = "refresh" },
}

local M = {}

function M:new(area)
	self:layout(area)
	return self
end

function M:layout(area)
	local chunks = ui.Layout()
		:constraints({
			ui.Constraint.Percentage(10),
			ui.Constraint.Percentage(80),
			ui.Constraint.Percentage(10),
		})
		:split(area)

	local chunks = ui.Layout()
		:direction(ui.Layout.HORIZONTAL)
		:constraints({
			ui.Constraint.Percentage(5),
			ui.Constraint.Percentage(90),
			ui.Constraint.Percentage(5),
		})
		:split(chunks[2])

	self._area = chunks[2]
end

local function status_line(catalog, filter, live_count)
	local parts = { #catalog .. " plugins" }
	if filter and filter ~= "" then parts[#parts + 1] = "filter: " .. filter end
	if live_count then
		parts[#parts + 1] = live_count .. " from GitHub (topic:yazi-plugin)"
	else
		parts[#parts + 1] = "press r to fetch more from GitHub"
	end
	return table.concat(parts, "  |  ")
end

-- One pass of: show the modal, let the user browse, and exit as soon as
-- they ask for something that needs work outside the key loop (install,
-- filter input, quit) -- same shape as openers.yazi's run_modal.
function M:run_modal()
	toggle_ui()

	local catalog, filter, live_count = get_state()
	set_rows(filtered(catalog, filter), status_line(catalog, filter, live_count))

	local tx, rx = ya.chan("mpsc")
	local action

	local function producer()
		while true do
			local cand = KEYS[ya.which({ cands = KEYS, silent = true })]
			local run = cand and cand.run or nil
			if run then
				tx:send(run)
				if run == "quit" or run == "install" or run == "filter" or run == "refresh" then
					return
				end
			end
		end
	end

	local function consumer()
		repeat
			local run = rx:recv()
			if run == "up" then
				update_cursor(-1)
			elseif run == "down" then
				update_cursor(1)
			elseif run == "clear" then
				set_state(catalog, nil, live_count)
				set_rows(catalog, status_line(catalog, nil, live_count))
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
	local catalog = merge_catalog(nil)
	set_state(catalog, nil)

	local live_count = nil
	while true do
		local action = self:run_modal()
		if action == "install" then
			do_install(active_row())
		elseif action == "filter" then
			local needle, ev = ya.input({ title = "Filter (name or description):", pos = { "top-center", y = 3, w = 50 } })
			if ev == 1 then
				local cat = select(1, get_state())
				set_state(cat, needle)
			end
		elseif action == "refresh" then
			ya.notify { title = "plugin-manager", content = "Fetching plugin list from GitHub...", timeout = 3 }
			local live = fetch_live()
			if live then
				live_count = #live
				local cat, filter = get_state()
				local merged = merge_catalog(live)
				set_state(merged, filter)
			else
				ya.notify {
					title = "plugin-manager",
					content = "Fetch failed (offline, or curl/jq missing) -- keeping the bundled list.",
					timeout = 6,
					level = "warn",
				}
			end
		else
			return
		end
	end
end

function M:reflow() return { self } end

function M:redraw()
	local rows = {}
	for _, e in ipairs(self.rows or {}) do
		rows[#rows + 1] = ui.Row({ ui.Line(e.id), ui.Line(e.desc) })
	end

	return {
		ui.Clear(self._area),
		ui.Border(ui.Edge.ALL)
			:area(self._area)
			:type(ui.Border.ROUNDED)
			:style(ui.Style():fg("blue"))
			:title(ui.Line("Plugin manager  (j/k move, Enter/i install, / filter, c clear, r refresh from GitHub, q quit)"):align(ui.Align.CENTER)),
		ui.Table(rows)
			:area(self._area:pad(ui.Pad(1, 2, 1, 1)))
			:header(ui.Row({ "Plugin", "Description" }):style(ui.Style():bold()))
			:row(self.cursor or 0)
			:row_style(ui.Style():fg("blue"):underline())
			:widths({
				ui.Constraint.Percentage(30),
				ui.Constraint.Fill(1),
			}),
		ui.Text(self.status or ""):area(self._area:pad(ui.Pad(0, 2, 0, 1))):align(ui.Align.LEFT),
	}
end

function M:click() end
function M:scroll() end
function M:touch() end

return M
