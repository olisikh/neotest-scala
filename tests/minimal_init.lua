--- Minimal Neovim init for running tests with plenary.busted.
---
--- Prerequisites:
---   1. plenary.nvim must be installed and on runtimepath
---   2. tree-sitter-scala grammar must be installed (`:TSInstall scala`)
---
--- Usage (from project root):
---   nvim --headless --clean -u tests/minimal_init.lua \
---     -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

local root = vim.fn.getcwd()

-- Add the plugin itself to runtimepath
vim.opt.runtimepath:prepend(root)

-- Add project root to Lua package.path so require('tests.helpers') works
package.path = root .. '/?.lua;'
  .. root .. '/?/init.lua;'
  .. package.path

-- Try to find plenary.nvim in common locations
local dep_paths = {
  -- lazy.nvim
  vim.fn.stdpath('data') .. '/lazy/plenary.nvim',
  vim.fn.stdpath('data') .. '/lazy/nvim-treesitter',
  -- packer
  vim.fn.stdpath('data') .. '/site/pack/packer/start/plenary.nvim',
  vim.fn.stdpath('data') .. '/site/pack/packer/start/nvim-treesitter',
  -- manual / other
  vim.fn.expand('~/.local/share/nvim/site/pack/vendor/start/plenary.nvim'),
  vim.fn.expand('~/.local/share/nvim/site/pack/vendor/start/nvim-treesitter'),
  -- nix
  vim.fn.stdpath('data') .. '/site/pack/myNeovimPackages/start/plenary.nvim',
  vim.fn.stdpath('data') .. '/site/pack/myNeovimPackages/start/nvim-treesitter',
}

for _, p in ipairs(dep_paths) do
  if vim.fn.isdirectory(p) == 1 then
    vim.opt.runtimepath:prepend(p)
  end
end

-- Also scan the runtimepath for any pack/*/start/* directories, since nix
-- may install plugins with non-standard pack group names
local site = vim.fn.stdpath('data') .. '/site/pack'
if vim.fn.isdirectory(site) == 1 then
  for _, group_dir in ipairs(vim.fn.readdir(site)) do
    local start_dir = site .. '/' .. group_dir .. '/start'
    if vim.fn.isdirectory(start_dir) == 1 then
      for _, plugin_dir in ipairs(vim.fn.readdir(start_dir)) do
        local full = start_dir .. '/' .. plugin_dir
        vim.opt.runtimepath:append(full)
      end
    end
  end
end

-- Mock neotest.lib for tests
local neotest_lib_files = {
  read_lines = function(path)
    local lines = {}
    for line in io.lines(path) do
      table.insert(lines, line)
    end
    return lines
  end,
  match_root_pattern = function(...)
    return function(path)
      return vim.fn.getcwd()
    end
  end,
}

package.loaded["neotest.lib"] = {
  files = neotest_lib_files,
}

package.loaded["neotest.lib.files"] = neotest_lib_files

-- Minimal settings
vim.o.swapfile = false
vim.o.backup = false
vim.o.writebackup = false
