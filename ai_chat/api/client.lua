local M        = {}
local config   = require("chatforge.config")
local state    = require("chatforge.core.state")
local backends = require("chatforge.api.backends")
local log      = require("chatforge.utils.logger")

--- Send messages to whatever backend the buffer has selected.
---@param src_bufnr number          source (non-chat) buffer
---@param messages  {role:string, content:string}[]
---@param on_done   fun(text:string|nil, err:string|nil)
function M.complete(src_bufnr, messages, on_done)
  if state.loading then
    on_done(nil, "A request is already in progress.")
    return
  end

  local cfg   = config.values
  local model = state.get_model(src_bufnr)
  local be    = backends.get("ollama")  -- only backend for now

  if not be then
    on_done(nil, "Backend 'ollama' not found.")
    return
  end

  -- Prepend system prompt
  local full = {}
  if cfg.system_prompt ~= "" then
    table.insert(full, { role = "system", content = cfg.system_prompt })
  end
  for _, m in ipairs(messages) do table.insert(full, m) end

  state.loading = true
  log.log("client.complete: model=%s msgs=%d", model, #full)

  be.ask(cfg.ollama_url, model, full, function(text, err)
    state.loading = false
    on_done(text, err)
  end)
end

return M
