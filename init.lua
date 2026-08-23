
-- Какое приложение чем открывать (Enter / l).
-- Штатный [opener] в yazi.toml тут не работает (см. комментарий в
-- plugins/smart-enter.yazi/main.lua) — Enter/l открывает файлы через
-- список из plugins/openers.yazi/main.lua. Чтобы поменять программу для
-- типа файлов, жми F в файловом менеджере (всплывающее окно: a — добавить,
-- e/Enter — изменить программу, d/x — удалить) — редактировать файлы руками
-- не нужно. `editor` ниже — чем открывать всё, что не попало ни в одно
-- правило из этого окна.
require("smart-enter"):setup {
	editor = "nvim",
}

-- zip
require("relative-motions"):setup({ show_numbers="relative", show_motion = true, enter_mode ="first" })




-- чёто для миниатюр фото 
 require("allmytoes"):setup {
    -- By default, all sizes are generated. Remove the ones you don't need.
    sizes = {"n", "l", "x", "xx"},
}
require("full-border"):setup()


--tresh
require("recycle-bin"):setup({
  -- Optional: Override automatic trash directory discovery
  -- trash_dir = "~/.local/share/Trash/",  -- Uncomment to use specific directory
})

--zoxide
require("zoxide"):setup {
	update_db = true,
}

-- git status в списке файлов
require("git"):setup {
	order = 1500,
}

-- телефон через KDE Connect: просмотр (g p) и отправка (c s), свой модуль
-- вместо kdeconnect-send.yazi — умеет и то, и другое через kdeconnect-cli
require("kdeconnect"):setup {
	auto_select_single = true,
}

-- быстрый undo последнего удаления (u / U), напарник recycle-bin
require("restore"):setup {
	show_confirm = true,
	suppress_success_notification = false,
}


-- ===== PHASE 0 TEST ONLY =====
-- DISABLED (incompatible): require("dual-pane"):setup()

-- split-tabs: preload here so the module (and its SPLIT_TABS global) exists
-- before far-mode's restore runs. Lazily loading it on the first `plugin
-- split-tabs ...` command costs a disk read, which lets that command land out
-- of order during startup restore.
require("split-tabs")

-- far-menu: F2 user menu / F9 main menu / F11 plugin commands.
-- setup() with no arguments just keeps the built-in lists; pass tables
-- here (user = {...}, main = {...}) to override them.
require("far-menu"):setup()

-- far-mode: restore tab/cwd layout after a mode-swap relaunch, if any
require("far-mode"):setup()
