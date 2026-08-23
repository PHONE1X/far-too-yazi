--- @since 25.5.31
--- @sync entry

-- Yazi on this system loses the target file when it hands off to an
-- [opener] entry -- the resolved url never reaches the spawned process, so
-- e.g. `nvim "$@"` or `gwenview "$@"` launch with zero args (nvim shows its
-- welcome screen, gwenview/haruna/etc just open blank). Instead of going
-- through yazi's [opener]/[open] dispatch at all, this plugin spawns the
-- right program directly via the Lua Command API and inlines the path, which
-- sidesteps the broken arg-passing entirely.
--
-- To change which program opens which file type, don't edit this file --
-- pass an `openers` table to require("smart-enter"):setup{} in init.lua.
-- See the commented example there. Anything with no matching extension
-- falls back to `editor` (default "nvim").

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

local function build_lookup(openers)
	local map = {}
	for _, rule in ipairs(openers) do
		for _, ext in ipairs(rule.ext) do
			map[ext:lower()] = rule
		end
	end
	return map
end

local function fail(cmd, err)
	ya.notify({ title = "Open", content = string.format("Failed to launch %s: %s", cmd, tostring(err)), level = "error", timeout = 5 })
end

local function setup(self, opts)
	opts = opts or {}
	self.open_multi = opts.open_multi
	self.editor = opts.editor or "nvim"
	self.lookup = build_lookup(opts.openers or DEFAULT_OPENERS)
end

local function entry(self)
	local h = cx.active.current.hovered
	if not h then return end

	if h.cha.is_dir then
		ya.emit("enter", { hovered = not self.open_multi })
		return
	end

	local ext = h.name:match("%.([^.]+)$")
	ext = ext and ext:lower() or ""
	local path = tostring(h.url)
	local lookup = self.lookup or build_lookup(DEFAULT_OPENERS)
	local rule = lookup[ext]

	if rule then
		local args = {}
		for _, a in ipairs(rule.args or {}) do args[#args + 1] = a end
		args[#args + 1] = path
		local _, err = Command(rule.cmd):arg(args):spawn()
		if err then fail(rule.cmd, err) end
	else
		-- treated as text: hand it to the editor via an inlined shell string,
		-- since a blocking TUI editor needs yazi to release the terminal
		-- (the "shell --block" mechanism handles that; direct Command:spawn()
		-- would not).
		local editor = self.editor or "nvim"
		ya.emit("shell", { editor .. " " .. ya.quote(path), block = true })
	end
end

return { entry = entry, setup = setup }
