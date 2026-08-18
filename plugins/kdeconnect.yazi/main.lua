--- @since 25.5.31

-- kdeconnect.yazi — browse and send files to a KDE Connect-paired phone
-- straight from Yazi, using kdeconnect-cli's native --mount /
-- --get-mount-point / --share flags (no DBus calls of our own, no gvfs
-- guesswork — this is the same mechanism KDE Connect's own "Browse this
-- device" button uses).

local function run(cmd_args)
	local cmd = Command(cmd_args[1])
	for i = 2, #cmd_args do
		cmd:arg(cmd_args[i])
	end
	local child, spawn_err = cmd:stdout(Command.PIPED):stderr(Command.PIPED):spawn()
	if spawn_err then
		return nil, tostring(spawn_err)
	end
	local output, wait_err = child:wait_with_output()
	if wait_err then
		return nil, tostring(wait_err)
	end
	if not output.status.success then
		local msg = output.stderr
		if not msg or msg == "" then
			msg = "kdeconnect-cli exited with code " .. tostring(output.status.code or "?")
		end
		return nil, msg
	end
	return output.stdout or "", nil
end

local function notify_err(fmt, ...)
	ya.notify({ title = "KDE Connect", content = string.format(fmt, ...), level = "error", timeout = 6 })
end

local function notify_info(fmt, ...)
	ya.notify({ title = "KDE Connect", content = string.format(fmt, ...), level = "info", timeout = 4 })
end

local state_option = ya.sync(function(state, attr)
	return state[attr]
end)

local current_cwd = ya.sync(function()
	local cwd = cx.active.current.cwd
	return cwd and tostring(cwd) or nil
end)

local function auto_select_single()
	local v = state_option("auto_select_single")
	if v == nil then
		return true
	end
	return v
end

-- List paired + reachable devices as { {id=..., name=...}, ... }
local function list_devices()
	local out, err = run({ "kdeconnect-cli", "-a", "--id-name-only" })
	if not out then
		return nil, err
	end
	local devices = {}
	for line in out:gmatch("[^\r\n]+") do
		local id, name = line:match("^(%S+)%s+(.*)$")
		if id then
			table.insert(devices, { id = id, name = name ~= "" and name or id })
		end
	end
	return devices, nil
end

local function pick_device(devices)
	if #devices == 0 then
		return nil
	end
	if #devices == 1 and auto_select_single() then
		return devices[1]
	end
	local cands = {}
	for i, d in ipairs(devices) do
		table.insert(cands, { on = tostring(i), desc = d.name })
	end
	table.insert(cands, { on = "q", desc = "Cancel" })
	local idx = ya.which({ cands = cands })
	if not idx or idx > #devices then
		return nil
	end
	return devices[idx]
end

local function pick_reachable_device()
	local devices, err = list_devices()
	if not devices then
		notify_err("Failed to list devices: %s", err or "unknown error")
		return nil
	end
	if #devices == 0 then
		notify_err("No paired KDE Connect devices are currently reachable.")
		return nil
	end
	return pick_device(devices)
end

-- selected_map's keys are internal, not URLs — compare by string form,
-- same as this config's (fixed) kdeconnect-send.yazi did.
local function is_selected(url, selected_map)
	if not url or not selected_map then
		return false
	end
	local needle = tostring(url)
	for _, selected_url in pairs(selected_map) do
		if selected_url and tostring(selected_url) == needle then
			return true
		end
	end
	return false
end

-- Selected files (Space/visual), falling back to the hovered file when
-- nothing is explicitly selected — matches this config's smart-enter /
-- smart-paste convention.
local get_targets = ya.sync(function()
	local selected_map = cx.active.selected
	local current_files = cx.active.current.files
	if not selected_map or not current_files then
		return {}, false
	end

	local any_selected = false
	for _ in pairs(selected_map) do
		any_selected = true
		break
	end

	if not any_selected then
		local hovered = cx.active.current.hovered
		if hovered and hovered.url and hovered.cha then
			if hovered.cha.is_dir then
				return {}, true
			end
			return { tostring(hovered.url) }, false
		end
		return {}, false
	end

	local files, dir_selected = {}, false
	for i = 1, #current_files do
		local file = current_files[i]
		if file and file.url and is_selected(file.url, selected_map) then
			if file.cha and file.cha.is_dir then
				dir_selected = true
			elseif file.cha then
				table.insert(files, tostring(file.url))
			else
				dir_selected = true
			end
		end
	end
	return files, dir_selected
end)

local function send()
	local files, dir_selected = get_targets()
	if dir_selected then
		notify_err("Can't send directories — select individual files, or archive them first (c a a).")
		return
	end
	if #files == 0 then
		notify_err("Nothing to send — select files with Space, or hover one.")
		return
	end

	local device = pick_reachable_device()
	if not device then
		return
	end

	local ok_count, fail_count = 0, 0
	for _, path in ipairs(files) do
		local _, err = run({ "kdeconnect-cli", "--share", path, "-d", device.id })
		if err then
			fail_count = fail_count + 1
			notify_err("Failed to send %s: %s", path, err)
		else
			ok_count = ok_count + 1
		end
	end

	local level = fail_count > 0 and (ok_count > 0 and "warn" or "error") or "info"
	ya.notify({
		title = "KDE Connect",
		content = string.format("Sent %d/%d file(s) to %s.", ok_count, ok_count + fail_count, device.name),
		level = level,
		timeout = 5,
	})
end

local function browse()
	local device = pick_reachable_device()
	if not device then
		return
	end

	-- --get-mount-point returns the deterministic mountpoint regardless of
	-- whether anything is actually mounted there yet.
	local path, path_err = run({ "kdeconnect-cli", "-d", device.id, "--get-mount-point" })
	if not path then
		notify_err("Could not get mount point for %s: %s", device.name, path_err or "unknown error")
		return
	end
	path = path:gsub("%s+$", "")
	if path == "" then
		notify_err("Empty mount point returned for %s.", device.name)
		return
	end

	-- If Yazi itself is currently sitting inside the mountpoint (e.g. a
	-- previous `browse` landed here and the user never left), `fusermount -u`
	-- below fails silently with "device is busy" — step out to $HOME first
	-- so the unmount can actually happen.
	local cwd = current_cwd()
	if cwd and (cwd == path or cwd:sub(1, #path + 1) == path .. "/") then
		local home = os.getenv("HOME") or "/"
		ya.emit("cd", { home })
		ya.sleep(0.1)
	end

	-- kdeconnect-cli --mount is idempotent — if the DBus side still thinks
	-- a mount is up, it won't touch it, even if the underlying sshfs's SSH
	-- session has since died (phone screen off, connection drop, etc). That
	-- leaves a mountpoint that exists but permission-denies every read,
	-- forever, until it's manually redone. Always force a clean remount so
	-- `browse` reliably gets a live, freshly-authenticated session instead
	-- of possibly reusing a stale one. Ignore the unmount's own error — it's
	-- expected to fail when nothing was mounted yet.
	run({ "fusermount", "-u", path })

	notify_info("Mounting %s…", device.name)
	local _, mount_err = run({ "kdeconnect-cli", "-d", device.id, "--mount" })
	if mount_err then
		notify_err("Mount failed for %s: %s", device.name, mount_err)
		return
	end

	-- kdeconnect-cli --mount blocks until the DBus call returns, but doesn't
	-- itself report sshfs-level failures — check the mountpoint actually
	-- exists before jumping there, and give an actionable hint if not.
	local _, test_err = run({ "test", "-d", path })
	if test_err then
		notify_err(
			"%s doesn't exist after mounting %s — is `sshfs` installed? (kdeconnect-cli reports success even when the underlying sshfs mount fails silently)",
			path,
			device.name
		)
		return
	end

	-- The bare root of the sshfs mount (kdeconnect@phone:/) is Android's own
	-- SFTP export root — KDE Connect's Android app doesn't allow *listing*
	-- that root itself (confirmed: `ls` on it permission-denies forever, on
	-- a freshly authenticated mount, every time), it only allows traversing
	-- through it into real storage. The actual files live one level of
	-- indirection deeper, at storage/emulated/0 — the same path KDE
	-- Connect's own "View this device" jumps straight to. Prefer that; fall
	-- back to the bare root for older/different KDE Connect layouts.
	local target = path .. "/storage/emulated/0"
	local _, target_test_err = run({ "test", "-d", target })
	if target_test_err then
		target = path
	end

	-- Even the real target can take a moment to become readable right after
	-- authenticating — poll with `ls` (not just `test -d`) instead of
	-- `cd`-ing Yazi into a directory that might still look empty.
	local ready = false
	local last_err = nil
	for attempt = 1, 20 do
		local _, list_err = run({ "ls", "-A", target })
		if not list_err then
			ready = true
			break
		end
		last_err = list_err
		if attempt == 1 then
			notify_info("Waiting for %s to finish connecting…", device.name)
		end
		ya.sleep(0.3)
	end

	if not ready then
		notify_err(
			"%s still refuses reads after several seconds. `ls` says: %s",
			device.name,
			last_err and last_err:gsub("%s+$", "") or "(no error text captured)"
		)
		return
	end

	ya.emit("cd", { target })
end

return {
	setup = function(state, options)
		state.auto_select_single = options and options.auto_select_single
	end,

	entry = function(_, job)
		local action = job.args and job.args[1]
		if action == "browse" then
			browse()
		elseif action == "send" then
			send()
		else
			notify_err('Usage: plugin kdeconnect browse | plugin kdeconnect send')
		end
	end,
}
