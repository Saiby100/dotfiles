vim.o.termguicolors = true

vim.g.mapleader = " "

-- Options
vim.opt.number = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.autoindent = true
vim.opt.mouse = "a"
vim.opt.textwidth = 80
vim.opt.clipboard = "unnamedplus" -- use system clipboard
vim.opt.scrolloff = 8
vim.opt.smoothscroll = true       -- scroll wrapped lines one screen row at a time
vim.opt.incsearch = true
vim.opt.hlsearch = true
vim.opt.fixendofline = true       -- insertFinalNewline
vim.opt.fillchars = { eob = ' ' }
vim.opt.pumheight = 10            -- max items shown in completion popup; rest scroll
vim.opt.autoread = true
