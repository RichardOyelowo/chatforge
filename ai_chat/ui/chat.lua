local M          = {}
local state      = require("ai_chat.core.state")
local config     = require("ai_chat.config")
local render     = require("ai_chat.ui.render")
local client     = require("ai_chat.api.client")
local dispatcher = require("ai_chat.core.dispatcher")
local parser     = require("ai_chat.core.parser")
local actions    = require("ai_chat.core.actions")
local picker     = require("ai_chat.ui.model_picker")
local log        = require("ai_chat.utils.logger")

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

-- ── action-button handler ──────────────────────────────────────────────────

local function handle_action_line(line)
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local btn, idx

  for b, n in line:gmatch("%[ (%a+) #(%d+) %]") do
    local start = line:find("%[ " .. b .. " #" .. n .. " %]", 1, true)
    if start and start <= col then
      btn = b:lower()
      idx = tonumber(n)
    end
  end

  if not btn then
    local fb, fn = line:match("%[ (%a+) #(%d+) %]")
    if fb then btn = fb:lower(); idx = tonumber(fn) end
  end

  if not btn or not idx then
    vim.notify("[ai_chat] Place cursor on a button then press <CR>.", vim.log.levels.WARN)
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
  elseif btn == "diff" then
    actions.diff_with_current(idx)
  elseif btn == "yank" then
    actions.yank(idx)
  end
end

-- ── send flow ──────────────────────────────────────────────────────────────

local function send_message(src_bufnr)
  if state.loading then
    vim.notify("[ai_chat] Request in progress…", vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = "You: " }, function(input)
    if not input or input == "" then return end

    local model = state.get_model(src_bufnr)
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

      -- Rebuild pending_blocks from latest response
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
  end)
end

-- ── keymaps ────────────────────────────────────────────────────────────────

local function set_keymaps(bufnr, src_bufnr)
  local o = { noremap = true, silent = true, buffer = bufnr }

  vim.keymap.set("n", "<CR>", function()
    local line = vim.api.nvim_get_current_line()
    if line:match("%[ %a+ #%d+ %]") then
      handle_action_line(line)
    else
      send_message(src_bufnr)
    end
  end, o)

  vim.keymap.set("n", "q", function()
    if state.chat_winnr and vim.api.nvim_win_is_valid(state.chat_winnr) then
      vim.api.nvim_win_close(state.chat_winnr, true)
    end
  end, o)

  vim.keymap.set("n", "m", function() picker.pick(src_bufnr) end, o)

  vim.keymap.set("n", "R", function()
    state.clear(src_bufnr)
    state.pending_blocks = {}
    local b = state.chat_bufnr
    vim.api.nvim_buf_set_option(b, "modifiable", true)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, {})
    vim.api.nvim_buf_set_option(b, "modifiable", false)
    render.write_header()
    vim.notify("[ai_chat] Conversation reset.", vim.log.levels.INFO)
  end, o)

  vim.keymap.set("n", "?", function()
    vim.notify("[ai_chat]  <CR> send/activate | m model | R reset | q close", vim.log.levels.INFO)
  end, o)

  -- Quick action shortcuts (act on most recent = block #1 after reset)
  vim.keymap.set("n", "<leader>aa", function() actions.apply_to_current(1) end, o)
  vim.keymap.set("n", "<leader>ad", function() actions.diff_with_current(1) end, o)
  vim.keymap.set("n", "<leader>ay", function() actions.yank(1) end, o)
  vim.keymap.set("n", "<leader>ar", function() actions.reject_all() end, o)
end

-- ── public API ─────────────────────────────────────────────────────────────

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
  set_keymaps(bufnr, src_bufnr)
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