local M = {}

--- Returns all lines from the given buffer (default: current).
---@param bufnr? number
---@return string
function M.get_content(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n")
end

--- Returns the visually selected text (works after leaving visual mode).
---@return string
function M.get_visual_selection()
  local _, ls, cs = unpack(vim.fn.getpos("'<"))
  local _, le, ce = unpack(vim.fn.getpos("'>"))
  local lines = vim.api.nvim_buf_get_lines(0, ls - 1, le, false)
  if #lines == 0 then return "" end
  -- Trim to exact column range
  lines[#lines] = lines[#lines]:sub(1, ce)
  lines[1]      = lines[1]:sub(cs)
  return table.concat(lines, "\n")
end

--- Returns the name / path of the given buffer.
---@param bufnr? number
---@return string
function M.get_name(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return vim.api.nvim_buf_get_name(bufnr)
end

--- Returns the filetype of the given buffer.
---@param bufnr? number
---@return string
function M.get_filetype(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return vim.bo[bufnr].filetype
end

return M