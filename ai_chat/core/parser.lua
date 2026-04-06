-- Parses raw AI response text into typed segments:
--   { type="text",   content="..." }
--   { type="code",   lang="lua",  content="...", index=N }
--   { type="action", action="edit_file"|"create_file"|"apply", target=?, block_index=N }

local M = {}

local FILE_PATTERN = "([%w_%-%.%/]+%.%w+)"

local function guess_target(text)
  return text:match(FILE_PATTERN)
end

local function guess_action(text)
  local lower = text:lower()
  if lower:match("creat")                              then return "create_file"
  elseif lower:match("edit") or lower:match("updat")
      or lower:match("modif") or lower:match("replac") then return "edit_file"
  else                                                  return "apply"
  end
end

function M.parse(raw)
  local segments  = {}
  local pos       = 1
  local len       = #raw
  local code_idx  = 0
  local last_text = ""

  while pos <= len do
    local fence_start, fence_end, lang = raw:find("```([%w_%-]*)\n", pos)

    if not fence_start then
      local tail = raw:sub(pos)
      if tail ~= "" then
        table.insert(segments, { type = "text", content = tail })
      end
      break
    end

    if fence_start > pos then
      local before = raw:sub(pos, fence_start - 1)
      if before:match("%S") then
        table.insert(segments, { type = "text", content = before })
        last_text = before
      end
    end

    local code_start = fence_end + 1
    local close_start, close_end = raw:find("\n```", code_start)
    local code_content

    if not close_start then
      code_content = raw:sub(code_start)
      pos = len + 1
    else
      code_content = raw:sub(code_start, close_start - 1)
      pos = close_end + 1
    end

    code_idx = code_idx + 1
    table.insert(segments, {
      type    = "code",
      lang    = (lang ~= "") and lang or "text",
      content = code_content,
      index   = code_idx,
    })

    table.insert(segments, {
      type        = "action",
      action      = guess_action(last_text),
      target      = guess_target(last_text),
      block_index = code_idx,
    })

    last_text = ""
  end

  return segments
end

function M.extract_code_blocks(raw)
  local out = {}
  for _, s in ipairs(M.parse(raw)) do
    if s.type == "code" then table.insert(out, s) end
  end
  return out
end

return M