--- @since 25.5.31

local toggle_ui = ya.sync(function(self)
	if self.children then
		Modal:children_remove(self.children)
		self.children = nil
	else
		self.children = Modal:children_add(self, 10)
	end
	if ui.render then ui.render() else ya.render() end
end)

local subscribe = ya.sync(function(self)
	ps.unsub("mount")
	ps.sub("mount", function() ya.emit("plugin", { self._id, "refresh" }) end)
end)

local update_partitions = ya.sync(function(self, partitions)
	self.partitions = partitions
	self.cursor = math.max(0, math.min(self.cursor or 0, #self.partitions - 1))
	if ui.render then ui.render() else ya.render() end
end)

local active_partition = ya.sync(function(self) return self.partitions[self.cursor + 1] end)

local update_cursor = ya.sync(function(self, cursor)
	if #self.partitions == 0 then
		self.cursor = 0
	else
		self.cursor = ya.clamp(0, self.cursor + cursor, #self.partitions - 1)
	end
	if ui.render then ui.render() else ya.render() end
end)

local M = {
	keys = {
		{ on = "q", run = "quit" },
		{ on = "<Esc>", run = "quit" },
		{ on = "<Enter>", run = { "enter", "quit" } },
		{ on = "k", run = "up" },
		{ on = "j", run = "down" },
		{ on = "l", run = { "enter", "quit" } },
		{ on = "<Up>", run = "up" },
		{ on = "<Down>", run = "down" },
		{ on = "<Right>", run = { "enter", "quit" } },
		{ on = "m", run = "mount" },
		{ on = "u", run = "unmount" },
		{ on = "e", run = "eject" },
	},
}

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
			ui.Constraint.Percentage(10),
			ui.Constraint.Percentage(80),
			ui.Constraint.Percentage(10),
		})
		:split(chunks[2])

	self._area = chunks[2]
end

function M:entry(job)
	if job.args[1] == "refresh" then
		return update_partitions(self.obtain())
	end

	toggle_ui()
	update_partitions(self.obtain())
	subscribe()

	local tx1, rx1 = ya.chan("mpsc")
	local tx2, rx2 = ya.chan("mpsc")
	
	function producer()
		while true do
			local cand = self.keys[ya.which { cands = self.keys, silent = true }] or { run = {} }
			for _, r in ipairs(type(cand.run) == "table" and cand.run or { cand.run }) do
				tx1:send(r)
				if r == "quit" then
					toggle_ui()
					return
				end
			end
		end
	end

	function consumer1()
		repeat
			local run = rx1:recv()
			if run == "quit" then
				tx2:send(run)
				break
			elseif run == "up" then
				update_cursor(-1)
			elseif run == "down" then
				update_cursor(1)
			elseif run == "enter" then
				local active = active_partition()
				if active and active.mountpoint then
					ya.emit("cd", { active.mountpoint })
				end
			else
				tx2:send(run)
			end
		until not run
	end

	function consumer2()
		repeat
			local run = rx2:recv()
			if run == "quit" then
				break
			elseif run == "mount" then
				self.operate("mount")
			elseif run == "unmount" then
				self.operate("unmount")
			elseif run == "eject" then
				self.operate("eject")
			end
		until not run
	end

	ya.join(producer, consumer1, consumer2)
end

function M:reflow() return { self } end

function M:redraw()
	local rows = {}
	for _, p in ipairs(self.partitions or {}) do
		local name_col = p.name
		if p.is_child then
			name_col = "  " .. p.name
		end

		local style = ui.Style()
		if p.mountpoint then
			style = style:fg("green")
		end

		rows[#rows + 1] = ui.Row({
			ui.Line(name_col),
			ui.Line(p.label or "-"),
			ui.Line(p.size or ""),
			ui.Line(p.fstype or "?"),
			ui.Line(p.mountpoint or ""):style(style),
		})
	end

	return {
		ui.Clear(self._area),
		ui.Border(ui.Edge.ALL)
			:area(self._area)
			:type(ui.Border.ROUNDED)
			:style(ui.Style():fg("blue"))
			:title(ui.Line("Drives & Partitions"):align(ui.Align.CENTER)),
		ui.Table(rows)
			:area(self._area:pad(ui.Pad(1, 1, 1, 1)))
			:header(ui.Row({ "Device", "Label", "Size", "Type", "Mountpoint" }):style(ui.Style():bold()))
			:row(self.cursor)
			:row_style(ui.Style():fg("blue"):underline())
			:widths({
				ui.Constraint.Length(12),
				ui.Constraint.Length(20),
				ui.Constraint.Length(10),
				ui.Constraint.Length(10),
				ui.Constraint.Fill(1),
			}),
	}
end

local function parse_lsblk_tree(devices, result, depth)
	if not devices then return end
	
	for _, dev in ipairs(devices) do
		local is_valid = true
		if dev.type == "loop" or dev.type == "rom" or dev.type == "ram" then is_valid = false end
		
		if is_valid then
			table.insert(result, {
				name = dev.name,
				path = dev.path,
				label = dev.label,
				fstype = dev.fstype,
				mountpoint = dev.mountpoint,
				size = dev.size,
				type = dev.type,
				is_child = depth > 0
			})
			
			if dev.children then
				parse_lsblk_tree(dev.children, result, depth + 1)
			end
		end
	end
end

function M.obtain()
	if ya.target_os() ~= "linux" then return {} end

	local output, err = Command("lsblk")
		:arg("-J")
		:arg("-o")
		:arg("NAME,PATH,LABEL,FSTYPE,MOUNTPOINT,SIZE,TYPE")
		:output()

	if not output or not output.stdout then
		ya.notify({ title = "Mount", content = "lsblk failed", level = "error" })
		return {}
	end

	local json = ya.json_decode(output.stdout)
	if not json or not json.blockdevices then return {} end

	local tbl = {}
	parse_lsblk_tree(json.blockdevices, tbl, 0)
	return tbl
end

function M.operate(op)
	local active = active_partition()
	if not active then return end

	if not active.path then
		M.fail("No device path found")
		return
	end

	if op == "mount" then
		if active.mountpoint then
			M.fail("Already mounted")
			return
		end
		if active.fstype == "swap" then
			M.fail("Cannot mount swap")
			return
		end
	end

	-- Пытаемся смонтировать даже если fstype неизвестен
	local output, err
	if op == "eject" then
		Command("udisksctl"):arg({ "unmount", "-b", active.path }):status()
		output, err = Command("udisksctl"):arg({ "power-off", "-b", active.path }):output()
	else
		output, err = Command("udisksctl"):arg({ op, "-b", active.path }):output()
	end

	if not output then
		M.fail("Process failed: %s", err)
	elseif not output.status.success then
		local msg = output.stderr
		if not msg or msg == "" then
			-- Если stderr пустой, значит проблема в Polkit агенте
			msg = "Error: Authentication dialog failed (Polkit Agent missing?)"
		else
			-- Очищаем мусор из сообщения udisks
			msg = msg:gsub("^Error looking up object for device assuming command is object path: ", "")
		end
		M.fail("%s", msg)
	else
		ya.emit("plugin", { "mount", "refresh" })
	end
end

function M.fail(...) ya.notify { title = "Mount", content = string.format(...), timeout = 5, level = "error" } end

function M:click() end
function M:scroll() end
function M:touch() end

return M
