return {
	{
		"williamboman/mason.nvim",
		lazy = false,
		opts = {},
	},

	-- LSP server configs + bridge to mason. nvim-lspconfig ships the
	-- `lsp/<server>.lua` definitions (cmd/filetypes/root_markers) that
	-- vim.lsp.enable() reads; without it the servers never start.
	{
		"neovim/nvim-lspconfig",
		lazy = false,
		dependencies = {
			"williamboman/mason.nvim",
			"williamboman/mason-lspconfig.nvim",
			"hrsh7th/cmp-nvim-lsp",
		},
		config = function()
			require("mason-lspconfig").setup({
				ensure_installed = {
					"ts_ls",
					"lua_ls",
					"html",
					"cssls",
					"jsonls",
					"yamlls",
					"bashls",
				},
				automatic_enable = false,
			})

			-- Advertise nvim-cmp's completion capabilities to every server.
			local capabilities = require("cmp_nvim_lsp").default_capabilities()
			vim.lsp.config("*", { capabilities = capabilities })

			-- Server-specific config
			vim.lsp.config("lua_ls", {
				settings = {
					Lua = {
						diagnostics = { globals = { "vim" } },
						workspace = { checkThirdParty = false },
					},
				},
			})

			vim.lsp.config("ts_ls", {
				init_options = {
					preferences = {
						includeCompletionsForModuleExports = true,
						includeCompletionsForImportStatements = true,
						includeCompletionsWithSnippetText = true,
						includeAutomaticOptionalChainCompletions = true,
					},
				},
				settings = {
					typescript = {
						suggest = { completeFunctionCalls = true },
						inlayHints = {
							includeInlayParameterNameHints = "all",
							includeInlayFunctionParameterTypeHints = true,
							includeInlayVariableTypeHints = true,
						},
					},
					javascript = {
						suggest = { completeFunctionCalls = true },
					},
				},
			})

			-- Diagnostics
			vim.diagnostic.config({
				virtual_text = true,
				signs = true,
				underline = true,
				update_in_insert = false,
				severity_sort = true,
			})

			-- Keymaps on LSP attach
			vim.api.nvim_create_autocmd("LspAttach", {
				callback = function(ev)
					local opts = { buffer = ev.buf, silent = true }
					vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
					vim.keymap.set("n", "<leader>d", vim.lsp.buf.definition, opts)
					vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
					vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
					vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
					vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
					vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
					vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
					vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
					vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
					vim.keymap.set("n", "<leader>cd", vim.diagnostic.open_float, opts)
				end,
			})

			-- Start the installed servers
			vim.lsp.enable({ "ts_ls", "lua_ls", "html", "cssls", "jsonls", "yamlls", "bashls", "dartls" })
		end,
	},

	{
		"hrsh7th/nvim-cmp",
		event = "InsertEnter",
		dependencies = {
			"hrsh7th/cmp-nvim-lsp",
			"hrsh7th/cmp-buffer",
			"hrsh7th/cmp-path",
			"saadparwaiz1/cmp_luasnip",
			"L3MON4D3/LuaSnip",
			"rafamadriz/friendly-snippets",
		},
		config = function()
			local cmp = require("cmp")
			local luasnip = require("luasnip")
			require("luasnip.loaders.from_vscode").lazy_load()

			vim.opt.completeopt = { "menu", "menuone", "noselect" }

			cmp.setup({
				snippet = {
					expand = function(args) luasnip.lsp_expand(args.body) end,
				},
				completion = {
					completeopt = "menu,menuone,noinsert",
				},
				window = {
					completion = cmp.config.window.bordered(),
					documentation = cmp.config.window.bordered(),
				},
				mapping = cmp.mapping.preset.insert({
					["<C-k>"]     = cmp.mapping.select_prev_item(),
					["<C-j>"]     = cmp.mapping.select_next_item(),
					["<C-Space>"] = cmp.mapping.complete(),
					["<C-e>"]     = cmp.mapping.abort(),
					-- Smart Tab: confirm the cmp menu if open, else accept a
					-- Copilot ghost suggestion if one is showing, else plain tab.
					-- Only whitespace before the cursor means you're indenting, so
					-- Copilot is skipped there (accept it with <M-l> instead).
					["<Tab>"]     = cmp.mapping(function(fallback)
						local ok, copilot = pcall(require, "copilot.suggestion")
						local col = vim.api.nvim_win_get_cursor(0)[2]
						local only_indent = vim.api.nvim_get_current_line():sub(1, col):match("^%s*$") ~= nil
						if cmp.visible() then
							cmp.confirm({ select = true })
						elseif ok and copilot.is_visible() and not only_indent then
							copilot.accept()
						else
							fallback()
						end
					end, { "i", "s" }),
				}),
				sources = cmp.config.sources({
					{ name = "nvim_lsp" },
					{ name = "luasnip", keyword_length = 2 },
					{ name = "path" },
				}, {
					{ name = "buffer", keyword_length = 3 },
				}),
			})
		end,
	},
}
