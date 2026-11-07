local prettier_configs = {
  ".prettierrc", ".prettierrc.json", ".prettierrc.yml", ".prettierrc.yaml",
  ".prettierrc.js", ".prettierrc.cjs", ".prettierrc.mjs",
  "prettier.config.js", "prettier.config.cjs", "prettier.config.mjs",
  ".prettierrc.toml",
}

local function has_prettier_config(dirname)
  if vim.fs.find(prettier_configs, { upward = true, path = dirname })[1] then
    return true
  end
  -- also honor a "prettier" key inside package.json
  local pkg = vim.fs.find({ "package.json" }, { upward = true, path = dirname })[1]
  if pkg then
    local ok, lines = pcall(vim.fn.readfile, pkg)
    if ok then
      for _, line in ipairs(lines) do
        if line:match('"prettier"%s*:') then return true end
      end
    end
  end
  return false
end

return {
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    opts = {
      formatters_by_ft = {
        javascript        = { "prettier" },
        javascriptreact   = { "prettier" },
        typescript        = { "prettier" },
        typescriptreact   = { "prettier" },
        vue               = { "prettier" },
        svelte            = { "prettier" },
        html              = { "prettier" },
        css               = { "prettier" },
        scss              = { "prettier" },
        less              = { "prettier" },
        json              = { "prettier" },
        jsonc             = { "prettier" },
        yaml              = { "prettier" },
        markdown          = { "prettier" },
        graphql           = { "prettier" },
        dart              = { "dart_format" }
      },
      formatters = {
        prettier = {
          require_cwd = false,
          -- prettier can't infer a parser from the .njk extension, so force
          -- the yaml parser for *.yaml.njk files (filetype is yaml via
          -- vim.filetype.add, so conform already routes them to prettier).
          options = {
            ext_parsers = {
              njk = "yaml",
            },
          },
        },
      },
      format_on_save = {
        timeout_ms = 3000,
        lsp_format = "never",
      },
    },
  },

  -- Auto-install prettier (and keep it up to date) via Mason
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "williamboman/mason.nvim" },
    event = "VeryLazy",
    opts = {
      ensure_installed = { "prettier" },
      auto_update = false,
      run_on_start = true,
    },
  },
}
