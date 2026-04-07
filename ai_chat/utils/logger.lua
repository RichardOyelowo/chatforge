local M = {}

local _enabled = false

function M.setup(enabled)
  _enabled = enabled or false
end

function M.log(msg, ...)
  if not _enabled then return end
  local formatted = type(msg) == "string" and string.format(msg, ...) or vim.inspect(msg)
  vim.schedule(function()
    vim.notify("[chatforge] " .. formatted, vim.log.levels.DEBUG)
  end)
end

function M.warn(msg, ...)
  local formatted = type(msg) == "string" and string.format(msg, ...) or vim.inspect(msg)
  vim.schedule(function()
    vim.notify("[chatforge] WARN: " .. formatted, vim.log.levels.WARN)
  end)
end

function M.err(msg, ...)
  local formatted = type(msg) == "string" and string.format(msg, ...) or vim.inspect(msg)
  vim.schedule(function()
    vim.notify("[chatforge] ERROR: " .. formatted, vim.log.levels.ERROR)
  end)
end

return M
