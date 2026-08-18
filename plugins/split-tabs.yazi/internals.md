# split-tabs.yazi — Internals

This document describes the architecture and design decisions of the plugin, along with the relevant yazi framework internals that make it work.

## Yazi Component Model

Yazi's UI is built on a Lua component tree rendered via [ratatui](https://github.com/ratatui/ratatui). Each component is a Lua table with:

- **`_id`** — a string identifier (e.g. `"current"`, `"preview"`, `"progress"`). Used by the framework to update the global `LAYOUT` singleton.
- **`_area`** — a `ui.Rect { x, y, w, h }` describing the component's screen region.
- **`reflow()`** — returns a flat list of components for layout recalculation (used on resize).
- **`redraw()`** — returns a list of renderable elements (`ui.Text`, `ui.List`, `ui.Border`, etc.).

### Component Hierarchy (stock yazi)

```
Root
├── Header    (_id = "header")
├── Tabs      (_id = "tabs")
├── Tab       (_id = "tab")
│   ├── Parent   (_id = "parent")
│   ├── Current  (_id = "current")
│   ├── Preview  (_id = "preview")
│   └── Rail     (_id = "rail")
│       ├── Marker
│       └── Marker
├── Status    (_id = "status")
└── Modal     (_id = "modal")
```

### Lifecycle

1. **`Component:new(area, ...)`** — constructor. Calls `self:layout()` then `self:build()`.
2. **`layout()`** — splits `self._area` into `self._chunks` (an array of sub-rects).
3. **`build()`** — creates `self._children` from `self._chunks`.
4. **`reflow()`** — recursively collects `{ self, ...children:reflow() }`. Called on terminal resize.
5. **`redraw()`** — recursively renders children via `ui.redraw(child)`. Called every frame.

## LAYOUT Singleton

`LAYOUT` is a global Rust struct (`yazi_config::LAYOUT`) with three fields:

```rust
struct Layout {
    current:  Rect,  // area of the "current" file list
    preview:  Rect,  // area of the preview pane
    progress: Rect,  // area of the progress indicator
}
```

It is updated in two places:

1. **Reflow** (`yazi-actor/src/app/reflow.rs`) — iterates the flat component list from `Root:reflow()`, reads `_id` and `_area` from each, and updates matching LAYOUT fields. If LAYOUT changed, triggers `render!()`.
2. **Redraw** (`ui.redraw()` in `yazi-plugin/src/elements/elements.rs`) — called for each child during `Root:redraw()`. Reads `_id`/`_area` and updates LAYOUT before calling the component's `redraw()`.

### Why LAYOUT Matters

- **`mgr::Preview` widget** (Rust) only renders when `lock.area == LAYOUT.preview`. This is how stale preview content is prevented.
- **`Folder::make`** uses `LAYOUT.preview.height` as the window size for file lists. Zero height = empty window.
- **`PeekJob`** gets its area from `LAYOUT.preview` at job creation time.

## Render Pipeline

```
Event (resize, keypress, etc.)
  → drain_events macro
    → checks NEED_RENDER flag
      → App::render()
        → Root::new(area)  [Rust Widget]
          → Root:new(area)  [Lua: layout() + build()]
            → Root:redraw()
              → ui.redraw(child) for each child
                → updates LAYOUT from _id/_area
                → calls child:redraw()
        → mgr::Preview widget renders AFTER Lua tree
        → if LAYOUT.preview changed during draw → re-trigger peek
```

### Reflow Pipeline (terminal resize)

```
Event::Resize
  → dispatch_resize()
    → Reflow::act()
      → Root:new(new_area) → Root:reflow()
        → flat list of all components
      → update LAYOUT from _id/_area of each component
      → if LAYOUT changed → render!()
    → act!(mgr:peek) to re-evaluate preview
```

**Critical**: every component in `Tab._children` must have a `reflow()` method. If any child lacks it, `Tab:reflow()` throws a Lua error that silently kills the reflow pipeline — LAYOUT never updates, `render!()` is never called, and the UI freezes at the old size.

## Plugin Architecture

### Monkey-Patching Strategy

The plugin saves original methods and replaces them with patched versions:

| Method | Purpose |
|--------|---------|
| `Tab.layout` | Replaces 3-slot parent/current/preview with 2-pane layout |
| `Tab.build` | Replaces children with two Current components + Markers |
| `Header.cwd` | Shows both pane paths side by side |
| `Tabs.height` | Returns 0 to hide the tab bar |
| `Entity.style` | Suppresses cursor highlight in the inactive pane |

