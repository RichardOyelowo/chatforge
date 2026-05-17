local M     = {}
local state = require("chatforge.core.state")
local log   = require("chatforge.utils.logger")
local render = require("chatforge.ui.render")
local NS = vim.api.nvim_create_namespace("chatforge_proposed_change")

vim.api.nvim_set_hl(0, "ChatforgeProposedChange", { link = "DiffText", default = true })

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

local function fallback_target_bufnr()
  local current = vim.api.nvim_get_current_buf()
  if not state.is_plugin_buf(current) then
    return current
  end
  if state.source_bufnr and vim.api.nvim_buf_is_valid(state.source_bufnr) then
    return state.source_bufnr
  end
  return nil
end

local function target_bufnr_for_block(idx)
  local block = state.pending_blocks[idx]
  if block and block.target_bufnr and vim.api.nvim_buf_is_valid(block.target_bufnr) then
    return block.target_bufnr
  end
  return fallback_target_bufnr()
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

local function block_target(idx, bufnr)
  local block = state.pending_blocks[idx]
  local target = block and block.target
  if target and target.bufnr ~= bufnr then
    target = nil
  end
  return target
end

local function block_while_applying(action)
  if not state.applying then
    return false
  end
  vim.notify("[chatforge] Wait for the staged implementation to finish writing before " .. action .. ".", vim.log.levels.WARN)
  return true
end

local function find_window_for_buf(bufnr)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      return win
    end
  end
  return nil
end

local function use_source_buffer_for_path(path)
  local absolute = vim.fn.fnamemodify(path, ":p")
  local bufnr = vim.fn.bufadd(absolute)
  vim.fn.bufload(bufnr)

  if not vim.api.nvim_buf_is_valid(bufnr) then
    vim.notify("[chatforge] Could not open " .. path .. ".", vim.log.levels.ERROR)
    return nil
  end

  local win = find_window_for_buf(bufnr)
  if not win then
    win = state.source_winnr
    if not win or not vim.api.nvim_win_is_valid(win) then
      win = vim.api.nvim_get_current_win()
      if state.is_plugin_buf(vim.api.nvim_win_get_buf(win)) then
        win = nil
      end
    end
  end

  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
    if vim.api.nvim_win_get_buf(win) ~= bufnr then
      vim.api.nvim_win_set_buf(win, bufnr)
    end
    state.source_winnr = win
  end

  state.source_bufnr = bufnr
  return bufnr
end

