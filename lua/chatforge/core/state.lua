local M = {}

---@type table<number, { model:string, history:{role:string,content:string,display:string|nil}[] }>
M.buffers = {}

M.chat_bufnr    = nil  ---@type number|nil
M.chat_winnr    = nil  ---@type number|nil
M.input_bufnr   = nil  ---@type number|nil
M.input_winnr   = nil  ---@type number|nil
M.source_bufnr  = nil  ---@type number|nil
M.source_winnr  = nil  ---@type number|nil
M.chat_source_bufnr = nil  ---@type number|nil
M.input_lines = { "" }
M.chat_lines = {}
M.chat_spans = {}
M.chat_entries = {}
M.last_status_entry = nil
M.render_ns = vim.api.nvim_create_namespace("chatforge_chat_render")
M.loading       = false
M.request_id    = 0
M.applying      = false
M.edit_target   = nil  ---@type {bufnr:number,line1:number,line2:number,kind:string}|nil
M.pending_blocks = {}  ---@type {lang:string,content:string,applied:boolean,target:table|nil}[]
M.staged_changes = {}  ---@type table<number, table>
M.streaming_change = nil
M.ollama_job = nil
M.ollama_pull_job = nil
M.ollama_job_stopping = false
M.ollama_pull_job_stopping = false

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

function M.append_message(bufnr, role, content, display)
  table.insert(M.get_buf(bufnr).history, { role = role, content = content, display = display })
end

function M.clear(bufnr)
  if M.buffers[bufnr] then M.buffers[bufnr].history = {} end
  M.pending_blocks = {}
  M.staged_changes = {}
  M.edit_target = nil
  M.last_status_entry = nil
end

function M.chat_is_open()
  return M.chat_bufnr ~= nil
    and vim.api.nvim_buf_is_valid(M.chat_bufnr)
    and M.chat_winnr ~= nil
    and vim.api.nvim_win_is_valid(M.chat_winnr)
    and vim.api.nvim_win_get_buf(M.chat_winnr) == M.chat_bufnr
end

function M.input_is_open()
  return M.chat_is_open()
    and M.input_bufnr ~= nil
    and vim.api.nvim_buf_is_valid(M.input_bufnr)
    and M.input_winnr ~= nil
    and vim.api.nvim_win_is_valid(M.input_winnr)
    and vim.api.nvim_win_get_buf(M.input_winnr) == M.input_bufnr
end

function M.is_plugin_buf(bufnr)
  return bufnr == M.chat_bufnr or bufnr == M.input_bufnr
end

return M
