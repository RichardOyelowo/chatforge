local M          = {}
local state      = require("chatforge.core.state")
local render     = require("chatforge.ui.render")
local client     = require("chatforge.api.client")
local dispatcher = require("chatforge.core.dispatcher")
local parser     = require("chatforge.core.parser")
local actions    = require("chatforge.core.actions")
local log        = require("chatforge.utils.logger")
 
-- ── buffer / window ────────────────────────────────────────────────────────
 
local function create_chat_buf()
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(b, "chatforge://chat")
  vim.bo[b].filetype   = "markdown"
  vim.bo[b].buftype    = "nofile"
  vim.bo[b].swapfile   = false
  vim.bo[b].modifiable = true
  return b
end

local completion_cache_cwd = nil
local completion_cache_items = nil

local function open_chat_window(chat_bufnr)
  vim.cmd("botright vsplit")
  local chat_w = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(chat_w, chat_bufnr)
  vim.wo[chat_w].wrap       = true
  vim.wo[chat_w].linebreak  = true
  vim.wo[chat_w].number     = false
  vim.wo[chat_w].relativenumber = false
  vim.wo[chat_w].signcolumn = "no"
  vim.wo[chat_w].winbar     = " chatforge "
  vim.cmd("vertical resize 65")
  return chat_w
end

-- ── right-side input area ─────────────────────────────────────────────────

local function trim_lines(lines)
  local first, last = 1, #lines
  while first <= last and lines[first]:match("^%s*$") do first = first + 1 end
  while last >= first and lines[last]:match("^%s*$") do last = last - 1 end
  if first > last then return "" end
  local out = {}
  for i = first, last do table.insert(out, lines[i]) end
  return table.concat(out, "\n")
end

local function clear_input()
  local b = state.chat_bufnr
  if not b or not vim.api.nvim_buf_is_valid(b) then return end
  state.input_lines = { "" }
  render.redraw_input(state.input_lines)
  if state.input_is_open() then
    vim.api.nvim_win_set_cursor(state.chat_winnr, { state.input_start_line, 3 })
  end
end

local function input_cursor_ok()
  if not state.input_is_open() then
    return false
  end
  local cursor = vim.api.nvim_win_get_cursor(state.chat_winnr)
  return cursor[1] >= state.input_start_line and cursor[1] <= state.input_end_line
end

local function set_chat_modifiable(enabled)
  if state.chat_bufnr and vim.api.nvim_buf_is_valid(state.chat_bufnr) then
    vim.bo[state.chat_bufnr].modifiable = true
  end
end

local function completion_items()
  local cwd = vim.fn.getcwd()
  if completion_cache_cwd == cwd and completion_cache_items then
    return completion_cache_items
  end

  local found = vim.fn.globpath(cwd, "**/*", false, true)
  local items = {}
  local dirs = {}
  local files = {}
  local limit = 80

  for _, path in ipairs(found) do
    if not path:match("/%.git/") then
      local rel = vim.fn.fnamemodify(path, ":.")
      if vim.fn.isdirectory(path) == 1 then
        table.insert(dirs, { word = "@dir " .. rel, menu = "dir" })
      else
        table.insert(files, { word = "@file " .. rel, menu = "file" })
      end
    end
  end

  table.sort(dirs, function(a, b) return a.word < b.word end)
  table.sort(files, function(a, b) return a.word < b.word end)

  table.insert(items, { word = "@file ", menu = "chatforge" })
  table.insert(items, { word = "@dir ", menu = "chatforge" })

  for _, item in ipairs(dirs) do
    if #items >= limit then break end
    table.insert(items, item)
  end

  for _, item in ipairs(files) do
    if #items >= limit then break end
    table.insert(items, item)
  end

  completion_cache_cwd = cwd
  completion_cache_items = items
  return items
end

local function completion_prefix(line, col)
  local before = line:sub(1, col)
  return before:match("(@[fF][iI][lL][eE]%s+%S*)$")
    or before:match("(@[dD][iI][rR]%s+%S*)$")
    or before:match("(@%S*)$")
