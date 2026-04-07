-- Public API:
--   M.preview(block_idx)          open a float for pending_blocks[block_idx]
--   M.close()                     close the current float if open

local M      = {}
local state  = require("chatforge.core.state")
local actions = require("chatforge.core.actions")
local log    = require("chatforge.utils.logger")

local _float_winnr = nil  ---@type number|nil
local _float_bufnr = nil  ---@type number|nil

-- ── helpers ────────────────────────────────────────────────────────────────

local function close_existing()
  if _float_winnr and vim.api.nvim_win_is_valid(_float_winnr) then
    vim.api.nvim_win_close(_float_winnr, true)
  end
  _float_winnr = nil
  _float_bufnr = nil
end

--- Map a language tag to a Neovim filetype string.
local LANG_FT = {
  lua        = "lua",
  python     = "python",
  py         = "python",
  javascript = "javascript",
  js         = "javascript",
  typescript = "typescript",
  ts         = "typescript",
  rust       = "rust",
  go         = "go",
  c          = "c",
  cpp        = "cpp",
  sh         = "sh",
  bash       = "sh",
  zsh        = "sh",
  json       = "json",
  yaml       = "yaml",
  toml       = "toml",
  html       = "html",
  css        = "css",
  sql        = "sql",
  markdown   = "markdown",
  md         = "markdown",
}

local function lang_to_ft(lang)
  return LANG_FT[lang:lower()] or lang
end

--- Calculate float dimensions: up to 80% screen width, 60% height.
local function float_dims(lines)
  local max_w = math.floor(vim.o.columns * 0.80)
  local max_h = math.floor(vim.o.lines   * 0.60)

  local content_w = 0
  for _, l in ipairs(lines) do
    content_w = math.max(content_w, vim.fn.strdisplaywidth(l))
  end

  local width  = math.min(math.max(content_w + 4, 40), max_w)
  local height = math.min(math.max(#lines + 2,  6),  max_h)
  local row    = math.floor((vim.o.lines   - height) / 2)
  local col    = math.floor((vim.o.columns - width)  / 2)

  return width, height, row, col
end

-- ── action bar ─────────────────────────────────────────────────────────────
-- A second tiny float sitting just below the main one with button hints.

local _bar_winnr = nil

local function open_action_bar(block_idx, main_row, main_height, main_col, main_width)
  if _bar_winnr and vim.api.nvim_win_is_valid(_bar_winnr) then
    vim.api.nvim_win_close(_bar_winnr, true)
    _bar_winnr = nil
  end

  local label = string.format(
    "  a Apply  d Diff  y Yank  q Close   (block #%d)", block_idx
  )
  local bar_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bar_buf, 0, -1, false, { label })
  vim.bo[bar_buf].modifiable = false

  local w = vim.api.nvim_open_win(bar_buf, false, {
    relative = "editor",
    width    = main_width,
    height   = 1,
    row      = main_row + main_height + 1,
    col      = main_col,
    style    = "minimal",
    border   = "rounded",
    focusable = false,
  })
  vim.wo[w].winhl = "Normal:Comment"
  _bar_winnr = w
end

-- ── public API ─────────────────────────────────────────────────────────────

--- Preview pending_blocks[block_idx] in a floating window.
---@param block_idx number  1-based
function M.preview(block_idx)
  close_existing()

  local block = state.pending_blocks[block_idx]
  if not block then
    vim.notify(
      string.format("[chatforge] No code block #%d pending.", block_idx),
      vim.log.levels.WARN
    )
    return
  end

  local lines  = vim.split(block.content, "\n")
  local ft     = lang_to_ft(block.lang or "text")
  local title  = string.format(" Block #%d  [%s] ", block_idx, block.lang or "text")

  local width, height, row, col = float_dims(lines)

  -- Create content buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].filetype   = ft
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].bufhidden  = "wipe"

  -- Open the float
  local winnr = vim.api.nvim_open_win(bufnr, true, {
    relative  = "editor",
    width     = width,
    height    = height,
    row       = row,
    col       = col,
    style     = "minimal",
    border    = "rounded",
    title     = title,
    title_pos = "center",
  })
  vim.wo[winnr].wrap       = false
  vim.wo[winnr].cursorline = true
  vim.wo[winnr].number     = true

  _float_winnr = winnr
  _float_bufnr = bufnr

  open_action_bar(block_idx, row, height, col, width)

  log.log("floating.preview: block=%d lang=%s lines=%d", block_idx, block.lang or "?", #lines)

  -- ── keymaps inside the float ──────────────────────────────────────────
  local o = { noremap = true, silent = true, buffer = bufnr }

  vim.keymap.set("n", "q", function() M.close() end, o)
  vim.keymap.set("n", "<Esc>", function() M.close() end, o)

  vim.keymap.set("n", "a", function()
    M.close()
    actions.apply_to_current(block_idx)
  end, o)

  vim.keymap.set("n", "d", function()
    M.close()
    actions.diff_with_current(block_idx)
  end, o)

  vim.keymap.set("n", "y", function()
    actions.yank(block_idx)
    vim.notify("[chatforge] Yanked. Float stays open.", vim.log.levels.INFO)
  end, o)

  -- Close when focus leaves
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer   = bufnr,
    once     = true,
    callback = function()
      vim.defer_fn(function()
        -- Only auto-close if the bar isn't the new focus
        if _float_winnr and vim.api.nvim_win_is_valid(_float_winnr) then
          M.close()
        end
      end, 50)
    end,
  })
end

--- Close the preview float (and its action bar).
function M.close()
  close_existing()
  if _bar_winnr and vim.api.nvim_win_is_valid(_bar_winnr) then
    vim.api.nvim_win_close(_bar_winnr, true)
    _bar_winnr = nil
  end
end

return M
