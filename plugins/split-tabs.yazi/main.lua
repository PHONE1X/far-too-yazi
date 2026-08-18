--- @since 26.5.6
--- @sync entry

-- nil when inactive; holds all dual-pane state when active.
local dp = nil
local saved = {}

local function active_pane()
    return cx.tabs.idx == dp.tabs[2] and 2 or 1
end

local function other_pane()
    return active_pane() == 1 and 2 or 1
end

-- Minimal component: renders static elements. Needs _id/_area for ui.redraw().
local Overlay = {}
function Overlay:new(id, area, elements)
    return setmetatable({ _id = id, _area = area, _elements = elements or {} }, { __index = self })
end

function Overlay:reflow() return {} end

function Overlay:redraw() return self._elements end

-- Polyfill: Marker lacks reflow(), which crashes Tab:reflow() on resize.
if not Marker.reflow then
    Marker.reflow = function() return {} end
end

-- Wraps a Current to suppress cursor highlight via dp._no_cursor flag.
local Pane = {}
function Pane:new(area, tab, active)
    return setmetatable(
        { _id = active and "current" or "my-current", _area = area, _active = active, _inner = Current:new(area, tab) },
        { __index = self }
    )
end

function Pane:reflow() return self._inner:reflow() end

function Pane:redraw()
    dp._no_cursor = not self._active
    local elements = self._inner:redraw()
    dp._no_cursor = nil
    return elements
end