All originals are stored in `saved` and restored on deactivate.

### State (`dp` table)

```lua
dp = {
    pane = 1|2,           -- which pane is currently focused
    tabs = { idx1, idx2 }, -- 1-based tab indices for each pane
    preview = bool,        -- whether preview panel is visible
    preview_area = Rect,   -- bottom-half rect when preview is on
    creating = bool,       -- guard to prevent recursive tab creation
    _no_cursor = bool,     -- transient flag during inactive pane redraw
}
```

### Tab Layout (patched)

Stock yazi splits the tab area into 3 horizontal slots: `[parent, current, preview]` using ratio constraints. The plugin replaces this:

**Dual-pane (no preview):**
- Pane 1 active: `[Length(0), Fill(1), Fill(1)]` — hides parent slot, both panes fill equally.
- Pane 2 active: `[Fill(1), Fill(1), Length(0)]` — hides preview slot.

**Dual-pane with preview:**
1. First split `self._area` vertically: `[Fill(1), Fill(1)]` → top half for panes, bottom half for preview.
2. Then split the top half horizontally as above.

### Tab Build (patched)

1. Temporarily shrinks `self._area` to the pane region (so the original build's borders don't bleed into the preview area).
2. Calls `saved.tab_build(self)` to draw borders and set up `self._base` (e.g. from `full-border.yazi`).
3. Restores `self._area`.
4. Replaces `self._children` with:
   - `Current:new(slot, active_tab)` — active pane, normal cursor.
   - `Inactive:new(Current:new(slot, inactive_tab))` — inactive pane, no cursor highlight.
   - `Marker:new(slot, folder)` — selection/yank markers for each pane.
5. Appends preview or a zero-width "preview" Overlay.

### Custom Components

#### `Overlay`
A minimal component for rendering static elements (borders, clear rects). Has `_id` and `_area` so `ui.redraw()` can process it. Returns `{}` from `reflow()` to avoid participating in the layout recalculation — its area is managed externally.

#### `Inactive`
A wrapper that sets `dp._no_cursor = true` during its inner component's `redraw()`. The patched `Entity.style()` checks this flag and returns the base file style without any cursor indicator, effectively removing the highlight from the hovered file in the inactive pane.

### Marker Polyfill

In stock yazi, `Marker` lives inside `Rail`, and `Rail:reflow()` returns `{}` — so Marker never needs its own `reflow()`. The plugin places Markers directly in `Tab._children`, where `Tab:reflow()` calls `child:reflow()` on every child. Without the polyfill (`Marker.reflow = function() return {} end`), the reflow crashes on terminal resize.

### Preview Panel

When the preview is toggled on:
- The layout splits vertically (50/50) before the horizontal pane split.
- A `Preview:new(area, self._tab)` component is added, which triggers yazi's native peek system.
- The preview border overlaps 1 row up (`y - 1, h + 1`) and draws only `LEFT + RIGHT + BOTTOM` edges, sharing the pane's bottom border line for a seamless appearance.

When the preview is toggled off:
- An `Overlay` with `_id = "preview"` and a zero-width rect is added. During `ui.redraw()`, this sets `LAYOUT.preview` to the zero-width rect, which causes the Rust `mgr::Preview` guard (`lock.area != LAYOUT.preview`) to block stale content.
- The height is kept non-zero (`self._area.h`) because `Folder::make` uses `LAYOUT.preview.height` as a window size — zero height would produce "No items" in file lists.
- `ya.emit("peek", { 99999 })` is called with a large skip value to force the peek system to call `preview.reset()`, which clears terminal protocol images (kitty graphics, sixel). The different skip value bypasses the "same file + same skip" deduplication check in the peek handler.

### Header Patch

Replaces `Header.cwd` to show both pane paths:
- Left path is truncated and space-padded to exactly `mid` columns so the separator aligns with the pane split.
- Right path fills the remaining space.
- Active path uses `th.tabs.active` style; inactive uses `th.tabs.inactive` (both with `bg("reset")` to avoid full-width background bars).

### Rendering

The plugin uses `ui.render()` (sets `NEED_RENDER` flag) to trigger re-renders after state changes. `ya.emit()` is used for async actions like tab creation/closing and peek triggers — these are queued as events and processed in the event loop after the plugin returns.
