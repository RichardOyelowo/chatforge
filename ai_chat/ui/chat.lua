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

local function open_chat_win(bufnr)
  vim.cmd("botright vsplit")
  local w = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(w, bufnr)
  vim.wo[w].wrap       = true
  vim.wo[w].linebreak  = true
  vim.wo[w].number     = false
  vim.wo[w].signcolumn = "no"
  vim.cmd("vertical resize 65")
  return w
end

-- ── action button activation ───────────────────────────────────────────────
-- Reads the line under the cursor, figures out which button and block index,
-- then dispatches to the right action. Call this from whatever keymap sets (e.g. <CR>).

function M.activate_cursor_button()
  local line = vim.api.nvim_get_current_line()
  if not line:match("%[ %a+ #%d+ %]") then
    vim.notify("[chatforge] No action button on this line.", vim.log.levels.INFO)
    return
  end

  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local btn, idx

  for b, n in line:gmatch("%[ (%a+) #(%d+) %]") do
    local start = line:find("%[ " .. b .. " #" .. n .. " %]", 1, true)
    if start and start <= col then
      btn = b:lower()
      idx = tonumber(n)
    end
  end

  -- fallback: pick first button on the line
  if not btn then
    local fb, fn = line:match("%[ (%a+) #(%d+) %]")
    if fb then btn = fb:lower(); idx = tonumber(fn) end
  end

  if not btn or not idx then
    vim.notify("[chatforge] Could not detect button under cursor.", vim.log.levels.WARN)
    return
  end

  if btn == "accept" then
    local target = line:match("%->%s+(%S+)")
    if target then
      vim.ui.input({ prompt = "Apply to file: ", default = target }, function(path)
        if path and path ~= "" then actions.apply_to_file(idx, path)
        else                        actions.apply_to_current(idx) end
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

function M.send_message(src_bufnr, prefilled_input)
  if state.loading then
    vim.notify("[chatforge] Request in progress…", vim.log.levels.WARN)
    return
  end

  local function do_send(input)
    if not input or input == "" then return end

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
          table.insert(state.pending_blocks, {
            lang    = seg.lang,
            content = seg.content,
            applied = false,
          })
        end
      end
      log.log("pending_blocks=%d", #state.pending_blocks)
      render.append_segments(segments)
    end)
  end

  if prefilled_input then
    do_send(prefilled_input)
  else
    vim.ui.input({ prompt = "You: " }, do_send)
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
  vim.notify("[chatforge] Conversation reset.", vim.log.levels.INFO)
end

-- ── public open ────────────────────────────────────────────────────────────

function M.open(src_bufnr)
  src_bufnr = src_bufnr or vim.api.nvim_get_current_buf()

  if state.chat_is_open() then
    vim.api.nvim_set_current_win(state.chat_winnr)
    return
  end

  local origin_win = vim.api.nvim_get_current_win()
  local bufnr      = create_chat_buf()
  local winnr      = open_chat_win(bufnr)

  state.chat_bufnr = bufnr
  state.chat_winnr = winnr

  render.write_header()
  log.log("chat open buf=%d win=%d src=%d", bufnr, winnr, src_bufnr)

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern  = tostring(winnr),
    once     = true,
    callback = function()
      state.chat_winnr = nil
      if vim.api.nvim_win_is_valid(origin_win) then
        vim.api.nvim_set_current_win(origin_win)
      end
    end,
  })
end

return M
