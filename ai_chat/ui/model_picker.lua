local M      = {}
local state  = require("chatforge.core.state")
local config = require("chatforge.config")
local log    = require("chatforge.utils.logger")

--- Fetch the list of models Ollama knows about.
---@param  on_done fun(models:string[]|nil, err:string|nil)
local function fetch_models(on_done)
  local url = config.values.ollama_url .. "/api/tags"
  vim.system(
    { "curl", "--silent", url },
    { text = true },
    function(result)
      if result.code ~= 0 then
        vim.schedule(function()
          on_done(nil, "curl failed: " .. (result.stderr or ""))
        end)
        return
      end

      local ok, decoded = pcall(vim.json.decode, result.stdout)
      if not ok or not decoded.models then
        -- Ollama might not be running — fall back to config default
        vim.schedule(function()
          on_done({ config.values.default_model }, nil)
        end)
        return
      end

      local names = {}
      for _, m in ipairs(decoded.models) do
        table.insert(names, m.name)
      end
      table.sort(names)

      vim.schedule(function() on_done(names, nil) end)
    end
  )
end

--- Open the model picker for a given source buffer.
---@param src_bufnr number
function M.pick(src_bufnr)
  fetch_models(function(models, err)
    if err then
      vim.notify("[chatforge] Could not fetch models: " .. err, vim.log.levels.WARN)
      models = { config.values.default_model }
    end

    local current = state.get_model(src_bufnr)

    vim.ui.select(models, {
      prompt = "Select model for this buffer (current: " .. current .. "):",
      format_item = function(item)
        return item == current and item .. "  ✓" or item
      end,
    }, function(choice)
      if not choice then return end
      state.set_model(src_bufnr, choice)
      vim.notify("[chatforge] Model set to: " .. choice, vim.log.levels.INFO)
      log.log("model_picker: bufnr=%d model=%s", src_bufnr, choice)
    end)
  end)
end

return M
