local M      = {}
local buf_u  = require("chatforge.utils.buffer")
local log    = require("chatforge.utils.logger")

---@alias DispatchAction "chat"|"edit_file"|"create_file"|"delete_file"|"explain"

---@class DispatchResult
---@field action   DispatchAction
---@field prompt   string         enriched prompt to send to the model
---@field target?  string         file path (for file operations)

local RULES = {
  { pattern = "^create%s+file%s+(%S+)",  action = "create_file",  capture = 1 },
  { pattern = "^edit%s+file%s+(%S+)",    action = "edit_file",    capture = 1 },
  { pattern = "^delete%s+file%s+(%S+)",  action = "delete_file",  capture = 1 },
  { pattern = "^explain%s+",             action = "explain"                   },
  { pattern = "^fix%s+",                 action = "edit_file"                 },
  { pattern = "^refactor%s+",            action = "edit_file"                 },
}

--- Detect action from raw user input.
---@param  input string
---@return DispatchAction, string|nil  action, optional file target
local function classify(input)
  local lower = input:lower()
  for _, rule in ipairs(RULES) do
    local m = { lower:match(rule.pattern) }
    if m[1] ~= nil then
      local target = rule.capture and m[rule.capture] or nil
      return rule.action, target
    end
  end
  return "chat", nil
end

--- Build the enriched prompt, optionally injecting current buffer content.
---@param  input     string
---@param  action    DispatchAction
---@param  src_bufnr number          the source (non-chat) buffer
---@return string
local function build_prompt(input, action, src_bufnr)
  local ft   = buf_u.get_filetype(src_bufnr)
  local name = buf_u.get_name(src_bufnr)

  -- For file-modification actions, include buffer content automatically
  if action == "edit_file" or action == "explain" then
    local content = buf_u.get_content(src_bufnr)
    if content ~= "" then
      return string.format(
        "%s\n\nFile: %s\n```%s\n%s\n```",
        input, name ~= "" and name or "(unnamed)", ft, content
      )
    end
  end

  return input
end

--- Dispatch user input → DispatchResult.
---@param  input     string
---@param  src_bufnr number
---@return DispatchResult
function M.dispatch(input, src_bufnr)
  local action, target = classify(input)
  local prompt = build_prompt(input, action, src_bufnr)

  log.log("dispatch: action=%s target=%s", action, target or "nil")

  return {
    action  = action,
    prompt  = prompt,
    target  = target,
  }
end

return M