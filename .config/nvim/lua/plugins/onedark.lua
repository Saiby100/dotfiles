return {
	"navarasu/onedark.nvim",
	lazy = false,
	priority = 1000,
	config = function()
		require("onedark").setup({
			style = "dark",
		})
		require("onedark").load()

		-- Split borders in the same colour tmux draws around inactive panes
		-- (pane-border-style @border), so a tmux split and a Neovim split are
		-- one continuous grid rather than two different frames.
		vim.api.nvim_set_hl(0, "WinSeparator", { fg = "#324456" })
	end,
}