local function write_buffer_to_disk(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  if vim.bo[bufnr].buftype ~= "" or vim.api.nvim_buf_get_name(bufnr) == "" then
    return true
  end

  local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function()
    vim.cmd("silent write")
  end)
  if not ok then
    vim.notify("[chatforge] Could not write accepted change: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  return true
end

local function add_proposed_highlight(bufnr, start_idx, line_count)
  vim.api.nvim_buf_clear_namespace(bufnr, NS, start_idx, start_idx + math.max(line_count, 1))
  for lnum = start_idx, start_idx + line_count - 1 do
    vim.api.nvim_buf_add_highlight(bufnr, NS, "ChatforgeProposedChange", lnum, 0, -1)
  end
end

local function clear_proposed_highlight(change)
  if change and change.bufnr and vim.api.nvim_buf_is_valid(change.bufnr) then
    vim.api.nvim_buf_clear_namespace(change.bufnr, NS, 0, -1)
  end
end

local function write_lines_live(bufnr, lines, target, opts, on_done)
  opts = opts or {}
  focus_source_window(bufnr)

  local was_modifiable = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true
  local start_idx = target and target.line1 and (target.line1 - 1) or 0
  local end_idx = target and target.line2 or -1
  local original = vim.api.nvim_buf_get_lines(bufnr, start_idx, end_idx, false)
  vim.api.nvim_buf_set_lines(bufnr, start_idx, end_idx, false, {})

  local i = 1
  local chunk_size = 2
  local insert_at = start_idx
  state.applying = true
  render.append_status("Implementing in source buffer...")

  local function step()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      state.applying = false
      render.remove_last_status()
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
      vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, chunk)
      insert_at = insert_at + #chunk
      if opts.highlight then
        add_proposed_highlight(bufnr, start_idx, insert_at - start_idx)
      end
      if state.source_winnr and vim.api.nvim_win_is_valid(state.source_winnr) then
        vim.api.nvim_win_set_cursor(state.source_winnr, { math.max(insert_at, 1), 0 })
      end
    end

    if i <= #lines then
      vim.defer_fn(step, 18)
    else
      if not target then
        local current = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        if #current > #lines and current[#current] == "" then
          vim.api.nvim_buf_set_lines(bufnr, #current - 1, #current, false, {})
        end
      end
      vim.bo[bufnr].modifiable = was_modifiable
      state.applying = false
      render.remove_last_status()
      if on_done then
        on_done({
          bufnr = bufnr,
          start_idx = start_idx,
          end_idx = end_idx,
          new_line_count = #lines,
          original = original,
          target = target,
        })
      end
    end
  end

  step()
end

-- ── public API ─────────────────────────────────────────────────────────────

--- Apply block N to the current buffer (replaces entire contents).
---@param idx number  1-based index into state.pending_blocks
function M.apply_to_current(idx)
  if block_while_applying("applying") then
    return
  end

  local staged = state.staged_changes[idx]
  if staged then
    if not write_buffer_to_disk(staged.bufnr) then
      render.append_status("Could not write implementation #" .. idx .. ".")
      return
    end
    clear_proposed_highlight(staged)
    state.staged_changes[idx] = nil
    if state.pending_blocks[idx] then
      state.pending_blocks[idx].applied = true
    end
    render.append_status("Accepted implementation #" .. idx .. " and wrote the source buffer.")
    vim.notify("[chatforge] Accepted implementation #" .. idx, vim.log.levels.INFO)
    return
  end

  local block = state.pending_blocks[idx]
  if block and block.stageable == false then
    vim.notify("[chatforge] That block is an example, not a staged implementation.", vim.log.levels.INFO)
    return
  end

  if block then
    vim.notify("[chatforge] Implementation #" .. idx .. " is not staged in the source buffer yet.", vim.log.levels.WARN)
  else
    vim.notify("[chatforge] No pending implementation #" .. idx .. ".", vim.log.levels.WARN)
  end
end

function M.stage_preview(idx)
  if block_while_applying("staging another change") then
    return
  end

  if state.staged_changes[idx] then
    return
  end

  local block = state.pending_blocks[idx]
  if not block or block.stageable == false then
    return
  end

  local lines, err = get_block_lines(idx)
  if err then
    vim.notify("[chatforge] " .. err, vim.log.levels.WARN)
    return
  end

  local bufnr = target_bufnr_for_block(idx)
  if block.target_file then
    bufnr = use_source_buffer_for_path(block.target_file)
    if not bufnr then
      return
    end
    block.target_bufnr = bufnr
    state.source_bufnr = bufnr
  end

  if not bufnr then
    vim.notify("[chatforge] Open or focus a source buffer first.", vim.log.levels.WARN)
    return
  end

  local target = block_target(idx, bufnr)
  write_lines_live(bufnr, lines, target, { highlight = true }, function(change)
    state.staged_changes[idx] = change
    render.append_status("Implementation #" .. idx .. " staged. Apply accepts; Reject restores.")
    log.log("stage_preview: block=%d bufnr=%d", idx, bufnr)
  end)
end

--- Apply block N to a specific file path (writes to disk, opens buffer).
---@param idx    number
---@param fpath  string
function M.apply_to_file(idx, fpath)
  if block_while_applying("applying") then
    return
  end

  local lines, err = get_block_lines(idx)
  if err then
    vim.notify("[chatforge] " .. err, vim.log.levels.WARN)
    return
  end

  -- Open (or create) the file in the source area and write it live.
  local bufnr = use_source_buffer_for_path(fpath)
  if not bufnr then
    return
  end

  write_lines_live(bufnr, lines, nil, { highlight = false }, function()
    write_buffer_to_disk(bufnr)
    state.pending_blocks[idx].applied = true
    vim.notify("[chatforge] Written block #" .. idx .. " -> " .. fpath, vim.log.levels.INFO)
  end)
end

--- Open a diff between block N and the current buffer in a new tab.
---@param idx number
function M.diff_with_current(idx)
  if block_while_applying("opening a diff") then
    return
  end

  local lines, err = get_block_lines(idx)
  if err then
    vim.notify("[chatforge] " .. err, vim.log.levels.WARN)
    return
  end

  local staged = state.staged_changes[idx]
  local orig_bufnr = target_bufnr_for_block(idx)
  local original_scratch = nil
  local proposed_scratch = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_lines(proposed_scratch, 0, -1, false, lines)

  if staged and staged.bufnr and vim.api.nvim_buf_is_valid(staged.bufnr) then
    original_scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(original_scratch, 0, -1, false, staged.original)
    vim.bo[original_scratch].filetype = vim.bo[staged.bufnr].filetype
    vim.bo[proposed_scratch].filetype = vim.bo[staged.bufnr].filetype
  else
    if not orig_bufnr then
      vim.notify("[chatforge] Open or focus a source buffer first.", vim.log.levels.WARN)
      return
    end
    vim.bo[proposed_scratch].filetype = vim.bo[orig_bufnr].filetype
  end

  vim.cmd("tabnew")
  if original_scratch then
    vim.api.nvim_set_current_buf(original_scratch)
    vim.bo[original_scratch].buftype = "nofile"
  else
    vim.api.nvim_set_current_buf(orig_bufnr)
  end
  vim.cmd("diffthis")
  vim.cmd("vsplit")
  vim.api.nvim_set_current_buf(proposed_scratch)
  vim.cmd("diffthis")
  vim.bo[proposed_scratch].buftype = "nofile"

  vim.notify("[chatforge] Diff opened in new tab. :tabclose when done.", vim.log.levels.INFO)
end

--- Discard all pending blocks (Reject all).
function M.reject_all()
  if block_while_applying("rejecting") then
    return
  end

  for idx, change in pairs(state.staged_changes) do
    if change.bufnr and vim.api.nvim_buf_is_valid(change.bufnr) then
      local was_modifiable = vim.bo[change.bufnr].modifiable
      vim.bo[change.bufnr].modifiable = true
      vim.api.nvim_buf_set_lines(
        change.bufnr,
        change.start_idx,
        change.start_idx + change.new_line_count,
        false,
        change.original
      )
      vim.bo[change.bufnr].modifiable = was_modifiable
      clear_proposed_highlight(change)
    end
    if state.pending_blocks[idx] then
      state.pending_blocks[idx].applied = false
    end
  end
  state.pending_blocks = {}
  state.staged_changes = {}
  state.edit_target = nil
  render.append_status("Rejected pending implementation.")
  vim.notify("[chatforge] All pending changes rejected.", vim.log.levels.INFO)
end

return M
