local plugins = {
  { "uhs-robert/oasis.nvim", lazy = false, priority = 1000, opts = { style = "night" } },
  { "LazyVim/LazyVim", opts = { colorscheme = "oasis-night" } },
  { "folke/snacks.nvim", opts = {
    dashboard = { enabled = false },
    indent = { enabled = false },
    scope = { enabled = false },
    animate = { enabled = false },
    scroll = { enabled = false },
    picker = { previewers = { file = { win = { wo = { wrap = false } } } } },
  } },
}
-- Keep LazyVim navigation, keymaps, which-key, Git UI, and basic editing.
-- Use built-in syntax highlighting and completion; never install language tools.
for _, name in ipairs({
  "folke/tokyonight.nvim", "catppuccin/nvim", "MunifTanjim/nui.nvim",
  "mason-org/mason.nvim", "mason-org/mason-lspconfig.nvim", "neovim/nvim-lspconfig",
  "stevearc/conform.nvim", "mfussenegger/nvim-lint", "folke/lazydev.nvim",
  "saghen/blink.cmp", "rafamadriz/friendly-snippets",
  "nvim-treesitter/nvim-treesitter", "nvim-treesitter/nvim-treesitter-textobjects",
  "windwp/nvim-ts-autotag", "folke/ts-comments.nvim", "nvim-mini/mini.ai",
  "folke/noice.nvim", "folke/flash.nvim", "folke/trouble.nvim",
  "folke/todo-comments.nvim", "MagicDuck/grug-far.nvim",
}) do
  plugins[#plugins + 1] = { name, enabled = false }
end
return plugins
