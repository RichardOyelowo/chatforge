local M     = {}
local state = require("chatforge.core.state")
local NL    = "\n"
 
local function buf_line_count(b)
  return vim.api.nvim_buf_line_count(b)
end
 
local function append(lines)
  local b = state.chat_bufnr
  if not b or not vim.api.nvim_buf_is_valid(b) then return end
 
  local flat = {}
  for _, l in ipairs(lines) do
    l = l:gsub("\r", "")
    for _, sub in ipairs(vim.split(l, NL, { plain = true })) do
      table.insert(flat, sub)
    end
  end
 
  vim.api.nvim_buf_set_option(b, "modifiable", true)
  vim.api.nvim_buf_set_lines(b, -1, -1, false, flat)
  vim.api.nvim_buf_set_option(b, "modifiable", false)
 
  if state.chat_winnr
      and vim.api.nvim_win_is_valid(state.chat_winnr)
      and vim.api.nvim_win_get_buf(state.chat_winnr) == b then
    vim.api.nvim_win_set_cursor(state.chat_winnr, { buf_line_count(b), 0 })
  end
end

local function chat_safe_text(content)
  local out = {}
  local in_code = false
  for _, line in ipairs(vim.split(content, NL, { plain = true })) do
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
 
function M.write_header()
  local b = state.chat_bufnr
  if not b then return end
  vim.api.nvim_buf_set_option(b, "modifiable", true)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, {
    "chatforge",
    "---------",
    "",
    "Ask in the message box below. Generated code is kept out of this pane.",
    "Apply writes into the source file; Reject discards the pending implementation.",
    "",
    "---",
    "",
  })
  vim.api.nvim_buf_set_option(b, "modifiable", false)
end
 
function M.append_user(content, model)
  local lines = {
    string.format("You  [%s]", model or "?"),
    "----------------",
  }
  for _, l in ipairs(vim.split(chat_safe_text(content), NL, { plain = true })) do
    table.insert(lines, "  " .. l)
  end
  table.insert(lines, "")
  append(lines)
end
 
function M.append_segments(segments)
  local b = state.chat_bufnr
  if not b then return end
 
  local lines = { "Assistant", "---------" }
  local n_blocks = 0
  local has_actions = false
  local staged_hint_rendered = false
 
  for _, seg in ipairs(segments) do
    if seg.type == "text" then
      for _, l in ipairs(vim.split(seg.content, NL, { plain = true })) do
        if l:match("%S") then
          table.insert(lines, "  " .. l)
        end
      end
 
    elseif seg.type == "code" then
      local block_index = seg.index or (n_blocks + 1)
      n_blocks = n_blocks + 1
      local block = state.pending_blocks[block_index]
      table.insert(lines, "")
      if block and block.stageable == false then
        table.insert(lines, string.format("  Example code #%d hidden from chat pane.", block_index))
        table.insert(lines, "  Ask for an edit, fix, refactor, or selected-range rewrite to stage changes in the file.")
      else
        table.insert(lines, string.format("  Implementation #%d ready", block_index))
        if not staged_hint_rendered then
          table.insert(lines, "  It will be staged directly in the source buffer for review.")
        else
          table.insert(lines, "  Only one implementation is staged at a time.")
        end
      end
      local suffix = ""
      if block and block.target_file then
        suffix = " -> " .. block.target_file
      end
      if (not block or block.stageable ~= false) and not staged_hint_rendered then
        has_actions = true
        staged_hint_rendered = true
        table.insert(lines, string.format(
          "  :ChatApply %d    :ChatReject    :ChatDiff %d%s",
          block_index, block_index, suffix
        ))
      end
    end
  end
 
  if n_blocks > 0 and has_actions then
    table.insert(lines, "")
    table.insert(lines, "  Staged changes are highlighted in the source buffer until Apply or Reject.")
    table.insert(lines, "")
  end
 
  table.insert(lines, "---")
  table.insert(lines, "")
 
  append(lines)
end

function M.append_assistant_text(content)
  local lines = { "Assistant", "---------" }
  for _, l in ipairs(vim.split(chat_safe_text(content), NL, { plain = true })) do
    if l:match("%S") then
      table.insert(lines, "  " .. l)
    end
  end
  table.insert(lines, "")
  table.insert(lines, "---")
  table.insert(lines, "")
  append(lines)
end
 
function M.append_status(msg, kind)
  local prefix = (kind == "error") and "!  " or "...  "
  append({ "*" .. prefix .. msg .. "*", "" })
end
 
function M.remove_last_status()
  local b = state.chat_bufnr
  if not b or not vim.api.nvim_buf_is_valid(b) then return end
  vim.api.nvim_buf_set_option(b, "modifiable", true)
  local lc = buf_line_count(b)
  vim.api.nvim_buf_set_lines(b, lc - 2, lc, false, {})
  vim.api.nvim_buf_set_option(b, "modifiable", false)
end
 
return M
