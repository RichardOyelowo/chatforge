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

local function target_bufnr()
  local current = vim.api.nvim_get_current_buf()
  if not state.is_plugin_buf(current) then
    return current
  end
  if state.source_bufnr and vim.api.nvim_buf_is_valid(state.source_bufnr) then
    return state.source_bufnr
  end
  return nil
end

local function focus_source_window(bufnr)
  if state.source_winnr and vim.api.nvim_win_is_valid(state.source_winnr) then
    vim.api.nvim_set_current_win(state.source_winnr)
    if vim.api.nvim_win_get_buf(state.source_winnr) ~= bufnr then
      vim.api.nvim_win_set_buf(state.source_winnr, bufnr)
    end
    return
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      vim.api.nvim_set_current_win(win)
      state.source_winnr = win
      return
    end
  end
end

local function write_lines_live(bufnr, lines, on_done)
  focus_source_window(bufnr)

  local was_modifiable = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

  local i = 1
  local chunk_size = 2
  local wrote_any = false

  local function step()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    local chunk = {}
    for _ = 1, chunk_size do
      if i > #lines then break end
      table.insert(chunk, lines[i])
      i = i + 1
    end

    if #chunk > 0 then
      vim.bo[bufnr].modifiable = true
      if wrote_any then
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, chunk)
      else
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, chunk)
        wrote_any = true
      end
      local lc = vim.api.nvim_buf_line_count(bufnr)
      if state.source_winnr and vim.api.nvim_win_is_valid(state.source_winnr) then
        vim.api.nvim_win_set_cursor(state.source_winnr, { lc, 0 })
      end
    end

    if i <= #lines then
      vim.defer_fn(step, 18)
    else
      vim.bo[bufnr].modifiable = was_modifiable
      if on_done then on_done() end
    end
  end

  step()
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

  local bufnr = target_bufnr()
  if not bufnr then
    vim.notify("[chatforge] Open or focus a source buffer first.", vim.log.levels.WARN)
    return
  end

  write_lines_live(bufnr, lines, function()
    state.pending_blocks[idx].applied = true
    vim.notify(string.format("[chatforge] Applied block #%d to %s",
      idx, vim.api.nvim_buf_get_name(bufnr)), vim.log.levels.INFO)
  end)
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

  if state.source_winnr and vim.api.nvim_win_is_valid(state.source_winnr) then
    vim.api.nvim_set_current_win(state.source_winnr)
  end

  -- Open (or create) the file in the source area and write it live.
  vim.cmd("edit " .. vim.fn.fnameescape(fpath))
  local bufnr = vim.api.nvim_get_current_buf()
  state.source_bufnr = bufnr
  state.source_winnr = vim.api.nvim_get_current_win()

  write_lines_live(bufnr, lines, function()
    vim.cmd("write")
    state.pending_blocks[idx].applied = true
    vim.notify("[chatforge] Written block #" .. idx .. " -> " .. fpath, vim.log.levels.INFO)
  end)
end

--- Open a diff between block N and the current buffer in a new tab.
---@param idx number
function M.diff_with_current(idx)
  local lines, err = get_block_lines(idx)
  if err then
    vim.notify("[chatforge] " .. err, vim.log.levels.WARN)
    return
  end

  local orig_bufnr = target_bufnr()
  if not orig_bufnr then
    vim.notify("[chatforge] Open or focus a source buffer first.", vim.log.levels.WARN)
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
