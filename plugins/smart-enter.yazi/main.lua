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
-- Keep this table in sync with [opener]/[open] in yazi.toml if you add a
-- new file type there.
local IMAGE = { jpg=1, jpeg=1, png=1, gif=1, bmp=1, webp=1, svg=1, ico=1, tiff=1, tif=1, heic=1, avif=1 }
local VIDEO = { mp4=1, mkv=1, webm=1, avi=1, mov=1, flv=1, wmv=1, m4v=1 }
local AUDIO = { mp3=1, flac=1, wav=1, ogg=1, m4a=1, opus=1 }
local ARCHIVE = { zip=1, tar=1, gz=1, bz2=1, ["7z"]=1, rar=1, xz=1, zst=1, jar=1 }
local EXE = { exe=1, msi=1, bat=1, lnk=1 }
local OFFICE = {
	doc = "--writer", docx = "--writer", odt = "--writer",
	xls = "--calc", xlsx = "--calc", ods = "--calc",
	ppt = "--impress", pptx = "--impress", odp = "--impress",
}
local PDF = { pdf = 1 }

local function fail(cmd, err)
	ya.notify({ title = "Open", content = string.format("Failed to launch %s: %s", cmd, tostring(err)), level = "error", timeout = 5 })
end

local function spawn(cmd, args)
	local _, err = Command(cmd):arg(args):spawn()
	if err then fail(cmd, err) end
end

local function setup(self, opts) self.open_multi = opts.open_multi end

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

	if EXE[ext] then
		spawn("portproton", { path })
	elseif ARCHIVE[ext] then
		local _, err = Command("ouch"):arg({ "decompress", path }):spawn()
		if err then fail("ouch", err) end
	elseif OFFICE[ext] then
		spawn("libreoffice", { OFFICE[ext], path })
	elseif PDF[ext] then
		spawn("okular", { path })
	elseif IMAGE[ext] then
		spawn("gwenview", { path })
	elseif VIDEO[ext] then
		spawn("haruna", { path })
	elseif AUDIO[ext] then
		spawn("mpv", { path })
	else
		-- treated as text: hand it to nvim via an inlined shell string,
		-- since a blocking TUI editor needs yazi to release the terminal
		-- (the "shell --block" mechanism handles that; direct Command:spawn()
		-- would not).
		ya.emit("shell", { "nvim " .. ya.quote(path), block = true })
	end
end

return { entry = entry, setup = setup }
