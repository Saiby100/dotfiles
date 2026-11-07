return {
	"windwp/nvim-autopairs",
	event = "InsertEnter",
	config = function()
		local autopairs = require("nvim-autopairs")
		autopairs.setup({
			check_ts = true, -- use treesitter to skip pairing inside strings/comments
		})

		-- Add "()" after confirming a function/method completion in nvim-cmp.
		local ok, cmp = pcall(require, "cmp")
		if ok then
			cmp.event:on("confirm_done", require("nvim-autopairs.completion.cmp").on_confirm_done())
		end
	end,
}