end

local function trigger_at_completion()
  vim.schedule(function()
    if not state.input_is_open() then return end
    if vim.fn.pumvisible() == 1 then return end
    if not input_cursor_ok() then
      return
    end
    local line = vim.api.nvim_get_current_line():gsub("^│%s?", ""):gsub("%s*│$", "")
    local actual_col = vim.fn.col(".") - 1
    local col = math.max(actual_col - 2, 0)
    local prefix = completion_prefix(line, col)
    if not prefix then return end
    local start_col = col - #prefix + 3
    local filtered = {}
    local lower_prefix = prefix:lower()
    for _, item in ipairs(completion_items()) do
      local is_generic = item.menu == "chatforge"
        and (lower_prefix == "@file " or lower_prefix == "@dir ")
      if not is_generic and item.word:lower():find(lower_prefix, 1, true) == 1 then
        table.insert(filtered, item)
      end
    end
    if #filtered > 0 then
      vim.fn.complete(start_col, filtered)
    end
  end)
end

local function setup_input_autocmds(bufnr)
  vim.api.nvim_create_autocmd("TextChangedI", {
    buffer = bufnr,
    callback = function()
      if not state.input_is_open() then return end
      if not input_cursor_ok() then
        return
      end
      local line = vim.api.nvim_get_current_line():gsub("^│%s?", ""):gsub("%s*│$", "")
      local col = math.max(vim.fn.col(".") - 3, 0)
      if completion_prefix(line, col) then
        trigger_at_completion()
      end
    end,
  })
end

local function focus_input()
  if state.input_is_open() then
    vim.api.nvim_set_current_win(state.chat_winnr)
    vim.api.nvim_win_set_cursor(state.chat_winnr, { state.input_start_line, 3 })
    vim.cmd("startinsert")
  end
end

local function has_staged_changes()
  for _ in pairs(state.staged_changes) do
    return true
  end
  return false
end

local function nonblank_line_count(text)
  local count = 0
  for _, line in ipairs(vim.split(text or "", "\n", { plain = true })) do
    if line:match("%S") then
      count = count + 1
    end
  end
  return count
end

local function looks_like_full_file(content, src_bufnr)
  if not src_bufnr or not vim.api.nvim_buf_is_valid(src_bufnr) then
    return false
  end
  local source_lines = vim.api.nvim_buf_get_lines(src_bufnr, 0, -1, false)
  local source_nonblank = 0
  for _, line in ipairs(source_lines) do
    if line:match("%S") then
      source_nonblank = source_nonblank + 1
    end
  end
  local returned_nonblank = nonblank_line_count(content)
  local threshold = source_nonblank < 8 and source_nonblank
    or math.max(8, math.floor(source_nonblank * 0.6))
  return returned_nonblank >= threshold
end

local function request_history(src_bufnr, current_prompt)
  local history = {}
  for _, msg in ipairs(state.get_buf(src_bufnr).history) do
    table.insert(history, { role = msg.role, content = msg.content })
  end
  table.insert(history, { role = "user", content = current_prompt })
  return history
end

local function render_history(src_bufnr)
  local b = state.chat_bufnr
  if not b or not vim.api.nvim_buf_is_valid(b) then return end

  render.write_header()

  local model = state.get_model(src_bufnr)
  for _, msg in ipairs(state.get_buf(src_bufnr).history) do
    if msg.role == "user" then
      render.append_user(msg.display or msg.content, model)
    elseif msg.role == "assistant" then
      render.append_assistant_text(msg.display or msg.content)
    end
  end
end

local function read_input_lines()
  local b = state.chat_bufnr
  if not b or not vim.api.nvim_buf_is_valid(b) or not state.input_start_line then
    return { "" }
  end

  local start_idx = state.input_start_line - 1
  local end_idx = state.input_end_line
  local raw = vim.api.nvim_buf_get_lines(b, start_idx, end_idx, false)
  local lines = {}
  for _, line in ipairs(raw) do
    line = line:gsub("^│%s?", "")
    line = line:gsub("%s*│$", "")
    line = line:gsub("%s+$", "")
    table.insert(lines, line)
  end
  state.input_lines = lines
  return lines
