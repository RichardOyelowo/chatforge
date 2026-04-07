local M   = {}
local log = require("chatforge.utils.logger")

-- ── Ollama ─────────────────────────────────────────────────────────────────

local ollama = {}

function ollama.ask(base_url, model, messages, on_done)
  local body = vim.json.encode({
    model    = model,
    messages = messages,
    stream   = false,
  })

  local url = base_url .. "/api/chat"
  log.log("ollama → POST %s  model=%s  msgs=%d", url, model, #messages)

  vim.system(
    {
      "curl", "--silent", "--no-buffer",
      "-X", "POST", url,
      "-H", "Content-Type: application/json",
      "-d", body,
    },
    { text = true },
    function(result)
      if result.code ~= 0 then
        local msg = result.stderr ~= "" and result.stderr
                    or ("curl exit " .. result.code)
        log.err("ollama curl failed: %s", msg)
        vim.schedule(function() on_done(nil, "Ollama unreachable: " .. msg) end)
        return
      end

      local ok, decoded = pcall(vim.json.decode, result.stdout)
      if not ok then
        log.err("ollama JSON decode failed: %s", result.stdout:sub(1, 200))
        vim.schedule(function() on_done(nil, "Bad JSON from Ollama.") end)
        return
      end

      if decoded.error then
        local msg = type(decoded.error) == "string" and decoded.error
                    or vim.inspect(decoded.error)
        log.err("ollama API error: %s", msg)
        vim.schedule(function() on_done(nil, msg) end)
        return
      end

      local text = decoded.message and decoded.message.content
      if not text then
        vim.schedule(function() on_done(nil, "Empty response from Ollama.") end)
        return
      end

      log.log("ollama ← %d chars", #text)
      vim.schedule(function() on_done(text, nil) end)
    end
  )
end

-- ── registry ───────────────────────────────────────────────────────────────

---@type table<string, { ask: fun(base_url:string, model:string, messages:table, on_done:fun(text:string|nil, err:string|nil)) }>
local registry = {
  ollama = ollama,
}

--- Fetch a backend by name (currently only "ollama").
---@param  name string
---@return table|nil
function M.get(name)
  return registry[name]
end

--- List available backend names.
---@return string[]
function M.list()
  local names = {}
  for k in pairs(registry) do table.insert(names, k) end
  table.sort(names)
  return names
end

return M