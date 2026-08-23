--- @since 25.5.31
--- @sync entry

-- Extensions that should NOT be handed to $EDITOR -- keep this in sync with
-- the non-text branches of [open].prepend_rules in yazi.toml (images, video,
-- archives, office/pdf, exe). Everything else is treated as text.
local NON_TEXT_EXT = {
	jpg = 1, jpeg = 1, png = 1, gif = 1, bmp = 1, webp = 1, svg = 1, ico = 1, tiff = 1, tif = 1, heic = 1, avif = 1,
	mp4 = 1, mkv = 1, webm = 1, avi = 1, mov = 1, flv = 1, wmv = 1, m4v = 1,
	mp3 = 1, flac = 1, wav = 1, ogg = 1, m4a = 1, opus = 1,
	zip = 1, tar = 1, gz = 1, bz2 = 1, ["7z"] = 1, rar = 1, xz = 1, zst = 1, jar = 1,
	pdf = 1, doc = 1, docx = 1, odt = 1, xls = 1, xlsx = 1, ods = 1, ppt = 1, pptx = 1, odp = 1,
	exe = 1, msi = 1, bat = 1, lnk = 1,
}

local function setup(self, opts) self.open_multi = opts.open_multi end

local function entry(self)
	local h = cx.active.current.hovered
	if not h then return end

	if h.cha.is_dir then
		ya.emit("enter", { hovered = not self.open_multi })
		return
	end

	-- Yazi on this system loses the target file when it hands off to an
	-- [opener] entry (block or not -- the resolved url never reaches the
	-- spawned process, so `nvim "$@"` launches with zero args and shows the
	-- welcome screen instead of the file). Inlining the path into the shell
	-- string sidesteps that broken arg-passing and actually opens the file.
	local ext = h.name:match("%.([^.]+)$")
	ext = ext and ext:lower() or ""
	if NON_TEXT_EXT[ext] == nil then
		ya.emit("shell", { "nvim " .. ya.quote(tostring(h.url)), block = true })
		return
	end

	ya.emit("open", { hovered = not self.open_multi })
end

return { entry = entry, setup = setup }
