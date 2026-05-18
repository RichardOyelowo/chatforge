local M        = {}
local config   = require("chatforge.config")
local state    = require("chatforge.core.state")
local backends = require("chatforge.api.backends")
local log      = require("chatforge.utils.logger")
local backend_control = require("chatforge.api.backend_control")

--- Send messages to whatever backend the buffer has selected.
---@param src_bufnr number          source (non-chat) buffer
---@param messages  {role:string, content:string}[]
---@param on_done   fun(text:string|nil, err:string|nil)
---@param request_id number|nil
---@param opts table|nil
function M.complete(src_bufnr, messages, on_done, request_id, opts)
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

  opts = vim.tbl_deep_extend("force", {
    temperature = cfg.temperature,
    max_output_tokens = cfg.max_output_tokens or cfg.max_tokens,
    context_tokens = cfg.context_tokens,
  }, opts or {})

  be.ask(cfg.ollama_url, model, full, function(text, err)
    if request_id and request_id ~= state.request_id then
      return
    end
    state.loading = false
    if err and err:match("Ollama unreachable") then
      backend_control.offer_ollama_start(err)
    elseif err and (err:lower():match("model") and (err:lower():match("not found") or err:lower():match("pull"))) then
      backend_control.offer_model_pull(model, err)
    end
    on_done(text, err)
  end, opts)
end

return M