end

local function sync_input_before_send()
  read_input_lines()
  render.redraw_input(state.input_lines)
end
 
-- ── send flow ──────────────────────────────────────────────────────────────
 
local function do_send(src_bufnr, input)
  if not input or input:match("^%s*$") then
    focus_input()
    return false
  end

  if state.applying then
    vim.notify("[chatforge] Wait for the staged implementation to finish writing.", vim.log.levels.WARN)
    focus_input()
    return false
  end

  if has_staged_changes() then
    vim.notify("[chatforge] Apply or Reject the staged change before sending another message.", vim.log.levels.WARN)
    focus_input()
    return false
  end

  state.source_bufnr = src_bufnr
  state.request_id = state.request_id + 1
  local request_id = state.request_id
  local model      = state.get_model(src_bufnr)
  local dispatched = dispatcher.dispatch(input, src_bufnr)
  local edit_target = state.edit_target
  state.edit_target = nil
  if edit_target then
    src_bufnr = edit_target.bufnr
    state.source_bufnr = src_bufnr
  end
  local should_stage = edit_target ~= nil
    or dispatched.action == "edit_file"
    or dispatched.action == "create_file"
 
  render.append_user(input, model)
  render.append_status("Thinking…")
 
  client.complete(src_bufnr, request_history(src_bufnr, dispatched.prompt), function(text, err)
    if request_id ~= state.request_id then
      return
    end
    render.remove_last_status()
    if err then
      render.append_status("Error: " .. err, "error")
      log.err(err)
      return
    end
    state.append_message(src_bufnr, "user", dispatched.prompt, input)
    state.append_message(src_bufnr, "assistant", text)
    local segments = parser.parse(text)
    state.pending_blocks = {}
    local actions_by_block = {}
    for _, seg in ipairs(segments) do
      if seg.type == "action" then
        actions_by_block[seg.block_index] = seg
      end
    end
    for _, seg in ipairs(segments) do
      if seg.type == "code" then
        local parsed_action = actions_by_block[seg.index] or {}
        local stageable = should_stage
        if should_stage and not edit_target and not parsed_action.target and not dispatched.target then
          stageable = looks_like_full_file(seg.content, src_bufnr)
        end
        table.insert(state.pending_blocks, {
          lang = seg.lang,
          content = seg.content,
          applied = false,
          stageable = stageable,
          target = edit_target,
          target_bufnr = src_bufnr,
          target_file = parsed_action.target or dispatched.target,
          action = parsed_action.action,
        })
      end
    end
    log.log("pending_blocks=%d", #state.pending_blocks)
    render.append_segments(segments)
    for i, block in ipairs(state.pending_blocks) do
      if block.stageable then
        actions.stage_preview(i)
        break
      end
    end
    if not should_stage then
      focus_input()
    end
  end, request_id)

  return true
end

local function send_from_input()
  if state.loading then
    vim.notify("[chatforge] Request in progress...", vim.log.levels.WARN)
    return
  end

  local b = state.chat_bufnr
  if not b or not vim.api.nvim_buf_is_valid(b) then return end

  sync_input_before_send()
  local lines = state.input_lines
  local input = trim_lines(lines)
  if input == "" then
    focus_input()
    return
  end

  if has_staged_changes() then
    vim.notify("[chatforge] Apply or Reject the staged change before sending another message.", vim.log.levels.WARN)
    focus_input()
    return
  end

  if do_send(state.source_bufnr or vim.api.nvim_get_current_buf(), input) then
    clear_input()
  end
end

local function setup_input_keymaps(bufnr)
  local opts = { noremap = true, silent = true, buffer = bufnr }
  vim.keymap.set("n", "<CR>", send_from_input, opts)
  vim.keymap.set("n", "i", function()
    focus_input()
  end, opts)
  vim.keymap.set("n", "a", function()
    focus_input()
  end, opts)
  vim.keymap.set("i", "<CR>", function()
    if vim.fn.pumvisible() == 1 then
      local keys = vim.api.nvim_replace_termcodes("<C-y>", true, false, true)
      vim.api.nvim_feedkeys(keys, "n", false)
      return
    end
    vim.cmd("stopinsert")
    send_from_input()
  end, opts)
  vim.keymap.set("i", "<C-j>", function()
    if not input_cursor_ok() then
      focus_input()
      return
    end
    local cursor = vim.api.nvim_win_get_cursor(0)
    if cursor[1] >= state.input_end_line then
      return
    end
    set_chat_modifiable(true)
    vim.api.nvim_put({ "│ " }, "l", true, true)
  end, opts)
  vim.keymap.set("i", "<BS>", function()
    if not input_cursor_ok() then
      focus_input()
      return
    end
    set_chat_modifiable(true)
    local keys = vim.api.nvim_replace_termcodes("<BS>", true, false, true)
    vim.api.nvim_feedkeys(keys, "n", false)
  end, opts)
end

-- input == nil: focus the right-side input area
-- input == string: send directly
function M.send_message(src_bufnr, input)
  if state.loading then
    vim.notify("[chatforge] Request in progress…", vim.log.levels.WARN)
    return
  end
 
  if input then
    do_send(src_bufnr, input)
  else
    if vim.api.nvim_get_current_buf() == state.chat_bufnr then
      send_from_input()
    else
      state.source_bufnr = src_bufnr
      focus_input()
    end
  end
end
 
-- ── reset ──────────────────────────────────────────────────────────────────
 
function M.reset(src_bufnr)
  if state.applying then
    vim.notify("[chatforge] Wait for the staged implementation to finish writing before reset.", vim.log.levels.WARN)
    return
  end
  state.request_id = state.request_id + 1
  state.loading = false
  if has_staged_changes() then
    actions.reject_all()
  end
  state.clear(src_bufnr)
  state.pending_blocks = {}
  local b = state.chat_bufnr
  if b and vim.api.nvim_buf_is_valid(b) then
    vim.api.nvim_buf_set_option(b, "modifiable", true)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, {})
    render.write_header()
  end
  clear_input()
  vim.notify("[chatforge] Conversation reset.", vim.log.levels.INFO)
