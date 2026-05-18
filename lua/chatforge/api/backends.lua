local M   = {}
local log = require("chatforge.utils.logger")

-- ── Ollama ─────────────────────────────────────────────────────────────────

local ollama = {}

function ollama.ask(base_url, model, messages, on_done, opts)
  opts = opts or {}
  local body = vim.json.encode({
    model    = model,
    messages = messages,
    stream   = opts.stream == true,
    options  = {
      temperature = opts.temperature,
      num_predict = opts.max_output_tokens,
      num_ctx = opts.context_tokens,
    },
  })

  local url = base_url .. "/api/chat"
  log.log("ollama → POST %s  model=%s  msgs=%d", url, model, #messages)

  local cmd = {
    "curl", "--silent", "--no-buffer",
    "-X", "POST", url,
    "-H", "Content-Type: application/json",
    "-d", body,
  }

  if opts.stream then
    local text = ""
    local pending = ""
    local stderr = {}

    local function handle_line(line)
      if line == "" then
        return
      end
      local ok, decoded = pcall(vim.json.decode, line)
      if not ok then
        log.err("ollama stream JSON decode failed: %s", line:sub(1, 200))
        return
      end
      if decoded.error then
        table.insert(stderr, type(decoded.error) == "string" and decoded.error or vim.inspect(decoded.error))
        return
      end
      if decoded.message and decoded.message.content then
        local chunk = decoded.message.content
        text = text .. chunk
        if opts.on_delta then
          vim.schedule(function() opts.on_delta(chunk) end)
        end
      end
    end

    local job = vim.fn.jobstart(cmd, {
      stdout_buffered = false,
      stderr_buffered = true,
      on_stdout = function(_, data)
        if not data then
          return
        end
        pending = pending .. table.concat(data, "\n")
        while true do
          local newline = pending:find("\n", 1, true)
          if not newline then
            break
          end
          local line = pending:sub(1, newline - 1)
          pending = pending:sub(newline + 1)
          handle_line(line)
        end
      end,
      on_stderr = function(_, data)
        if data then
          for _, line in ipairs(data) do
            if line ~= "" then
              table.insert(stderr, line)
            end
          end
        end
      end,
      on_exit = function(_, code)
        if pending ~= "" then
          handle_line(pending)
        end
        if code ~= 0 then
          local msg = #stderr > 0 and table.concat(stderr, "\n")
                      or ("curl exit " .. code)
          log.err("ollama curl failed: %s", msg)
          vim.schedule(function() on_done(nil, "Ollama unreachable: " .. msg) end)
          return
        end
        if #stderr > 0 then
          vim.schedule(function() on_done(nil, table.concat(stderr, "\n")) end)
          return
        end
        if text == "" then
          vim.schedule(function() on_done(nil, "Empty response from Ollama.") end)
          return
        end
        log.log("ollama ← %d chars", #text)
        vim.schedule(function() on_done(text, nil) end)
      end,
    })

    if job <= 0 then
      vim.schedule(function() on_done(nil, "Ollama unreachable: could not start curl") end)
    end
    return
  end

  vim.system(
    cmd,
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
      if not text or text == "" then
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
