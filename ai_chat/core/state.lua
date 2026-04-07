local M = {}

---@type table<number, { model:string, history:{role:string,content:string}[] }>
M.buffers = {}

M.chat_bufnr    = nil  ---@type number|nil
M.chat_winnr    = nil  ---@type number|nil
M.loading       = false
M.pending_blocks = {}  ---@type {lang:string,content:string,applied:boolean}[]

local config
local function default_model()
  config = config or require("chatforge.config")
  return config.values.default_model
end

function M.get_buf(bufnr)
  if not M.buffers[bufnr] then
    M.buffers[bufnr] = { model = default_model(), history = {} }
  end
  return M.buffers[bufnr]
end

function M.get_model(bufnr)   return M.get_buf(bufnr).model end
function M.set_model(bufnr, model) M.get_buf(bufnr).model = model end

function M.append_message(bufnr, role, content)
  table.insert(M.get_buf(bufnr).history, { role = role, content = content })
end

function M.clear(bufnr)
  if M.buffers[bufnr] then M.buffers[bufnr].history = {} end
  M.pending_blocks = {}
end

function M.chat_is_open()
  return M.chat_bufnr ~= nil
    and vim.api.nvim_buf_is_valid(M.chat_bufnr)
    and M.chat_winnr ~= nil
    and vim.api.nvim_win_is_valid(M.chat_winnr)
end

return M