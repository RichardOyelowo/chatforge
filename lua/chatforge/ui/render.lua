local M     = {}
local state = require("chatforge.core.state")
local NL    = "\n"

local CHAT_WIDTH = 58
local INPUT_HEIGHT = 4

vim.api.nvim_set_hl(0, "ChatforgeUserBubble", { link = "Identifier", default = true })
vim.api.nvim_set_hl(0, "ChatforgeAssistantBubble", { link = "Normal", default = true })
vim.api.nvim_set_hl(0, "ChatforgeInputBox", { link = "FloatBorder", default = true })
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

local function input_box_lines(input_lines)
  local width = visible_width()
  local top = "+" .. string.rep("-", width - 2) .. "+"
  local lines = { "", top }
  for i = 1, INPUT_HEIGHT do
    local content = input_lines[i] or ""
    content = content:sub(1, width - 4)
    table.insert(lines, "> " .. content)
  end
  table.insert(lines, top)
  return lines
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

  if state.input_start_line then
    local start_idx = math.max(state.input_start_line - 4, 0)
    local end_idx = math.min(vim.api.nvim_buf_line_count(b), start_idx + INPUT_HEIGHT + 4)
    for lnum = start_idx, end_idx - 1 do
      vim.api.nvim_buf_add_highlight(b, state.render_ns, "ChatforgeInputBox", lnum, 0, -1)
    end
  end
end

local function redraw(input_lines)
  local transcript = vim.deepcopy(state.chat_lines or {})
  local box = input_box_lines(input_lines or state.input_lines or { "" })
  state.input_start_line = #transcript + 3
  state.input_end_line = state.input_start_line + INPUT_HEIGHT - 1

  local lines = {}
  vim.list_extend(lines, transcript)
  vim.list_extend(lines, box)
  set_lines(lines)
  apply_highlights()
end

local function append_transcript(lines, kind)
  state.chat_lines = state.chat_lines or {}
  state.chat_spans = state.chat_spans or {}
  local start = #state.chat_lines + 1
  for _, line in ipairs(lines) do
    table.insert(state.chat_lines, line)
  end
  local finish = #state.chat_lines
  for line = start, finish do
    table.insert(state.chat_spans, { line = line, kind = kind })
  end
  redraw()

  if state.chat_winnr
      and vim.api.nvim_win_is_valid(state.chat_winnr)
      and vim.api.nvim_win_get_buf(state.chat_winnr) == state.chat_bufnr then
    local cursor_line = state.input_start_line
    vim.api.nvim_win_set_cursor(state.chat_winnr, { cursor_line, 3 })
  end
end

local function message_lines(content, opts)
  opts = opts or {}
  local width = math.min(visible_width() - 10, opts.width or 44)
  local body = {}
  for _, line in ipairs(split_lines(chat_safe_text(content))) do
    for _, wrapped in ipairs(wrap_line(line, width)) do
      table.insert(body, wrapped)
    end
  end

  if #body == 0 then
    body = { "" }
  end

  local full_width = visible_width()
  local label = opts.label or ""
  local lines = { "" }

  if opts.align == "right" then
    local label_pad = math.max(full_width - #label, 0)
    table.insert(lines, string.rep(" ", label_pad) .. label)
    for _, line in ipairs(body) do
      local pad = math.max(full_width - #line, 0)
      table.insert(lines, string.rep(" ", pad) .. line)
    end
  else
    table.insert(lines, label)
    for _, line in ipairs(body) do
      table.insert(lines, line)
    end
  end
  return lines
end

function M.write_header()
  state.chat_lines = {
    "chatforge",
    "Ask, attach @file or @dir context, then review staged edits in the source buffer.",
  }
  state.chat_spans = {
    { line = 1, kind = "muted" },
    { line = 2, kind = "muted" },
  }
  state.input_lines = { "" }
  redraw({ "" })
end

function M.redraw_input(input_lines)
  state.input_lines = input_lines
  redraw(input_lines)
end

function M.append_user(content, model)
  local label = string.format("You [%s]", model or "?")
  append_transcript(message_lines(content, { label = label, align = "right", width = 38 }), "user")
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
          table.insert(text_parts, string.format("Apply: :ChatApply %d. Reject: :ChatReject. Diff: :ChatDiff %d.", block_index, block_index))
          staged_hint_rendered = true
          has_actions = true
        end
      end
    end
  end

  if n_blocks > 0 and has_actions then
    table.insert(text_parts, "Generated code is staged in the source buffer and highlighted until Apply or Reject.")
  end

  append_transcript(message_lines(table.concat(text_parts, "\n\n"), { label = "Assistant", align = "left", width = 44 }), "assistant")
end

function M.append_assistant_text(content)
  append_transcript(message_lines(content, { label = "Assistant", align = "left", width = 44 }), "assistant")
end

function M.append_status(msg, kind)
  local label = kind == "error" and "Error" or "Status"
  local lines = message_lines(msg, { label = label, align = "left", width = 42 })
  local start_idx = #(state.chat_lines or {}) + 1
  append_transcript(lines, "status")
  state.last_status_span = { start = start_idx, finish = start_idx + #lines - 1 }
end

function M.remove_last_status()
  local span = state.last_status_span
  if not span then
    return
  end
  for _ = span.start, span.finish do
    table.remove(state.chat_lines, span.start)
  end
  state.last_status_span = nil

  local spans = {}
  for _, existing in ipairs(state.chat_spans or {}) do
    if existing.line < span.start or existing.line > span.finish then
      local line = existing.line
      if line > span.finish then
        line = line - (span.finish - span.start + 1)
      end
      table.insert(spans, { line = line, kind = existing.kind })
    end
  end
  state.chat_spans = spans
  redraw()
end

return M
