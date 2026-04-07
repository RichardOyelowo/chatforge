emlocal M = {}

M.fix = "Fix the following code and explain what was wrong:\n\n```%s\n%s\n```"

M.explain = "Explain what this code does, step by step:\n\n```%s\n%s\n```"

M.refactor = "Refactor the following code for clarity and performance. "
          .. "Show the improved version with a brief explanation:\n\n```%s\n%s\n```"

M.tests = "Write unit tests for the following code:\n\n```%s\n%s\n```"

M.docstring = "Add docstrings / comments to the following code:\n\n```%s\n%s\n```"

--- Build a prompt from a template key + code.
---@param  key      string  key in M (fix|explain|refactor|tests|docstring)
---@param  code     string
---@param  filetype? string  e.g. "lua", "python"
---@return string|nil
function M.build(key, code, filetype)
  local tpl = M[key]
  if not tpl then return nil end
  return string.format(tpl, filetype or "", code)
end

return M
