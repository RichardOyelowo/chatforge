local M          = {}
local state      = require("chatforge.core.state")
local render     = require("chatforge.ui.render")
local client     = require("chatforge.api.client")
local dispatcher = require("chatforge.core.dispatcher")
local parser     = require("chatforge.core.parser")
local actions    = require("chatforge.core.actions")
local floating   = require("chatforge.ui.floating")
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
 
local function open_chat_win(bufnr, input_bufnr)
  vim.cmd("botright vsplit")
  local w = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(w, bufnr)
  vim.wo[w].wrap       = true
  vim.wo[w].linebreak  = true
  vim.wo[w].number     = false
  vim.wo[w].signcolumn = "no"
  vim.cmd("vertical resize 65")

  vim.cmd("botright 6split")
  local input_w = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(input_w, input_bufnr)
  vim.wo[input_w].wrap       = true
  vim.wo[input_w].linebreak  = true
  vim.wo[input_w].number     = false
  vim.wo[input_w].relativenumber = false
  vim.wo[input_w].signcolumn = "no"
  vim.wo[input_w].winfixheight = true
  vim.wo[input_w].winbar = " chatforge input  |  Enter sends  |  Esc returns to normal mode "
  vim.cmd("resize 6")

  return w, input_w
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
  vim.api.nvim_buf_set_lines(b, 0, -1, false, {})
end

local function focus_input()
  if state.input_is_open() then
    vim.api.nvim_set_current_win(state.input_winnr)
    vim.cmd("startinsert")
  end
end
 
-- ── action button activation ───────────────────────────────────────────────
 
function M.activate_cursor_button()
  local line = vim.api.nvim_get_current_line()
  if not line:match("%[ %a+ #%d+ %]") then
    vim.notify("[chatforge] No action button on this line.", vim.log.levels.INFO)
    return
  end
 
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local btn, idx
 
  for b, n in line:gmatch("%[ (%a+) #(%d+) %]") do
    local start = line:find("[ " .. b .. " #" .. n .. " ]", 1, true)
    if start and start <= col then
      btn = b:lower(); idx = tonumber(n)
    end
  end
 
  if not btn then
    local fb, fn = line:match("%[ (%a+) #(%d+) %]")
    if fb then btn = fb:lower(); idx = tonumber(fn) end
  end
 
  if not btn or not idx then
    vim.notify("[chatforge] Could not detect button under cursor.", vim.log.levels.WARN)
    return
  end
 
  if btn == "accept" or btn == "apply" then
    local target = line:match("%->%s+(%S+)")
    if target then
      vim.ui.input({ prompt = "Apply to file: ", default = target }, function(path)
        if path and path ~= "" then actions.apply_to_file(idx, path)
        else actions.apply_to_current(idx) end
      end)
    else
      actions.apply_to_current(idx)
    end
  elseif btn == "diff"    then actions.diff_with_current(idx)
  elseif btn == "yank"    then actions.yank(idx)
  elseif btn == "preview" then floating.preview(idx)
  end
end
 
-- ── send flow ──────────────────────────────────────────────────────────────
 
local function do_send(src_bufnr, input)
  if not input or input:match("^%s*$") then
    focus_input()
    return
  end

  state.source_bufnr = src_bufnr
  local model      = state.get_model(src_bufnr)
  local dispatched = dispatcher.dispatch(input, src_bufnr)
 
  render.append_user(input, model)
  state.append_message(src_bufnr, "user", dispatched.prompt)
  render.append_status("Thinking…")
 
  client.complete(src_bufnr, state.get_buf(src_bufnr).history, function(text, err)
    render.remove_last_status()
    if err then
      render.append_status("Error: " .. err, "error")
      log.err(err)
      return
    end
    state.append_message(src_bufnr, "assistant", text)
    local segments = parser.parse(text)
    state.pending_blocks = {}
    for _, seg in ipairs(segments) do
      if seg.type == "code" then
        table.insert(state.pending_blocks, { lang = seg.lang, content = seg.content, applied = false })
      end
    end
    log.log("pending_blocks=%d", #state.pending_blocks)
    render.append_segments(segments)
    focus_input()
  end)
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

  clear_input()
  do_send(state.source_bufnr or vim.api.nvim_get_current_buf(), input)
end

local function setup_input_keymaps(bufnr)
  local opts = { noremap = true, silent = true, buffer = bufnr }
  vim.keymap.set("n", "<CR>", send_from_input, opts)
  vim.keymap.set("i", "<CR>", function()
    vim.cmd("stopinsert")
    send_from_input()
  end, opts)
  vim.keymap.set("n", "<C-s>", send_from_input, opts)
  vim.keymap.set("i", "<C-s>", function()
    vim.cmd("stopinsert")
    send_from_input()
  end, opts)
end
 
-- input == nil → focus the right-side input pane
-- input == string → send directly
function M.send_message(src_bufnr, input)
  if state.loading then
    vim.notify("[chatforge] Request in progress…", vim.log.levels.WARN)
    return
  end
 
  if input then
    do_send(src_bufnr, input)
  else
    state.source_bufnr = src_bufnr
    focus_input()
  end
end
 
-- ── reset ──────────────────────────────────────────────────────────────────
 
function M.reset(src_bufnr)
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
  local winnr, input_win = open_chat_win(bufnr, input_buf)
  state.chat_bufnr = bufnr
  state.chat_winnr = winnr
  state.input_bufnr = input_buf
  state.input_winnr = input_win
  setup_input_keymaps(input_buf)
  render.write_header()
  log.log("chat open buf=%d win=%d src=%d", bufnr, winnr, src_bufnr)
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern  = tostring(winnr),
    once     = true,
    callback = function()
      state.chat_winnr = nil
      state.input_winnr = nil
      if vim.api.nvim_win_is_valid(origin_win) then
        vim.api.nvim_set_current_win(origin_win)
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern  = tostring(input_win),
    once     = true,
    callback = function()
      state.input_winnr = nil
    end,
  })
  focus_input()
end
 
return M
