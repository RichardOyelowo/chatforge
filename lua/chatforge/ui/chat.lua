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
  vim.api.nvim_buf_set_name(b, "AI Chat")
  vim.bo[b].filetype   = "markdown"
  vim.bo[b].buftype    = "nofile"
  vim.bo[b].swapfile   = false
  vim.bo[b].modifiable = false
  return b
end

local function create_input_buf()
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(b, "AI Chat Input")
  vim.bo[b].filetype   = "markdown"
  vim.bo[b].buftype    = "nofile"
  vim.bo[b].bufhidden  = "hide"
  vim.bo[b].swapfile   = false
  vim.bo[b].modifiable = true
  return b
end
 
local function open_chat_win(bufnr)
  vim.cmd("botright vsplit")
  local w = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(w, bufnr)
  vim.wo[w].wrap       = true
  vim.wo[w].linebreak  = true
  vim.wo[w].number     = false
  vim.wo[w].signcolumn = "no"
  vim.wo[w].winbar     = " chatforge "
  vim.cmd("vertical resize 65")

  return w
end

local function input_window_opts()
  local width = math.max(vim.api.nvim_win_get_width(state.chat_winnr) - 4, 24)
  local height = 4
  local chat_height = vim.api.nvim_win_get_height(state.chat_winnr)
  return {
    relative = "win",
    win = state.chat_winnr,
    row = math.max(chat_height - height - 2, 1),
    col = 1,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " message ",
    title_pos = "left",
  }
end

local function open_input_win(input_bufnr)
  local input_w = vim.api.nvim_open_win(input_bufnr, false, input_window_opts())
  vim.wo[input_w].wrap       = true
  vim.wo[input_w].linebreak  = true
  vim.wo[input_w].number     = false
  vim.wo[input_w].relativenumber = false
  vim.wo[input_w].signcolumn = "no"
  vim.wo[input_w].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"
  return input_w
end

-- ── right-side input pane ─────────────────────────────────────────────────

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
  local b = state.input_bufnr
  if not b or not vim.api.nvim_buf_is_valid(b) then return end
  vim.bo[b].modifiable = true
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { "" })
  if state.input_is_open() then
    vim.api.nvim_win_set_cursor(state.input_winnr, { 1, 0 })
  end
end

local function completion_items()
  local cwd = vim.fn.getcwd()
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
    local line = vim.api.nvim_get_current_line()
    local col = vim.fn.col(".") - 1
    local prefix = completion_prefix(line, col)
    if not prefix then return end
    local start_col = col - #prefix + 1
    local filtered = {}
    for _, item in ipairs(completion_items()) do
      if item.word:lower():find(prefix:lower(), 1, true) == 1 then
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
      local line = vim.api.nvim_get_current_line()
      local col = vim.fn.col(".") - 1
      if completion_prefix(line, col) then
        trigger_at_completion()
      end
    end,
  })
end

local function focus_input()
  if state.input_bufnr and vim.api.nvim_buf_is_valid(state.input_bufnr) and state.chat_is_open() and not state.input_is_open() then
    state.input_winnr = open_input_win(state.input_bufnr)
  end

  if state.input_is_open() then
    vim.api.nvim_set_current_win(state.input_winnr)
    vim.cmd("startinsert")
  end
end

local function has_staged_changes()
  for _ in pairs(state.staged_changes) do
    return true
  end
  return false
end

local function request_history(src_bufnr, current_prompt)
  local history = {}
  for _, msg in ipairs(state.get_buf(src_bufnr).history) do
    table.insert(history, { role = msg.role, content = msg.content })
  end
  table.insert(history, { role = "user", content = current_prompt })
  return history
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
    state.append_message(src_bufnr, "user", input)
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
        table.insert(state.pending_blocks, {
          lang = seg.lang,
          content = seg.content,
          applied = false,
          stageable = should_stage,
          target = edit_target,
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
  end)

  return true
end

local function send_from_input()
  if state.loading then
    vim.notify("[chatforge] Request in progress...", vim.log.levels.WARN)
    return
  end

  local b = state.input_bufnr
  if not b or not vim.api.nvim_buf_is_valid(b) then return end

  local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
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
  vim.keymap.set("i", "<CR>", function()
    vim.cmd("stopinsert")
    send_from_input()
  end, opts)
  vim.keymap.set("i", "<C-j>", function()
    vim.api.nvim_put({ "" }, "l", true, true)
  end, opts)
end

-- input == nil: focus the right-side input pane
-- input == string: send directly
function M.send_message(src_bufnr, input)
  if state.loading then
    vim.notify("[chatforge] Request in progress…", vim.log.levels.WARN)
    return
  end
 
  if input then
    do_send(src_bufnr, input)
  else
    if vim.api.nvim_get_current_buf() == state.input_bufnr then
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
    vim.api.nvim_buf_set_option(b, "modifiable", false)
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
    focus_input()
    return
  end
  local origin_win = vim.api.nvim_get_current_win()
  local bufnr      = create_chat_buf()
  local input_buf  = create_input_buf()
  local winnr      = open_chat_win(bufnr)
  state.chat_bufnr = bufnr
  state.chat_winnr = winnr
  state.input_bufnr = input_buf
  state.input_winnr = open_input_win(input_buf)
  setup_input_autocmds(input_buf)
  setup_input_keymaps(input_buf)
  render.write_header()
  log.log("chat open buf=%d win=%d src=%d", bufnr, winnr, src_bufnr)
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern  = tostring(winnr),
    once     = true,
    callback = function()
      state.chat_winnr = nil
      state.input_winnr = nil
      state.input_bufnr = nil
      state.chat_bufnr = nil
      if vim.api.nvim_buf_is_valid(input_buf) then
        pcall(vim.api.nvim_buf_delete, input_buf, { force = true })
      end
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
