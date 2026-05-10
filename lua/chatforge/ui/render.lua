local M     = {}
local state = require("chatforge.core.state")
local NL    = "\n"
 
local NS = vim.api.nvim_create_namespace("chatforge_code")
 
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
 
  if state.chat_winnr and vim.api.nvim_win_is_valid(state.chat_winnr) then
    vim.api.nvim_win_set_cursor(state.chat_winnr, { buf_line_count(b), 0 })
  end
end
 
local function highlight_code_lines(first, last)
  local b = state.chat_bufnr
  if not b then return end
  vim.api.nvim_set_hl(0, "ChatforgeCode", { link = "DiffAdd", default = true })
  for lnum = first, last - 1 do
    vim.api.nvim_buf_add_highlight(b, NS, "ChatforgeCode", lnum, 0, -1)
  end
end
 
function M.write_header()
  local b = state.chat_bufnr
  if not b then return end
  vim.api.nvim_buf_set_option(b, "modifiable", true)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, {
    "# chatforge",
    "",
    "  :ChatSend <message>   send     :ChatReset   new chat     :ChatSetModel   set model",
    "",
    "---",
    "",
  })
  vim.api.nvim_buf_set_option(b, "modifiable", false)
end
 
function M.append_user(content, model)
  local lines = {
    string.format("**You** _(model: %s)_:", model or "?"),
    "",
  }
  for _, l in ipairs(vim.split(content, NL, { plain = true })) do
    table.insert(lines, "> " .. l)
  end
  table.insert(lines, "")
  append(lines)
end
 
function M.append_segments(segments)
  local b = state.chat_bufnr
  if not b then return end
 
  local lines       = { "**Assistant:**", "" }
  local code_ranges = {}
 
  for _, seg in ipairs(segments) do
    if seg.type == "text" then
      for _, l in ipairs(vim.split(seg.content, NL, { plain = true })) do
        table.insert(lines, l)
      end
 
    elseif seg.type == "code" then
      local block_start = #lines
      local block_index = seg.index or (#code_ranges + 1)
      table.insert(lines, "```" .. (seg.lang or ""))
      for _, l in ipairs(vim.split(seg.content, NL, { plain = true })) do
        table.insert(lines, l)
      end
      table.insert(lines, "```")
      local block_end = #lines
      table.insert(lines, string.format(
        "  [ Preview #%d ]  [ Apply #%d ]  [ Diff #%d ]  [ Yank #%d ]",
        block_index, block_index, block_index, block_index
      ))
      table.insert(lines, "")
      table.insert(code_ranges, { block_start, block_end })
    end
  end
 
  local n_blocks = #code_ranges
 
  if n_blocks > 0 then
    table.insert(lines, "")
    if n_blocks == 1 then
      table.insert(lines, "  Put the cursor on an action above and run :ChatActivate, or use :ChatApply / :ChatDiff / :ChatReject")
    else
      local previews = {}
      for i = 1, n_blocks do
        table.insert(previews, string.format(":ChatPreview %d", i))
      end
      table.insert(lines, "  " .. table.concat(previews, "   "))
      table.insert(lines, "  :ChatApply N   :ChatDiff N   :ChatReject")
    end
    table.insert(lines, "")
  end
 
  table.insert(lines, "---")
  table.insert(lines, "")
 
  local buf_offset = buf_line_count(b)
  append(lines)
 
  for _, range in ipairs(code_ranges) do
    highlight_code_lines(buf_offset + range[1], buf_offset + range[2])
  end
end
 
function M.append_status(msg, kind)
  local prefix = (kind == "error") and "⚠  " or "⋯  "
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
