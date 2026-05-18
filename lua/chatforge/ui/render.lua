local M     = {}
local state = require("chatforge.core.state")
local NL    = "\n"

local CHAT_WIDTH = 58
local message_lines

vim.api.nvim_set_hl(0, "ChatforgeUserBubble", { fg = "#d7f7ff", bg = "#17343a", default = true })
vim.api.nvim_set_hl(0, "ChatforgeAssistantBubble", { fg = "#d8dee9", bg = "#171a22", default = true })
vim.api.nvim_set_hl(0, "ChatforgeMuted", { link = "Comment", default = true })
vim.api.nvim_set_hl(0, "ChatforgeStatus", { link = "DiagnosticInfo", default = true })

local function chat_buf()
  local b = state.chat_bufnr
  if b and vim.api.nvim_buf_is_valid(b) then
    return b
  end
  return nil
end

local function visible_width()
  if state.chat_winnr and vim.api.nvim_win_is_valid(state.chat_winnr) then
    return math.max(vim.api.nvim_win_get_width(state.chat_winnr) - 4, 36)
  end
  return CHAT_WIDTH
end

local function visible_height()
  if state.chat_winnr and vim.api.nvim_win_is_valid(state.chat_winnr) then
    return math.max(vim.api.nvim_win_get_height(state.chat_winnr), 12)
  end
  return 24
end

local function split_lines(content)
  local lines = {}
  for _, l in ipairs(vim.split(tostring(content or ""), NL, { plain = true })) do
    l = l:gsub("\r", "")
    table.insert(lines, l)
  end
  return lines
end

local function wrap_line(line, width)
  if line == "" then
    return { "" }
  end

  local out = {}
  local current = ""
  for word in line:gmatch("%S+") do
    if current == "" then
      current = word
    elseif #current + #word + 1 <= width then
      current = current .. " " .. word
    else
      table.insert(out, current)
      current = word
    end
  end
  if current ~= "" then
    table.insert(out, current)
  end
  if #out == 0 then
    return { line:sub(1, width) }
  end
  return out
end

local function chat_safe_text(content)
  local out = {}
  local in_code = false
  for _, line in ipairs(split_lines(content)) do
    if line:match("^```") then
      if not in_code then
        table.insert(out, "[code hidden from chat pane]")
      end
      in_code = not in_code
    elseif not in_code then
      table.insert(out, line)
    end
  end
  return table.concat(out, NL)
end

local function set_lines(lines)
  local b = chat_buf()
  if not b then return end
  vim.bo[b].modifiable = true
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
end

local function apply_highlights()
  local b = chat_buf()
  if not b then return end
  vim.api.nvim_buf_clear_namespace(b, state.render_ns, 0, -1)

  for _, span in ipairs(state.chat_spans or {}) do
    local hl = span.kind == "user" and "ChatforgeUserBubble"
      or span.kind == "assistant" and "ChatforgeAssistantBubble"
      or span.kind == "status" and "ChatforgeStatus"
      or "ChatforgeMuted"
    vim.api.nvim_buf_add_highlight(b, state.render_ns, hl, span.line - 1, 0, -1)
  end

end