local function apply_dual_tab_patch()
    Tab.layout = function(self)
        if #cx.tabs < 2 and not dp.creating then
            dp.creating = true
            ya.emit("tab_create", { cx.active.current.cwd })
            dp.tabs = { 1, 2 }
        elseif #cx.tabs >= 2 then
            dp.creating = nil
        end

        if #cx.tabs > 2 then
            for i = #cx.tabs, 1, -1 do
                if i ~= dp.tabs[1] and i ~= dp.tabs[2] then
                    ya.emit("tab_close", { i - 1 }) -- 0-based
                    break
                end
            end
        end

        dp.pane = active_pane()

        -- Preview on: split vertically first, then horizontally for panes.
        local pane_area = self._area
        if dp.preview then
            local vsplit = ui.Layout()
                :direction(ui.Layout.VERTICAL)
                :constraints({
                    ui.Constraint.Fill(1),
                    ui.Constraint.Fill(1),
                })
                :split(self._area)
            pane_area = vsplit[1]
            dp.preview_area = vsplit[2]
        else
            dp.preview_area = nil
        end

        -- Active pane uses the "current" slot; inactive gets a zero-width slot.
        self._chunks = ui.Layout()
            :direction(ui.Layout.HORIZONTAL)
            :constraints({
                ui.Constraint.Fill(1),
                ui.Constraint.Fill(1),
                ui.Constraint.Length(0),
            })
            :split(pane_area)
    end

    Tab.build = function(self, ...)
        saved.tab_build(self, ...)

        local c = self._chunks
        local tab1 = cx.tabs[dp.tabs[1]]
        local tab2 = cx.tabs[dp.tabs[2]]

        if not tab1 or not tab2 then
            self._children = {}
            return
        end

        self._children = {
            Pane:new(c[1]:pad(ui.Pad(0, 0, 0, 1)), tab1, dp.pane == 1),
            Pane:new(c[2]:pad(ui.Pad.x(1)), tab2, dp.pane == 2),

            Marker:new(c[1], tab1.current),

            Rails:new(c, self._tab), -- draw a rail between "parent" and "current" panels
            Marker:new(c[2], tab2.current),
        }

        if dp.preview and dp.preview_area then
            -- Overlap preview 1 row up to share the pane's bottom border line.
            local pa = dp.preview_area
            local joined = ui.Rect { x = pa.x, y = pa.y - 1, w = pa.w, h = pa.h + 1 }
            self._children[#self._children + 1] = Overlay:new("border", joined, {
                ui.Border(ui.Edge.ALL):area(joined),
            })
            self._children[#self._children + 1] = Preview:new(joined:pad(ui.Pad(1, 1, 1, 1)), self._tab)
        else
            -- Zero-width "preview" rect prevents stale Rust-side preview rendering.
            -- Height stays non-zero so Folder::make window size isn't clamped to 0.
            self._children[#self._children + 1] = Overlay:new("preview",
                ui.Rect { x = 0, y = 0, w = 0, h = self._area.h }, {})
        end
    end
end

local function apply_header_patch()
    Header.cwd = function(self)
        local w = self._area.w
        local mid = math.floor(w / 2) - 1

        local tab1 = cx.tabs[dp.tabs[1]]
        local tab2 = dp.tabs[2] and cx.tabs[dp.tabs[2]]
        local pane = dp.pane or 1

        if not tab1 then return "" end

        if not tab2 then
            local s = ya.readable_path(tostring(tab1.current.cwd))
            return ui.Span(ui.truncate(s, { max = w, rtl = true })):style(th.tabs.active)
        end

        -- Left path: pad to exactly `mid` columns so the separator aligns with the pane split.
        local p1 = ya.readable_path(tostring(tab1.current.cwd))
        p1 = ui.truncate(p1, { max = mid, rtl = true })
        local pad = mid - #p1
        if pad > 0 then
            p1 = p1 .. string.rep(" ", pad)
        end

        local right_avail = math.max(0, w - mid - 1 - (self._right_width or 0)) - 4
        local p2 = ya.readable_path(tostring(tab2.current.cwd))
        p2 = ui.truncate(p2, { max = right_avail, rtl = true })

        -- LOCAL CHANGE vs upstream 00c3084: upstream patches both of these
        -- with bg("reset") to avoid a filled bar across each header half.
        -- That does not survive a flavor whose active-tab style carries its
        -- contrast in the BACKGROUND: gruvbox-dark defines
        --   tabs.active = { fg = "#282828", bg = "#a89984" }
        -- i.e. near-black text meant to sit on a light chip. Strip the
        -- background and you are left with #282828 (relative luminance 0.16)
        -- on a dark terminal -- the active pane's path becomes unreadable,
        -- while the inactive one survives only because its fg is already
        -- light. Keeping the background restores the intended look: the
        -- active half renders as a filled bar in the FLAVOR'S OWN colors.
        --
        -- Deliberately no hardcoded colors here -- both styles come straight
        -- from the active flavor, so this follows the global theme and needs
        -- no theme.toml override.
        local s_active = th.tabs.active
        local s_inactive = th.tabs.inactive

        return ui.Line {
            ui.Span(p1):style(pane == 1 and s_active or s_inactive),
            ui.Span(" "),
            ui.Span(p2):style(pane == 2 and s_active or s_inactive),
        }
    end
end

local function restore_all()
    Tab.layout = saved.tab_layout
    Tab.build = saved.tab_build
    Header.cwd = saved.header_cwd
    Tabs.height = saved.tabs_height
    Entity.style = saved.entity_style
end

local function activate()
    if dp then return end

    ps.sub("ind-watch", function(args)
        args.files = { cx.tabs[dp.tabs[1]].current.file, cx.tabs[dp.tabs[2]].current.file }

        -- If the preview pane is active and the hovered entity is a directory,
        -- add it to the watch list as well so that the directory can be loaded when absent.
        local hovered = cx.tabs[active_pane()].current.hovered
        if dp.preview and hovered and hovered.cha.is_dir then
            args.files[#args.files + 1] = hovered
        end

        return args
    end)

    ps.sub("relay-update-files", function(args)
        args.tabs = { cx.tabs[dp.tabs[1]].id, cx.tabs[dp.tabs[2]].id }
        return args
    end)

    saved.tab_layout = Tab.layout
    saved.tab_build = Tab.build
    saved.header_cwd = Header.cwd
    saved.tabs_height = Tabs.height
    saved.entity_style = Entity.style

    Entity.style = function(self)
        if dp and dp._no_cursor then
            return self._file:style() or ui.Style()
        end
        return saved.entity_style(self)
    end

    Tabs.height = function() return 0 end

    local n = #cx.tabs
    local cur = cx.tabs.idx
    local tab2_idx

    if n >= 2 then
        tab2_idx = (cur < n) and (cur + 1) or 1
    else
        tab2_idx = 2
        ya.emit("tab_create", { cx.active.current.cwd })
        -- tab_create makes the new tab active. Queue a switch back so the
        -- original tab remains the left (active) pane after initialization.
        ya.emit("tab_switch", { cur - 1 })
    end

    dp = { pane = 1, view = "dual", tabs = { cur, tab2_idx }, creating = n < 2, preview = false }

    apply_dual_tab_patch()
    apply_header_patch()
    ui.render()
end

local function deactivate()
    if not dp then return end
    ps.unsub("ind-watch")
    ps.unsub("relay-update-files")
    ya.emit("tab_close", { other_pane() - 1 })
    restore_all()
    dp = nil
    saved = {}
    ui.render()
end

local function spl_activate()
    activate()
end

local function spl_deactivate()
    deactivate()
end

local function spl_toggle()
    if dp then deactivate() else activate() end
end

local function spl_preview()
    if not dp then return end
    dp.preview = not dp.preview
    ui.render()
    if dp.preview then
        ya.emit("peek", { 0 })
    else
        -- Different skip value forces preview.reset() which clears protocol images.
        ya.emit("peek", { 99999 })
    end
end

local function spl_switch_tab()
    if not dp then return end
    ya.emit("tab_switch", { dp.tabs[other_pane()] - 1 })
    ui.render()
end

-- Apply a file operation to the selection (or the hovered file) and send it
-- to the other pane, using yazi's own yank/paste task queue -- the same
-- machinery the "y" and "p" keys use. That path recurses into directories,
-- reports progress, and prompts on name conflicts. A hand-rolled copy gets
-- none of those for free.
--
-- LOCAL CHANGE vs upstream 00c3084. Upstream calls:
--     ya.task(op, { from = url, to = cwd:join(url.name) }):spawn()
-- inside a ya.async block. `ya.task` is not a real yazi API -- it appears
-- neither in the documentation nor in yazi's source. The call therefore
-- raises, and because the surrounding ya.async block is unprotected the
-- error is swallowed. The visible effect is that copy and move between
-- panes silently do nothing at all, in both keymaps. Driving yank + paste
-- across a tab_switch uses the engine's real file-operation path instead.
--
-- Note dp.tabs holds tab POSITION INDICES in this upstream-based version
-- (the later workspaces rewrite stored tab id objects and resolved them via
-- tab_by_id). Keep that in mind if this is ported forward again.
local function spl_transfer(operation)
    if not dp then return end

    local src_idx = dp.tabs[active_pane()]
    local dst_idx = dp.tabs[other_pane()]
    local source = cx.tabs[src_idx]
    if not source or not cx.tabs[dst_idx] then return end

    local n = 0
    for _ in pairs(source.selected) do
        n = n + 1
    end
    if n == 0 and not source.current.hovered then return end

    ya.emit("yank", operation == "move" and { cut = true } or {})
    ya.emit("tab_switch", { dst_idx - 1 })
    -- Route through merge-paste instead of the bare "paste" command: plain
    -- paste silently auto-renames on a name collision, which is how F5/F6
    -- worked before this change. merge-paste asks Overwrite / Merge folders
    -- / Skip / Rename / Cancel per conflict (same prompt Shift+Insert already
    -- gives you), which is what F5/F6 are expected to do too. Its ya.which()
    -- prompt is an async, blocking-on-input call -- the tab_switch back to
    -- src_pane right below fires immediately regardless (this emit is
    -- fire-and-forget, same as the old "paste" call was), so on a conflict
    -- the view may flip back to src while the prompt is still up. The
    -- prompt itself still renders and captures the keypress correctly; it's
    -- a cosmetic wrinkle, not a functional one -- worth revisiting if it
    -- turns out to be more than that in practice.
    ya.emit("plugin", { "merge-paste" })
    ya.emit("tab_switch", { src_idx - 1 })
    -- paste queues a background task and returns at once. By the time the
    -- tab_switch above returns us to the source pane, the destination is no
    -- longer the active tab, and this composited dual-pane view -- unlike
    -- core yazi's single-pane redraw -- does not repaint on background task
    -- completion for a tab that is not active.
    --
    -- A single immediate ui.render() only catches transfers that finish
    -- before this line runs -- true for a quick local copy of a few small
    -- files, false the moment the task takes any real time, or (in FAR
    -- mode, where F5/F6 route through far-mode's far_copy/far_move, which
    -- re-emits into this same function via an extra async "plugin" hop
    -- before ever reaching this line) almost always false. There is no
    -- single point in time guaranteed to be "after the task landed," so
    -- poll with real delays instead -- same ya.async + pcall(ui.render)
    -- pattern far-mode.yazi already uses for its mode-indicator chip.
    -- Six renders over 1.5s covers typical local transfers; anything
    -- slower still shows correctly once the user switches into the
    -- destination pane manually, same fallback as before this fix.
    ui.render()
    ya.async(function()
        for _ = 1, 6 do
            ya.sleep(0.25)
            pcall(ui.render)
        end
    end)
end

local function spl_copy()
    spl_transfer("copy")
end

local function spl_move()
    spl_transfer("move")
end

-- Shift+Y in vim mode: move to the other pane when dual-pane is active,
-- same as F6/spl_move. "Y" is otherwise bound to unyank (cancel yank
-- status) -- when dual-pane is off there's nothing to transfer to, so fall
-- back to that native behavior instead of silently doing nothing. (FAR mode
-- always has dual-pane on, so it binds straight to spl_move with no need
-- for this fallback -- see keymap-far.toml.) "X" duplicates unyank too, so
-- it stays reachable either way.
local function spl_move_or_unyank()
    if dp then
        spl_transfer("move")
    else
        ya.emit("unyank", {})
    end
end

local function entry(st, job)
    job = type(job) == "string" and { args = { job } } or job
    local act = job and job.args and job.args[1]

    if act == "spl_activate" then
        spl_activate()
    elseif act == "spl_deactivate" then
        spl_deactivate()
    elseif act == "spl_toggle" then
        spl_toggle()
    elseif act == "spl_switch_tab" then
        spl_switch_tab()
    elseif act == "spl_copy" then
        spl_copy()
    elseif act == "spl_move" then
        spl_move()
    elseif act == "spl_move_or_unyank" then
        spl_move_or_unyank()
    elseif act == "spl_preview" then
        spl_preview()
    end
end

-- ===================== local addition to upstream 00c3084 =====================
-- Everything above this line is upstream, unmodified. The block below is the
-- ONLY local change: a read-only state getter, published both as a module
-- export and as a plain global.
--
-- Why it is needed: far-mode.yazi gates its pane operations on dual_state(),
-- which reads `SPLIT_TABS.state`. Without this, that check is permanently
-- false, and FAR mode's <Tab> (switch pane), copy and move each re-emit
-- themselves 40 times waiting for a dual-pane that they cannot observe, then
-- give up silently -- the keys simply stop working.
--
-- It must be a global, not a require(): far-mode reads it from a @sync entry,
-- and a cross-plugin require() yields, which a @sync entry cannot do. Both
-- plugins' entries share one sync Lua state, so a global reaches the live
-- `dp` upvalue. If yazi ever sandboxes plugin globals this reads back nil,
-- which far-mode already treats as "dual-pane off" -- degraded, not broken.
--
-- NOTE for anyone rebuilding the workspace layer on top of this: upstream's
-- dp.tabs holds tab POSITION INDICES (integers), not the tab id objects the
-- later workspaces version used. far-mode's capture handles both, but keep
-- the distinction in mind -- conflating them is what silently destroyed the
-- saved layout on every mode switch.
local function state()
    if not dp then return nil end
    return { tabs = dp.tabs, pane = dp.pane, preview = dp.preview }
end

SPLIT_TABS = SPLIT_TABS or {}
SPLIT_TABS.state = state

return { entry = entry, state = state }
