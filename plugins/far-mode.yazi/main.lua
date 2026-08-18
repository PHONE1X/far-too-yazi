--- @since 26.5.6
--- @sync entry
-- far-mode.yazi -- switches between vim-style and FAR Manager-style keymaps
-- by atomically swapping the keymap.toml symlink, saving tab/cwd layout,
-- then quitting so the `y` shell wrapper can relaunch yazi with the new
-- keymap loaded (yazi has no live keymap-reload -- see sxyazi/yazi#1757).
--
-- INCREMENT 2b -- fixes the confirmed Increment-2a bug:
--   `cx` is SYNC-CONTEXT ONLY (yazi docs, plugins/overview: "You can access
--   all states through the `cx`, within the `sync()` block, in an async
--   plugin"). ya.async() dispatches into the ASYNC runtime, so the old
--   capture_state() call inside the ya.async block was touching a `cx` that
--   does not exist there. State is now captured in `entry` itself, which is
--   `@sync` and therefore the one place `cx` is legitimately readable; only
--   the finished string is handed into the async block for file I/O.
--
-- Every step calls ya.err() so a failing run leaves a trail in
-- ~/.local/state/yazi/yazi.log. Requires YAZI_LOG=debug in the environment.

local TAG = "far-mode: "

local function log(msg)
	ya.err(TAG .. tostring(msg))
end

local function config_dir()
	return os.getenv("YAZI_CONFIG_HOME") or (os.getenv("HOME") .. "/.config/yazi")
end

-- ASYNC context (fs.* and Command are async-only per docs)
local function swap_to(target_file)
	local dir = config_dir()
	local link = dir .. "/keymap.toml"
	local tmp = dir .. "/.keymap.toml.next"
	log("swap_to: dir=" .. dir .. " target=" .. target_file)

	local _, err = Command("ln"):arg({ "-sfn", target_file, tmp }):output()
	if err then
		log("ln -sfn FAILED: " .. tostring(err))
		ya.notify({ title = "far-mode", content = "ln -sfn failed: " .. tostring(err), timeout = 6, level = "error" })
		return false
	end
	log("ln -sfn ok -> " .. tmp)

	local ok, rerr = fs.rename(Url(tmp), Url(link))
	if not ok then
		log("fs.rename FAILED: " .. tostring(rerr))
		ya.notify({ title = "far-mode", content = "fs.rename failed: " .. tostring(rerr), timeout = 6, level = "error" })
		return false
	end
	log("fs.rename ok, keymap.toml -> " .. target_file)

	return true
end

-- Resolve a split-tabs TAB ID to its current 1-based position in cx.tabs,
-- as a string ("" when absent/unresolvable).
--
-- Why this exists: split-tabs' dp.tabs used to hold plain integer POSITIONS,
-- and the restore side below still parses these two fields with "%d*" and
-- tonumber() as positions (`tabs[dual.t1]`). split-tabs was later refactored
-- to store yazi TAB ID OBJECTS instead (stable across index shifts), but this
-- capture path was never updated -- it kept doing tostring(id), which yields
-- "Id: 0x7fd73bcc2760", a raw memory address.
--
-- That broke the restore silently and completely: the "%d*\t%d*" pattern
-- cannot match "Id: 0x...", so string.match returned nil for ALL FOUR dual
-- fields at once -- pane fell back to 1, preview to false, t1/t2 to nil --
-- and the `dual.t1 and dual.t2` guard then skipped the pane-ordering step
-- entirely. Every mode switch silently discarded the whole dual-pane layout
-- and re-activated it against whatever tabs happened to sit at positions 1
-- and 2. (Confirmed in yazi.log: "dual(t1=nil t2=nil preview=false)".)
--
-- Positions are also the only thing that CAN be serialized here: a tab Id is
-- a runtime handle belonging to the process being replaced, so it is
-- meaningless to the process that reads this file back.
-- Accepts EITHER form, because the two split-tabs versions in play disagree:
-- upstream 00c3084 stores plain position integers in dp.tabs, while the
-- workspaces rewrite stored tab id objects. Passing an integer through the
-- id-lookup below would compare a number against an id and always miss,
-- silently re-breaking the save -- so numbers are taken as positions as-is.
local function pos_of(id)
	if not id then return "" end
	if type(id) == "number" then
		return (id >= 1 and id <= #cx.tabs) and tostring(id) or ""
	end
	for i = 1, #cx.tabs do
		if cx.tabs[i].id == id then return tostring(i) end
	end
	return ""
end

-- SYNC context ONLY. Must be called from `entry`, never from inside
-- ya.async(). Line-based, hand-rolled (no JSON in the sandbox): one
-- "tab\t<cwd>" line per tab, then "active\t<idx>".
local function capture_state()
	local ok, res = pcall(function()
		local lines = {}
		for i = 1, #cx.tabs do
			lines[#lines + 1] = "tab\t" .. tostring(cx.tabs[i].current.cwd)
		end
		lines[#lines + 1] = "active\t" .. tostring(cx.tabs.idx)

		-- Dual-pane (split-tabs) state, if that plugin is loaded and active.
		-- Read through the SPLIT_TABS global rather than require(), which
		-- cannot be called from a @sync entry. Absent global == inactive.
		local dual = SPLIT_TABS and SPLIT_TABS.state and SPLIT_TABS.state()
		if dual then
			lines[#lines + 1] = table.concat({
				"dual",
				tostring(dual.pane or 1),
				tostring(dual.preview and "1" or "0"),
				pos_of((dual.tabs or {})[1]),
				pos_of((dual.tabs or {})[2]),
			}, "\t")
		end

		return table.concat(lines, "\n") .. "\n"
	end)
	if not ok then
		log("capture_state FAILED: " .. tostring(res))
		return nil
	end
	log("capture_state ok (" .. #res .. " bytes): " .. res:gsub("\n", " | "))
	return res
end

-- ASYNC context
local function write_state(payload)
	local state_file = os.getenv("YAZI_STATE_FILE")
	if not state_file or state_file == "" then
		log("YAZI_STATE_FILE unset, skipping state write")
		return
	end
	if not payload then
		log("no payload (capture failed), skipping state write")
		return
	end
	local ok, err = fs.write(Url(state_file), payload)
	if not ok then
		log("fs.write FAILED: " .. tostring(err))
		ya.notify({ title = "far-mode", content = "state write failed: " .. tostring(err), timeout = 6, level = "error" })
	else
		log("state written to " .. state_file)
	end
end

-- ASYNC context. Presence of the file (any content) after yazi exits is the
-- wrapper's restart signal; content is irrelevant. Skipped if
-- $YAZI_RESTART_FILE is unset (no `y` wrapper) -- graceful-degrade path.
local function write_sentinel()
	local restart_file = os.getenv("YAZI_RESTART_FILE")
	if not restart_file or restart_file == "" then
		log("YAZI_RESTART_FILE unset -- no wrapper, will quit without restart")
		return false
	end
	local ok, err = fs.write(Url(restart_file), "1")
	if not ok then
		log("sentinel write FAILED: " .. tostring(err))
		ya.notify({ title = "far-mode", content = "sentinel write failed: " .. tostring(err), timeout = 6, level = "error" })
	else
		log("sentinel written to " .. restart_file)
	end
	return ok
end

-- SYNC context. Dumps the live tab layout into the log so a bad restore
-- leaves evidence instead of guesswork.
local function log_tabs(where)
	local ok, err = pcall(function()
		local parts = {}
		for i = 1, #cx.tabs do
			parts[#parts + 1] = i .. ":" .. tostring(cx.tabs[i].current.cwd)
		end
		local dual = SPLIT_TABS and SPLIT_TABS.state and SPLIT_TABS.state()
		local dtxt = "off"
		if dual then
			dtxt = "panes{" .. tostring((dual.tabs or {})[1]) .. "," .. tostring((dual.tabs or {})[2])
				.. "} pane=" .. tostring(dual.pane) .. " preview=" .. tostring(dual.preview)
		end
		log(where .. ": tabs=" .. #cx.tabs .. " idx=" .. tostring(cx.tabs.idx)
			.. " [" .. table.concat(parts, " | ") .. "] dual=" .. dtxt)
	end)
	if not ok then
		log(where .. ": log_tabs failed: " .. tostring(err))
	end
end

-- SYNC context. Steps 2 and 3 of the restore chain; step 1 is the async block
-- in setup(). Each step is dispatched as its own plugin command so that it
-- runs only after everything the previous step queued has been applied --
-- which is the whole point, because split-tabs reads cx.tabs at the moment it
-- activates and builds a wrong pane mapping if the tabs are not there yet.
local function restore_step(act)
	local pane, preview = act:match("^restore_dual:(%d+):(%d)$")
	if pane then
		log_tabs("restore/step2 pre-activate")
		ya.emit("plugin", { "split-tabs", "spl_activate" })
		-- Do NOT queue spl_preview / the pane switch here. A plugin command
		-- for a not-yet-loaded plugin has to read its main.lua off disk first,
		-- so spl_activate can land LATER than commands emitted after it --
		-- and spl_preview starts with `if not dp then return end`, i.e. it is
		-- silently dropped and the preview pane never comes back. Wait for
		-- dual-pane to actually be up instead.
		ya.emit("plugin", { "far-mode", "restore_wait:" .. pane .. ":" .. preview .. ":0" })
		return
	end

	local wpane, wpreview, wn = act:match("^restore_wait:(%d+):(%d):(%d+)$")
	if wpane then
		local dual = SPLIT_TABS and SPLIT_TABS.state and SPLIT_TABS.state()
		if not dual then
			local n = tonumber(wn) or 0
			if n < 40 then
				-- Re-queue ourselves; each round trip hands the event loop back
				-- to yazi, which is what lets the pending plugin load finish.
				ya.emit("plugin", { "far-mode",
					"restore_wait:" .. wpane .. ":" .. wpreview .. ":" .. (n + 1) })
			else
				log("restore: dual-pane never came up after " .. n .. " waits, giving up")
			end
			return
		end
		log("restore: dual-pane up after " .. wn .. " wait(s)")
		if wpreview == "1" and not dual.preview then
			ya.emit("plugin", { "split-tabs", "spl_preview" })
		end
		if wpane == "2" then
			-- split-tabs derives the active pane from cx.tabs.idx, so moving
			-- to the second tab AFTER activation selects pane 2 without
			-- disturbing the pane->tab mapping it has just built.
			ya.emit("tab_switch", { 1 })
		end
		ya.emit("plugin", { "far-mode", "restore_verify" })
		return
	end

	if act == "restore_verify" then
		log_tabs("restore/step3 post-activate")
	else
		log("unknown restore step: " .. tostring(act))
	end
end

-- SYNC context. nil when split-tabs is not loaded or dual-pane is off.
local function dual_state()
	if SPLIT_TABS and SPLIT_TABS.state then
		return SPLIT_TABS.state()
	end
	return nil
end

-- FAR always has two panels, so F5/F6/Tab turn dual-pane on rather than
-- refusing to work. Activation is not instant (split-tabs sets its state
-- in its own @sync entry, one command later), so the action is retried
-- through the same self-re-emitting wait the restore chain uses.
local FAR_ACTIONS = {
	far_copy = "spl_copy",
	far_move = "spl_move",
	far_switch_pane = "spl_switch_tab",
}

-- F5/F6 (far_copy/far_move) end in a full quit + relaunch, the same
-- mechanism to_far/to_vim already use to force a clean redraw, instead of
-- relying on split-tabs' repaint polling. Reasoning: split-tabs' own
-- ya.async poll (6 renders over 1.5s, see spl_transfer) already fixes the
-- common case, but a full relaunch is what the user actually asked for here
-- -- guaranteed-correct, at the cost of a visible reload flash each time.
--
-- SAFETY NOTE, load-bearing: quitting kills the WHOLE yazi process,
-- including anything still in flight -- an unfinished background copy, or
-- (via the merge-paste routing spl_transfer uses) an open Overwrite / Merge
-- / Skip / Rename prompt waiting on a keypress. There is no clean signal
-- available here for "the transfer, and any conflict prompt on it, has
-- fully finished" -- merge-paste is invoked as a fire-and-forget plugin
-- emit, not an awaitable call, so this can only wait a fixed delay and hope
-- it was enough. RELOAD_DELAY below is tuned for a quick local transfer
-- with at most one conflict the user answers promptly; a slow transfer, or
-- a conflict prompt left sitting unanswered past this delay, will get cut
-- off by the reload. If that turns out to bite in practice, the fix is to
-- stop firing merge-paste via emit and instead call its entry() directly
-- (via require(), which -- unlike @sync entry -- IS usable from inside an
-- ya.async block) so this can await real completion instead of guessing.
local RELOAD_DELAY = 2.0

local function schedule_reload_after_transfer()
	local payload = capture_state()
	ya.async(function()
		log("reload: sleeping " .. RELOAD_DELAY .. "s before relaunch")
		ya.sleep(RELOAD_DELAY)
		write_state(payload)
		local wrapped = write_sentinel()
		if not wrapped then
			log("reload: no `y` wrapper detected, cannot auto-relaunch")
			ya.notify({
				title = "far-mode",
				content = "No `y` wrapper detected -- can't auto-reload after transfer.",
				timeout = 6,
			})
			return
		end
		log("reload: emitting quit")
		ya.emit("quit", {})
	end)
end

local function far_action(base, n)
	local action = FAR_ACTIONS[base]
	if not action then
		log("unknown far action: " .. tostring(base))
		return
	end

	if dual_state() then
		ya.emit("plugin", { "split-tabs", action })
		if base == "far_copy" or base == "far_move" then
			schedule_reload_after_transfer()
		end
		return
	end

	if n == 0 then
		log(base .. ": dual-pane is off, activating it first")
		ya.emit("plugin", { "split-tabs", "spl_activate" })
	end
	if n < 40 then
		ya.emit("plugin", { "far-mode", base .. ":" .. (n + 1) })
	else
		log(base .. ": dual-pane never came up after " .. n .. " waits, giving up")
	end
end

-- Ctrl+Q is FAR's quick-view panel. With dual-pane on that is split-tabs'
-- preview pane; without it, yazi's own preview column is the right target
-- -- turning dual-pane on just to show a preview would be obnoxious.
local function far_preview()
	if dual_state() then
		ya.emit("plugin", { "split-tabs", "spl_preview" })
	else
		ya.emit("plugin", { "toggle-pane", "min-preview" })
	end
end

local function entry(st, job)
	job = type(job) == "string" and { args = { job } } or job
	local act = job and job.args and job.args[1]
	log("entry fired, act=" .. tostring(act))

	if type(act) == "string" and act:find("^restore_") then
		restore_step(act)
		return
	end

	if act == "far_preview" then
		far_preview()
		return
	end

	if type(act) == "string" then
		-- [%a_] and not %a: "far_switch_pane" has two underscores.
		local base, n = act:match("^(far_[%a_]+):(%d+)$")
		if base then
			far_action(base, tonumber(n) or 0)
			return
		end
		if FAR_ACTIONS[act] then
			far_action(act, 0)
			return
		end
	end

	local target
	if act == "to_far" then
		target = "keymap-far.toml"
	elseif act == "to_vim" then
		target = "keymap-vim.toml"
	else
		log("unknown action, aborting")
		return
	end

	-- SYNC context here (@sync entry) -- the only safe place to read cx.
	local payload = capture_state()

	ya.async(function()
		log("async block entered")
		if not swap_to(target) then
			log("swap failed, aborting before quit")
			return
		end
		write_state(payload)
		local wrapped = write_sentinel()
		if not wrapped then
			ya.notify({
				title = "far-mode",
				content = "Keymap swapped to " .. target .. ". No `y` wrapper detected -- quitting now; relaunch yazi manually to pick it up.",
				timeout = 6,
			})
		end
		log("emitting quit")
		ya.emit("quit", {})
	end)
end

-- Called from init.lua at startup: require("far-mode"):setup().
-- Whole body is pcall-wrapped so a far-mode failure can never abort
-- init.lua and take the rest of the user's plugin setup down with it.
-- Reads the state file via `cat` because yazi has no fs.read.
-- ========================= mode indicator =========================
-- A status-line chip showing which keymap is currently live. It is built
-- from the same pieces yazi's own NOR / size chips use (th.status.sep_left
-- glyphs, th.mode colours), so it inherits whatever flavor is installed
-- instead of hardcoding colours.

local current_mode = nil -- "far" | "vim" | nil (not yet known)
local LABELS = { far = "FAR", vim = "VIM" }

local mode_chip_inner -- forward declaration; defined just below

local function mode_chip(self)
	local ok, line = pcall(mode_chip_inner, self)
	if not ok then
		pcall(log, "indicator: chip render failed: " .. tostring(line))
		return "" -- never propagate: an error here blanks the whole UI
	end
	return line
end

mode_chip_inner = function(self)
	local label = LABELS[current_mode]
	if not label then
		return "" -- unknown: render nothing rather than a wrong label
	end

	-- FAR borrows the flavor's "select" accent so it is unmistakable at a
	-- glance; VIM borrows the "normal" accent, matching the NOR chip.
	local m = th.mode
	local style = ui.Style():fg("reset"):bg("reset")
		:patch(current_mode == "far" and m.select_main or m.normal_main)

	-- No :bg() on the separators: Status:redraw already paints the whole bar
	-- with th.status.overall, so leaving the background unset lets them sit
	-- on it. (Do NOT reach for App.bg() here -- that global does not exist in
	-- 26.5.6, and because this runs inside Status:redraw, any error blanks the
	-- entire Root component, not just this chip.)
	return ui.Line {
		ui.Span(th.status.sep_left.open):fg(style:bg()),
		ui.Span(" " .. label .. " "):style(style),
		ui.Span(th.status.sep_left.close):fg(style:bg()),
	}
end

local function mode_from_string(s)
	if type(s) ~= "string" then
		return nil
	elseif s:find("far", 1, true) then
		return "far"
	elseif s:find("vim", 1, true) then
		return "vim"
	end
	return nil
end

-- Path 1: $YAZI_KEYMAP_MODE, exported by the `y` wrapper just before launch.
-- os.getenv is sync-safe, so the chip is correct on the very first frame.
local function detect_mode_sync()
	return mode_from_string(os.getenv("YAZI_KEYMAP_MODE"))
end

-- Path 2: fallback for a bare `yazi` with no wrapper -- read the symlink
-- ourselves. Command() needs an async context, so the chip stays empty for a
-- frame or two, then fills in.
local function detect_mode_async()
	ya.async(function()
		local out, cerr = Command("readlink"):arg({ config_dir() .. "/keymap.toml" }):output()
		if cerr or not out or not out.stdout then
			log("indicator: readlink failed (" .. tostring(cerr) .. ")")
			return
		end
		current_mode = mode_from_string(out.stdout)
		log("indicator: mode=" .. tostring(current_mode) .. " via readlink")
		pcall(ui.render) -- best-effort repaint; next natural redraw covers us
	end)
end

local function setup()
	local ok, err = pcall(function()
		-- Mode indicator: register the chip synchronously (Status is a UI
		-- component, so it must be touched from the sync context), then work
		-- out which mode we are in. Order 2500 puts it between yazi's size
		-- chip (2000) and the hovered filename (3000).
		current_mode = detect_mode_sync()
		Status:children_add(mode_chip, 2500, Status.LEFT)
		log("indicator: registered, initial mode=" .. tostring(current_mode))
		if not current_mode then
			detect_mode_async()
		end

		local state_file = os.getenv("YAZI_STATE_FILE")
		if not state_file or state_file == "" then
			return
		end

		ya.async(function()
			log("restore: reading " .. state_file)
			local out, cerr = Command("cat"):arg({ state_file }):output()
			if cerr or not out or not out.stdout or out.stdout == "" then
				log("restore: nothing to restore (" .. tostring(cerr) .. ")")
				return
			end

			local tabs, active, dual = {}, nil, nil
			for line in out.stdout:gmatch("[^\n]+") do
				local kind, rest = line:match("^(%a+)\t(.*)$")
				if kind == "tab" then
					tabs[#tabs + 1] = rest
				elseif kind == "active" then
					active = tonumber(rest)
				elseif kind == "dual" then
					local pane, preview, t1, t2 = rest:match("^(%d*)\t(%d*)\t(%d*)\t(%d*)")
					dual = {
						pane = tonumber(pane) or 1,
						preview = preview == "1",
						t1 = tonumber(t1),
						t2 = tonumber(t2),
					}
				end
			end

			if #tabs == 0 then
				log("restore: parsed 0 tabs, nothing to do")
				return
			end

			-- Pane ORDER matters. split-tabs gives pane 1 to the tab that is
			-- active when it activates and pane 2 to the one after it, so the
			-- two pane tabs must be recreated as tabs 1 and 2 in pane order.
			-- Restoring them in raw cx.tabs order and then switching to the
			-- saved active tab before activating (what Increment 3 did) makes
			-- split-tabs map {2,1} whenever pane 2 was active -- the panes come
			-- back swapped, which reads exactly like "the left pane's directory
			-- reset itself".
			local target = active or 1
			if dual and dual.t1 and dual.t2 and tabs[dual.t1] and tabs[dual.t2] then
				local ordered = { tabs[dual.t1], tabs[dual.t2] }
				for i = 1, #tabs do
					if i ~= dual.t1 and i ~= dual.t2 then
						ordered[#ordered + 1] = tabs[i]
					end
				end
				target = (active == dual.t2) and 2 or 1
				tabs = ordered
			end
			log("restore: " .. #tabs .. " tabs, active=" .. tostring(active)
				.. " target=" .. tostring(target)
				.. (dual and (" dual(t1=" .. tostring(dual.t1) .. " t2=" .. tostring(dual.t2)
					.. " preview=" .. tostring(dual.preview) .. ")") or " dual(off)"))

			ya.emit("cd", { Url(tabs[1]) })
			for i = 2, #tabs do
				ya.emit("tab_create", { Url(tabs[i]) })
			end
			-- tab_create leaves the newly created tab active, so come back to
			-- tab 1: split-tabs must build its mapping from a known position.
			ya.emit("tab_switch", { 0 })

			if dual then
				-- Hand off to the sync half of the plugin. Activating dual-pane
				-- from here would race the tab commands just queued above; a
				-- plugin command lands behind them, so split-tabs sees the
				-- finished tab layout.
				log("restore: handing off to sync step for dual-pane")
				ya.emit("plugin", { "far-mode",
					"restore_dual:" .. target .. ":" .. (dual.preview and "1" or "0") })
			elseif target > 1 then
				ya.emit("tab_switch", { target - 1 })
			end

			-- one-shot: consume the file so a later plain relaunch (not a
			-- mode swap) doesn't re-apply stale layout
			fs.remove("file", Url(state_file))
			log("restore: done, state file consumed")
		end)
	end)
	if not ok then
		pcall(ya.err, TAG .. "setup FAILED (init.lua protected by pcall): " .. tostring(err))
	end
end

return { entry = entry, setup = setup }
