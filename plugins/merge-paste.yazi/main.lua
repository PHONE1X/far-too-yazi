--- @since 25.5.31

-- merge-paste.yazi — conflict-aware paste for Yazi, from Yazi's own yank
-- buffer or from the system clipboard.
--
-- Yazi's built-in `paste` only has two behaviors: silently auto-rename the
-- pasted item (default), or silently overwrite with `--force`. There is no
-- prompt, and no way to merge a folder into an existing one of the same
-- name — a feature request for exactly that was closed "not planned"
-- upstream (https://github.com/sxyazi/yazi/issues/982).
--
-- This plugin replaces `paste` for interactive use: for every yanked item
-- whose name collides with something already at the destination, it asks
-- Overwrite / Merge (folders only) / Skip / Rename — with an "apply to all
-- remaining conflicts" shortcut so you're not click-through-prompted file
-- by file on a big batch.
--
-- "Merge" copies the source folder's contents into the existing
-- destination folder, combining the two trees; anything that *also*
-- collides inside (same nested name) gets overwritten. That matches what
-- most GUI file managers mean by "merge" — it is not a diff/3-way merge.
--
-- System clipboard: when nothing is yanked inside Yazi, paste falls back to
-- the system clipboard, so files copied in Dolphin, Nautilus, VS Code or any
-- other app land in the current directory through the same conflict prompt.
-- Cut-vs-copy is honoured using the desktop's own clipboard markers, so a
-- cut in Dolphin moves rather than copies. Requires `wl-clipboard` on
-- Wayland or `xclip` on X11; without either, the plugin still works normally
-- with Yazi's internal yank buffer.

local function run(cmd_args)
	local cmd = Command(cmd_args[1])
	for i = 2, #cmd_args do
		cmd:arg(cmd_args[i])
	end
	local child, spawn_err = cmd:stdout(Command.PIPED):stderr(Command.PIPED):spawn()
	if spawn_err then
		return false, tostring(spawn_err)
	end
	local output, wait_err = child:wait_with_output()
	if wait_err then
		return false, tostring(wait_err)
	end
	if not output.status.success then
		local msg = output.stderr
		if not msg or msg == "" then
			msg = cmd_args[1] .. " exited with code " .. tostring(output.status.code or "?")
		end
		return false, msg
	end
	return true, nil
end

-- Like run(), but returns stdout on success and nil on any failure. Used for
-- clipboard reads, where a non-zero exit usually just means "that MIME type
-- isn't on the clipboard right now" and isn't worth reporting to the user.
local function run_out(cmd_args)
	local cmd = Command(cmd_args[1])
	for i = 2, #cmd_args do
		cmd:arg(cmd_args[i])
	end
	local child, spawn_err = cmd:stdout(Command.PIPED):stderr(Command.PIPED):spawn()
	if spawn_err then
		return nil
	end
	local output, wait_err = child:wait_with_output()
	if wait_err or not output or not output.status.success then
		return nil
	end
	return output.stdout or ""
end

local function notify_err(fmt, ...)
	ya.notify({ title = "Paste", content = string.format(fmt, ...), level = "error", timeout = 6 })
end

local function notify_info(fmt, ...)
	ya.notify({ title = "Paste", content = string.format(fmt, ...), level = "info", timeout = 4 })
end

-- Snapshot what's yanked, whether it's cut (vs copy), and where to paste —
-- into the hovered directory if there is one, otherwise the cwd (same
-- convention as this config's smart-paste). The destination is resolved
-- even when nothing is yanked, because the system-clipboard fallback needs
-- it too.
--
-- force_cwd skips the "into the hovered directory" step and always targets
-- the pane's own cwd. Needed by split-tabs' F5/F6 dual-pane transfer: it
-- switches to the OTHER pane and pastes there, and that pane's cursor can
-- be sitting on any folder the user last highlighted (not opened, just
-- highlighted) -- with the default hover-aware behavior, the file silently
-- lands inside whatever subfolder happens to be highlighted instead of the
-- pane's actual directory. "Move to the other pane" should always mean the
-- other pane's cwd, never wherever its cursor happens to rest. Ordinary
-- paste bindings (Shift+Insert, "p") don't pass this and keep the original
-- hover-aware smart-paste behavior.
local get_paste_state = ya.sync(function(_, force_cwd)
	local dest = cx.active.current.cwd
	if not force_cwd then
		local hovered = cx.active.current.hovered
		if hovered and hovered.cha and hovered.cha.is_dir then
			dest = hovered.url
		end
	end
	dest = dest and tostring(dest) or nil

	local yanked = cx.yanked
	if not yanked then
		return {}, false, dest
	end

	local is_cut = yanked.is_cut and true or false

	local sources = {}
	for _, url in pairs(yanked) do
		table.insert(sources, tostring(url))
	end

	return sources, is_cut, dest
end)

local do_unyank = ya.sync(function()
	ya.emit("unyank", {})
end)

local do_refresh = ya.sync(function()
	ya.emit("refresh", {})
end)

local function basename(path)
	return (path:gsub("/+$", "")):match("([^/]+)$") or path
end

local function join(dir, name)
	if dir:sub(-1) == "/" then
		return dir .. name
	end
	return dir .. "/" .. name
end

local function path_exists(path)
	local ok = run({ "test", "-e", path })
	return ok
end

local function is_dir(path)
	local ok = run({ "test", "-d", path })
	return ok
end

-- ---------------------------------------------------------------------------
-- System clipboard
-- ---------------------------------------------------------------------------

local function has_cmd(name)
	return run_out({ "which", name }) ~= nil
end

local function display_server()
	local t = os.getenv("XDG_SESSION_TYPE")
	if t == "wayland" or t == "x11" then
		return t
	end
	if os.getenv("WAYLAND_DISPLAY") then
		return "wayland"
	end
	if os.getenv("DISPLAY") then
		return "x11"
	end
	return nil
end

-- The MIME types currently offered by the clipboard, or nil if we can't read
-- it at all (no display server, or the helper tool isn't installed).
local function clipboard_types()
	local srv = display_server()
	local out
	if srv == "wayland" and has_cmd("wl-paste") then
		out = run_out({ "wl-paste", "--list-types" })
	elseif srv == "x11" and has_cmd("xclip") then
		out = run_out({ "xclip", "-selection", "clipboard", "-t", "TARGETS", "-o" })
	end
	if not out then
		return nil
	end

	local types = {}
	for line in out:gmatch("[^\r\n]+") do
		local t = line:match("^%s*(.-)%s*$")
		if t ~= "" then
			types[t] = true
		end
	end
	return types
end

local function clipboard_read(mime)
	local srv = display_server()
	if srv == "wayland" then
		return run_out({ "wl-paste", "-n", "-t", mime })
	elseif srv == "x11" then
		return run_out({ "xclip", "-selection", "clipboard", "-t", mime, "-o" })
	end
	return nil
end

local function percent_decode(s)
	return (s:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end))
end

-- text/uri-list -> local filesystem paths. Anything that isn't a plain local
-- file:// URI is skipped: this plugin copies files, it doesn't download.
local function uri_list_to_paths(text)
	local paths = {}
	if not text then
		return paths
	end
	for line in text:gmatch("[^\r\n]+") do
		local uri = line:match("^%s*(.-)%s*$")
		if uri ~= "" and uri:sub(1, 1) ~= "#" then
			local path = uri:match("^file://(.*)$")
			if path and path:sub(1, 1) == "/" then
				table.insert(paths, percent_decode(path))
			end
		end
	end
	return paths
end

-- GNOME/Nautilus put the operation and the URIs in a single blob:
--   copy\nfile:///a\nfile:///b
local function parse_gnome_copied_files(text)
	if not text then
		return nil, false
	end
	local first = text:match("^([^\r\n]*)") or ""
	local op = first:match("^%s*(%a+)%s*$")
	if op ~= "cut" and op ~= "copy" then
		return nil, false
	end
	return uri_list_to_paths(text:sub(#first + 1)), op == "cut"
end

-- Files currently on the system clipboard, plus whether the source app
-- marked them as a cut rather than a copy.
local function get_clipboard_paste_state()
	local types = clipboard_types()
	if not types then
		return {}, false
	end

	-- GNOME's blob carries the cut/copy flag inline, so prefer it when present.
	if types["x-special/gnome-copied-files"] then
		local paths, is_cut = parse_gnome_copied_files(clipboard_read("x-special/gnome-copied-files"))
		if paths and #paths > 0 then
			return paths, is_cut
		end
	end

	if not types["text/uri-list"] then
		return {}, false
	end

	local paths = uri_list_to_paths(clipboard_read("text/uri-list"))
	if #paths == 0 then
		return {}, false
	end

	-- KDE marks a cut with a separate flag alongside the URI list:
	-- "1" means cut, "0" means copy.
	local is_cut = false
	if types["application/x-kde-cut-selection"] then
		local flag = clipboard_read("application/x-kde-cut-selection")
		is_cut = flag ~= nil and flag:match("1") ~= nil
	end

	return paths, is_cut
end

-- After a cut-paste the sources are gone, so leaving them on the clipboard
-- would make a second paste fail confusingly. GUI file managers clear it too.
local function clear_clipboard()
	if display_server() == "wayland" and has_cmd("wl-copy") then
		run_out({ "wl-copy", "--clear" })
	end
end

-- Clipboard contents can be stale (the file was moved or deleted since it was
-- copied), so drop entries that no longer exist before pasting anything.
local function existing_only(sources)
	local present, missing = {}, 0
	for _, src in ipairs(sources) do
		if path_exists(src) then
			table.insert(present, src)
		else
			missing = missing + 1
		end
	end
	return present, missing
end

-- ---------------------------------------------------------------------------
-- Conflict resolution
-- ---------------------------------------------------------------------------

-- file.ext -> file_1.ext, file_2.ext, ... (matches Yazi's own default
-- auto-rename suffix style).
local function unique_name(dir, name)
	local stem, ext = name:match("^(.*)(%.[^./]+)$")
	if not stem or stem == "" then
		stem, ext = name, ""
	end
	for i = 1, 9999 do
		local candidate = string.format("%s_%d%s", stem, i, ext)
		if not path_exists(join(dir, candidate)) then
			return candidate
		end
	end
	return name .. "_dup"
end

-- Ask what to do about one conflicting name. Returns one of
-- "overwrite" | "merge" | "skip" | "rename" | "cancel" | nil (Esc, same as
-- cancel), plus whether the user wants this applied to all remaining
-- conflicts too.
local function ask_conflict(name, both_dirs)
	local cands = { { on = "o", desc = "Overwrite" } }
	if both_dirs then
		table.insert(cands, { on = "m", desc = "Merge folders" })
	end
	table.insert(cands, { on = "s", desc = "Skip" })
	table.insert(cands, { on = "r", desc = "Rename (keep both)" })
	table.insert(cands, { on = "q", desc = "Cancel paste" })

	notify_info('"%s" already exists at the destination.', name)
	local idx = ya.which({ cands = cands })
	if not idx then
		return "cancel", false
	end

	local map = { o = "overwrite", m = "merge", s = "skip", r = "rename", q = "cancel" }
	local action = map[cands[idx].on]
	if action == "cancel" then
		return "cancel", false
	end

	local all_idx = ya.which({
		cands = {
			{ on = "y", desc = "Yes — do this for all remaining conflicts" },
			{ on = "n", desc = "No — ask me each time" },
		},
	})

	return action, all_idx == 1
end

local function copy_or_move(is_cut, src, dst)
	if is_cut then
		return run({ "mv", src, dst })
	end
	return run({ "cp", "-a", src, dst })
end

-- Copies (or moves) src's *contents* into an existing dst directory,
-- overwriting anything that collides inside.
local function merge_into(is_cut, src, dst)
	local ok, err = run({ "cp", "-a", src .. "/.", dst .. "/" })
	if not ok then
		return false, err
	end
	if is_cut then
		return run({ "rm", "-rf", src })
	end
	return true
end

local function replace(is_cut, src, dst)
	local ok, err = run({ "rm", "-rf", dst })
	if not ok then
		return false, err
	end
	return copy_or_move(is_cut, src, dst)
end

-- Paste a single item into dest_dir, resolving a conflict if there is one.
-- `forced` (if set) is a previously-chosen action to reuse without prompting
-- again; it's ignored (and re-asked) if it doesn't apply to this item's type
-- (e.g. a forced "merge" when this particular conflict isn't folder-vs-folder).
-- Returns ok (true/false, or nil if the whole paste was cancelled), err,
-- and the (possibly updated) forced choice for the next item.
local function paste_one(is_cut, src, dest_dir, forced)
	local name = basename(src)
	local dst = join(dest_dir, name)

	if not path_exists(dst) then
		local ok, err = copy_or_move(is_cut, src, dst)
		return ok, err, forced
	end

	local both_dirs = is_dir(src) and is_dir(dst)
	local action = forced
	if action == "merge" and not both_dirs then
		action = nil
	end

	if not action then
		local chosen, apply_all = ask_conflict(name, both_dirs)
		if chosen == "cancel" then
			return nil, nil, forced
		end
		action = chosen
		if apply_all then
			forced = action
		end
	end

	local ok, err
	if action == "skip" then
		ok = true
	elseif action == "overwrite" then
		ok, err = replace(is_cut, src, dst)
	elseif action == "merge" then
		ok, err = merge_into(is_cut, src, dst)
	elseif action == "rename" then
		ok, err = copy_or_move(is_cut, src, join(dest_dir, unique_name(dest_dir, name)))
	end

	return ok, err, forced
end

local function paste(force_cwd)
	local sources, is_cut, dest_dir = get_paste_state(force_cwd)
	local from_clipboard = false

	-- Nothing yanked inside Yazi? Fall back to whatever the desktop clipboard
	-- is holding, so a copy in Dolphin/Nautilus/VS Code pastes here too.
	if #sources == 0 then
		local clip_sources, clip_is_cut = get_clipboard_paste_state()
		if #clip_sources > 0 then
			sources, is_cut, from_clipboard = clip_sources, clip_is_cut, true
		end
	end

	if #sources == 0 then
		notify_err("Nothing to paste — yank files in Yazi (y / x), or copy them in another app.")
		return
	end
	if not dest_dir then
		notify_err("Couldn't determine the destination directory.")
		return
	end

	if from_clipboard then
		local present, missing = existing_only(sources)
		if #present == 0 then
			notify_err("The clipboard points at %d file(s) that no longer exist.", missing)
			return
		end
		if missing > 0 then
			notify_info("Skipping %d clipboard entries that no longer exist.", missing)
		end
		sources = present
	end

	local forced = nil
	local ok_count, fail_count = 0, 0
	local cancelled = false

	for _, src in ipairs(sources) do
		if cancelled then
			break
		end
		local ok, err, new_forced = paste_one(is_cut, src, dest_dir, forced)
		forced = new_forced
		if ok == nil then
			cancelled = true
		elseif ok then
			ok_count = ok_count + 1
		else
			fail_count = fail_count + 1
			notify_err("Failed on %s: %s", basename(src), err and err:gsub("%s+$", "") or "unknown error")
		end
	end

	if from_clipboard then
		-- Only a cut invalidates the clipboard; a copy stays available so it
		-- can be pasted into several places, exactly like in a GUI file manager.
		if is_cut and not cancelled then
			clear_clipboard()
		end
	else
		do_unyank()
	end
	do_refresh()

	local origin = from_clipboard and " from the clipboard" or ""

	if cancelled then
		notify_info("Paste cancelled — %d item(s) done before stopping.", ok_count)
	elseif fail_count > 0 then
		ya.notify({
			title = "Paste",
			content = string.format("Done%s: %d ok, %d failed.", origin, ok_count, fail_count),
			level = "warn",
			timeout = 6,
		})
	else
		notify_info("Pasted %d item(s)%s.", ok_count, origin)
	end
end

return {
	-- job.args[1] == "cwd" forces the pane's own directory as the paste
	-- target, ignoring whatever's hovered (see get_paste_state above). Used
	-- by split-tabs' F5/F6 dual-pane transfer; absent for ordinary paste
	-- bindings, which keep the default hover-aware smart-paste behavior.
	entry = function(_, job)
		job = type(job) == "string" and { args = { job } } or job
		local force_cwd = job and job.args and job.args[1] == "cwd"
		paste(force_cwd)
	end,
}
