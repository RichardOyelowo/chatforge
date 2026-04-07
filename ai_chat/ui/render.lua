local M     = {}
local state = require("chatforge.core.state")

-- ── internal ───────────────────────────────────────────────────────────────

local function append(lines)
  if not state.chat_bufnr or not vim.api.nvim_buf_is_valid(state.chat_bufnr) then
    return
  end
  vim.api.nvim_buf_set_option(state.chat_bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(state.chat_bufnr, -1, -1, false, lines)
  vim.api.nvim_buf_set_option(state.chat_bufnr, "modifiable", false)

  if state.chat_winnr and vim.api.nvim_win_is_valid(state.chat_winnr) then
    local lc = vim.api.nvim_buf_line_count(state.chat_bufnr)
    vim.api.nvim_win_set_cursor(state.chat_winnr, { lc, 0 })
  end
end

-- ── public ─────────────────────────────────────────────────────────────────

function M.write_header()
  local b = state.chat_bufnr
  if not b then return end
  vim.api.nvim_buf_set_option(b, "modifiable", true)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, {
    "# AI Chat",
    "",
    "  <CR>  send    q  close    m  model picker    R  reset    ?  help",
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
  for _, l in ipairs(vim.split(content, "\n")) do
    table.insert(lines, "> " .. l)
  end
  table.insert(lines, "")
  append(lines)
end

--- Render a full parsed segment list from parser.parse().
---@param segments table[]
function M.append_segments(segments)
  local lines   = { "**Assistant:**", "" }
  local actions = {}   -- collected action segments to render at the end

  for _, seg in ipairs(segments) do
    if seg.type == "text" then
      for _, l in ipairs(vim.split(seg.content, "\n")) do
        table.insert(lines, l)
      end

    elseif seg.type == "code" then
      table.insert(lines, "```" .. (seg.lang or ""))
      for _, l in ipairs(vim.split(seg.content, "\n")) do
        table.insert(lines, l)
      end
      table.insert(lines, "```")
      table.insert(lines, "")

    elseif seg.type == "action" then
      table.insert(actions, seg)
    end
  end

  -- Action buttons for each code block
  for _, act in ipairs(actions) do
    local idx = act.block_index
    local target_hint = act.target and ("  ->  " .. act.target) or ""
    table.insert(lines, string.format(
      "  [ Accept #%d ]  [ Diff #%d ]  [ Yank #%d ]  [ Preview #%d ]%s",
      idx, idx, idx, idx, target_hint
    ))
    table.insert(lines, "")
  end

  table.insert(lines, "---")
  table.insert(lines, "")
  append(lines)
end

function M.append_status(msg, kind)
  local prefix = (kind == "error") and "⚠  " or "⋯  "
  append({ "*" .. prefix .. msg .. "*", "" })
end

--- Remove the last status line pair (used after response arrives).
function M.remove_last_status()
  local b = state.chat_bufnr
  if not b or not vim.api.nvim_buf_is_valid(b) then return end
  vim.api.nvim_buf_set_option(b, "modifiable", true)
  local lc = vim.api.nvim_buf_line_count(b)
  -- status is "*... msg ...*" + blank line = 2 lines
  vim.api.nvim_buf_set_lines(b, lc - 2, lc, false, {})
  vim.api.nvim_buf_set_option(b, "modifiable", false)
end

return M
