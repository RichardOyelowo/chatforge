local M     = {}
local state = require("chatforge.core.state")
 
-- Highlight namespace for green AI code blocks
local NS = vim.api.nvim_create_namespace("chatforge_code")
 
-- ── internal ───────────────────────────────────────────────────────────────
 
local function buf_line_count(b)
  return vim.api.nvim_buf_line_count(b)
end
 
local function append(lines)
  local b = state.chat_bufnr
  if not b or not vim.api.nvim_buf_is_valid(b) then return end
  vim.api.nvim_buf_set_option(b, "modifiable", true)
  vim.api.nvim_buf_set_lines(b, -1, -1, false, lines)
  vim.api.nvim_buf_set_option(b, "modifiable", false)
  if state.chat_winnr and vim.api.nvim_win_is_valid(state.chat_winnr) then
    vim.api.nvim_win_set_cursor(state.chat_winnr, { buf_line_count(b), 0 })
  end
end
 
-- Highlight lines [first, last) in the chat buffer with a green tint.
-- Called after append() so the line numbers are final.
local function highlight_code_lines(first_line, last_line)
  local b = state.chat_bufnr
  if not b then return end
  -- Ensure the highlight group exists (links to DiffAdd which is green in most themes)
  vim.api.nvim_set_hl(0, "ChatforgeCode", { link = "DiffAdd", default = true })
  for lnum = first_line, last_line - 1 do
    vim.api.nvim_buf_add_highlight(b, NS, "ChatforgeCode", lnum, 0, -1)
  end
end
 
-- ── public ─────────────────────────────────────────────────────────────────
 
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
  for _, l in ipairs(vim.split(content, "")) do
    table.insert(lines, "> " .. l)
  end
  table.insert(lines, "")
  append(lines)
end
 
--- Render parsed segments. Green-highlights AI code blocks.
--- Shows a single set of action hints at the end (not per-block).
---@param segments table[]
function M.append_segments(segments)
  local b = state.chat_bufnr
  if not b then return end
 
  local lines      = { "**Assistant:**", "" }
  -- Track where each code block lands so we can highlight after append.
  -- { start_offset, end_offset } relative to current line count.
  local code_ranges = {}
 
  for _, seg in ipairs(segments) do
    if seg.type == "text" then
      for _, l in ipairs(vim.split(seg.content, "")) do
        table.insert(lines, l)
      end
 
    elseif seg.type == "code" then
      local block_start = #lines  -- 0-based offset within `lines`
      table.insert(lines, "```" .. (seg.lang or ""))
      for _, l in ipairs(vim.split(seg.content, "")) do
        table.insert(lines, l)
      end
      table.insert(lines, "```")
      table.insert(lines, "")
      table.insert(code_ranges, { block_start, #lines - 1 })
    end
    -- "action" segments: ignored here — we build hints below ourselves
  end
 
  -- Count how many code blocks are in this response
  local n_blocks = #code_ranges
 
  -- Single set of action hints at the end
  if n_blocks > 0 then
    table.insert(lines, "")
    if n_blocks == 1 then
      table.insert(lines, "  :ChatPreview   :ChatApply   :ChatDiff   :ChatReject")
    else
      -- Show numbered variants for each block
      local preview_hints = {}
      for i = 1, n_blocks do
        table.insert(preview_hints, string.format(":ChatPreview %d", i))
      end
      table.insert(lines, "  " .. table.concat(preview_hints, "   "))
      table.insert(lines, "  :ChatApply N   :ChatDiff N   :ChatReject")
    end
    table.insert(lines, "")
  end
 
  table.insert(lines, "---")
  table.insert(lines, "")
 
  -- Record where this block starts in the real buffer before appending
  local buf_offset = buf_line_count(b)  -- current last line (0-based after this)
 
  append(lines)
 
  -- Apply green highlights to each code block
  for _, range in ipairs(code_ranges) do
    local first = buf_offset + range[1]   -- absolute 0-based line in buffer
    local last  = buf_offset + range[2]
    highlight_code_lines(first, last)
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