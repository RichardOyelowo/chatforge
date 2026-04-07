local M     = {}
local state = require("chatforge.core.state")
local log   = require("chatforge.utils.logger")

-- ── helpers ────────────────────────────────────────────────────────────────

--- Return the lines of pending block N (1-based).
---@param  idx number
---@return string[]|nil, string|nil  lines, err
local function get_block_lines(idx)
  local block = state.pending_blocks[idx]
  if not block then
    return nil, "No pending code block #" .. idx
  end
  return vim.split(block.content, "\n"), nil
end

-- ── public API ─────────────────────────────────────────────────────────────

--- Apply block N to the current buffer (replaces entire contents).
---@param idx number  1-based index into state.pending_blocks
function M.apply_to_current(idx)
  local lines, err = get_block_lines(idx)
  if err then
    vim.notify("[chatforge] " .. err, vim.log.levels.WARN)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  -- Don't accidentally clobber the chat buffer itself
  if bufnr == state.chat_bufnr then
    vim.notify("[chatforge] Switch to your source buffer first.", vim.log.levels.WARN)
    return
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  state.pending_blocks[idx].applied = true
  vim.notify(string.format("[chatforge] Applied block #%d to %s",
    idx, vim.api.nvim_buf_get_name(bufnr)), vim.log.levels.INFO)
  log.log("apply_to_current: block=%d bufnr=%d", idx, bufnr)
end

--- Apply block N to a specific file path (writes to disk, opens buffer).
---@param idx    number
---@param fpath  string
function M.apply_to_file(idx, fpath)
  local lines, err = get_block_lines(idx)
  if err then
    vim.notify("[chatforge] " .. err, vim.log.levels.WARN)
    return
  end

  -- Open (or create) the file in a split and write
  vim.cmd("edit " .. vim.fn.fnameescape(fpath))
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.cmd("write")
  state.pending_blocks[idx].applied = true
  vim.notify("[chatforge] Written block #" .. idx .. " → " .. fpath, vim.log.levels.INFO)
end

--- Open a diff between block N and the current buffer in a new tab.
---@param idx number
function M.diff_with_current(idx)
  local lines, err = get_block_lines(idx)
  if err then
    vim.notify("[chatforge] " .. err, vim.log.levels.WARN)
    return
  end

  local orig_bufnr = vim.api.nvim_get_current_buf()
  if orig_bufnr == state.chat_bufnr then
    vim.notify("[chatforge] Switch to your source buffer first.", vim.log.levels.WARN)
    return
  end

  -- Create a scratch buffer for the proposed code
  local scratch = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
  vim.bo[scratch].filetype = vim.bo[orig_bufnr].filetype

  -- Open both in a diff-tab
  vim.cmd("tabnew")
  vim.api.nvim_set_current_buf(orig_bufnr)
  vim.cmd("diffthis")
  vim.cmd("vsplit")
  vim.api.nvim_set_current_buf(scratch)
  vim.cmd("diffthis")
  vim.bo[scratch].buftype = "nofile"

  vim.notify("[chatforge] Diff opened in new tab. :tabclose when done.", vim.log.levels.INFO)
end

--- Yank block N to the unnamed register.
---@param idx number
function M.yank(idx)
  local lines, err = get_block_lines(idx)
  if err then
    vim.notify("[chatforge] " .. err, vim.log.levels.WARN)
    return
  end
  vim.fn.setreg('"', table.concat(lines, "\n"))
  vim.notify(string.format("[chatforge] Block #%d yanked to register.", idx), vim.log.levels.INFO)
end

--- Discard all pending blocks (Reject all).
function M.reject_all()
  state.pending_blocks = {}
  vim.notify("[chatforge] All pending changes rejected.", vim.log.levels.INFO)
end

return M