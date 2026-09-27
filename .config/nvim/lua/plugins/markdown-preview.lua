return {
	"iamcco/markdown-preview.nvim",
	build = "cd app && npm install",
	ft = { "markdown" },
	init = function()
		vim.g.mkdp_filetypes = { "markdown" }
		-- Setting this replaces the plugin's defaults wholesale, so restate them
		-- and only turn off scroll sync with the Neovim cursor.
		vim.g.mkdp_preview_options = {
			mkit = vim.empty_dict(),
			katex = vim.empty_dict(),
			uml = vim.empty_dict(),
			maid = vim.empty_dict(),
			disable_sync_scroll = 1,
			sync_scroll_type = "middle",
			hide_yaml_meta = 1,
			sequence_diagrams = vim.empty_dict(),
			flowchart_diagrams = vim.empty_dict(),
			content_editable = false,
			disable_filename = 0,
			toc = vim.empty_dict(),
		}
	end,
	keys = {
		{ "<leader>p", ":MarkdownPreview<CR>", desc = "Markdown Preview" },
	},
}