local function render_entries()
  local lines = {}
  local spans = {}

  for _, entry in ipairs(state.chat_entries or {}) do
    local entry_lines
    if entry.type == "raw" then
      entry_lines = vim.deepcopy(entry.lines or {})
    else
      entry_lines = message_lines(entry.content, {
        label = entry.label,
        align = entry.align,
      })
    end

    local start = #lines + 1
    vim.list_extend(lines, entry_lines)
    local finish = #lines
    for line = start, finish do
      table.insert(spans, { line = line, kind = entry.kind })
    end
  end

  local filler_count = math.max(visible_height() - #lines - 1, 0)
  for _ = 1, filler_count do
    table.insert(lines, "")
  end

  state.chat_lines = lines
  state.chat_spans = spans
  return lines
end

local function redraw()
  local lines = render_entries()
  set_lines(lines)
  local b = chat_buf()
  if b then
    vim.bo[b].modifiable = false
  end
  apply_highlights()
end

local function append_entry(entry)
  state.chat_entries = state.chat_entries or {}
  table.insert(state.chat_entries, entry)
  redraw()

  if state.chat_winnr
      and vim.api.nvim_win_is_valid(state.chat_winnr)
      and vim.api.nvim_win_get_buf(state.chat_winnr) == state.chat_bufnr then
    local cursor_line = math.max(vim.api.nvim_buf_line_count(state.chat_bufnr), 1)
    vim.api.nvim_win_set_cursor(state.chat_winnr, { cursor_line, 3 })
  end
end

message_lines = function(content, opts)
  opts = opts or {}
  local full_width = visible_width()
  local max_width = math.max(math.floor(full_width * 0.78), 28)
  local width = math.min(max_width, opts.width or max_width)
  local body = {}
  for _, line in ipairs(split_lines(chat_safe_text(content))) do
    for _, wrapped in ipairs(wrap_line(line, width)) do
      table.insert(body, wrapped)
    end
  end

  if #body == 0 then
    body = { "" }
  end

  local label = opts.label or ""
  local lines = { "" }

  if opts.align == "right" then
    local label_pad = math.max(full_width - #label - 2, 0)
    table.insert(lines, string.rep(" ", label_pad) .. label)
    for _, line in ipairs(body) do
      local padded = " " .. line .. " "
      local pad = math.max(full_width - #padded - 2, 0)
      table.insert(lines, string.rep(" ", pad) .. padded)
    end
  else
    table.insert(lines, label)
    for _, line in ipairs(body) do
      table.insert(lines, " " .. line .. " ")
    end
  end
  return lines
end

function M.write_header()
  state.chat_entries = {
    {
      type = "raw",
      kind = "muted",
      lines = {
        "# chatforge",
        "",
        "Ask below. Code stays out of chat.",
        "Apply writes. Reject discards.",
        "",
        "---",
      },
    },
  }
  state.input_lines = { "" }
  redraw()
end

function M.redraw()
  redraw()
end

function M.append_user(content, model)
  local label = string.format("You [%s]", model or "?")
  append_entry({
    type = "message",
    kind = "user",
    label = label,
    align = "right",
    content = content,
  })
end

function M.append_segments(segments)
  local text_parts = {}
  local n_blocks = 0
  local has_actions = false
  local staged_hint_rendered = false

  for _, seg in ipairs(segments) do
    if seg.type == "text" then
      table.insert(text_parts, seg.content)
    elseif seg.type == "code" then
      local block_index = seg.index or (n_blocks + 1)
      n_blocks = n_blocks + 1
      local block = state.pending_blocks[block_index]
      if block and block.stageable == false then
        table.insert(text_parts, string.format(
          "Example code #%d was hidden from chat. Ask for an edit, fix, refactor, or selected-range rewrite to stage changes in the file.",
          block_index
        ))
      else
        local suffix = ""
        if block and block.target_file then
          suffix = " -> " .. block.target_file
        end
        table.insert(text_parts, string.format("Implementation #%d ready%s.", block_index, suffix))
        if not staged_hint_rendered then
          table.insert(text_parts, string.format("Review: :ChatAccept, :ChatReject, :ChatDiff %d.", block_index))
          staged_hint_rendered = true
          has_actions = true
        end
      end
    end
  end

  if n_blocks > 0 and has_actions then
    table.insert(text_parts, "Generated code is staged in the source buffer and highlighted until Apply or Reject.")
  end

  append_entry({
    type = "message",
    kind = "assistant",
    label = "Assistant",
    align = "left",
    content = table.concat(text_parts, "\n\n"),
  })
end

function M.append_assistant_text(content)
  append_entry({
    type = "message",
    kind = "assistant",
    label = "Assistant",
    align = "left",
    content = content,
  })
end

function M.append_status(msg, kind)
  local label = kind == "error" and "Error" or "Status"
  append_entry({
    type = "message",
    kind = "status",
    label = label,
    align = "left",
    content = msg,
  })
  state.last_status_entry = #(state.chat_entries or {})
end

function M.remove_last_status()
  local entry = state.last_status_entry
  if not entry or not state.chat_entries or not state.chat_entries[entry] then
    return
  end
  table.remove(state.chat_entries, entry)
  state.last_status_entry = nil
  redraw()
end

return M
