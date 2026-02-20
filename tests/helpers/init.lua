local H = {}

local _mocks = {}

function H.mk_buf(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  if type(lines) == 'string' then
    lines = vim.split(lines, '\n', { plain = true })
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

function H.cleanup_buf(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

function H.mock_fn(module, fn_name, return_fn)
  local mod = package.loaded[module] or require(module)
  if not _mocks[module] then
    _mocks[module] = {}
  end
  _mocks[module][fn_name] = mod[fn_name]
  mod[fn_name] = return_fn
end

function H.restore_mocks()
  for module, fns in pairs(_mocks) do
    local mod = package.loaded[module]
    if mod then
      for fn_name, original in pairs(fns) do
        mod[fn_name] = original
      end
    end
  end
  _mocks = {}
end

function H.assert_eq(actual, expected, msg)
  msg = msg or 'assertion failed'
  assert(actual == expected, msg .. ': expected ' .. vim.inspect(expected) .. ', got ' .. vim.inspect(actual))
end

return H