end
 
-- ── open ───────────────────────────────────────────────────────────────────
 
function M.open(src_bufnr)
  src_bufnr = src_bufnr or vim.api.nvim_get_current_buf()
  if not state.is_plugin_buf(src_bufnr) then
    state.source_bufnr = src_bufnr
    state.source_winnr = vim.api.nvim_get_current_win()
  end
  if state.chat_is_open() then
    if state.chat_source_bufnr ~= state.source_bufnr then
      render_history(state.source_bufnr)
      state.chat_source_bufnr = state.source_bufnr
    end
    focus_input()
    return
  end
  local origin_win = vim.api.nvim_get_current_win()
  local bufnr      = create_chat_buf()
  local winnr = open_chat_window(bufnr)
  state.chat_bufnr = bufnr
  state.chat_winnr = winnr
  state.chat_source_bufnr = state.source_bufnr
  setup_input_autocmds(bufnr)
  setup_input_keymaps(bufnr)
  render.write_header()
  log.log("chat open buf=%d win=%d src=%d", bufnr, winnr, src_bufnr)
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern  = tostring(winnr),
    once     = true,
    callback = function()
      state.chat_winnr = nil
      state.chat_bufnr = nil
      state.chat_source_bufnr = nil
      if vim.api.nvim_buf_is_valid(bufnr) then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
      if vim.api.nvim_win_is_valid(origin_win) then
        vim.api.nvim_set_current_win(origin_win)
      end
    end,
  })
  focus_input()
end
 
return M
