-- ai_chat/utils/window.lua
-- Helpers for creating floating windows.

local M = {}

--- Create a centred floating window.
---@param opts { width?:number, height?:number, title?:string, border?:string }
---@return number bufnr, number winnr
function M.open_float(opts)
  opts = opts or {}
  local width  = opts.width  or math.floor(vim.o.columns * 0.6)
  local height = opts.height or math.floor(vim.o.lines   * 0.4)
  local row    = math.floor((vim.o.lines   - height) / 2)
  local col    = math.floor((vim.o.columns - width)  / 2)

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].bufhidden = "wipe"

  local winnr = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width    = width,
    height   = height,
    row      = row,
    col      = col,
    style    = "minimal",
    border   = opts.border or "rounded",
    title    = opts.title and (" " .. opts.title .. " ") or nil,
    title_pos = opts.title and "center" or nil,
  })

  return bufnr, winnr
end

--- Close a floating window safely.
---@param winnr number
function M.close_float(winnr)
  if winnr and vim.api.nvim_win_is_valid(winnr) then
    vim.api.nvim_win_close(winnr, true)
  end
end

return M