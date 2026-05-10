-- Commands:
--   :Chat                   open / focus the chat window
--   :ChatSend [message]     no args = focus input pane, args = send, visual = send selection
--   :ChatSetModel [model]   set model for current buffer, or open picker
--   :ChatReset              clear history and reopen
--   :ChatActivate           activate the action button under the cursor
--   :ChatApply [N]          apply block N to current buffer (default 1)
--   :ChatDiff  [N]          diff block N against current buffer
--   :ChatYank  [N]          yank block N to unnamed register
--   :ChatPreview [N]        open block N in a floating preview window
--   :ChatReject             discard all pending blocks
 
local M = {}
 
function M.setup(opts)
  local config  = require("chatforge.config")
  local log     = require("chatforge.utils.logger")
 
  config.setup(opts)
  log.setup(config.values.debug)
 
  local chat     = require("chatforge.ui.chat")
  local actions  = require("chatforge.core.actions")
  local floating = require("chatforge.ui.floating")
  local state    = require("chatforge.core.state")
  local picker   = require("chatforge.ui.model_picker")
 
  -- ── :Chat ──────────────────────────────────────────────────────────────
  vim.api.nvim_create_user_command("Chat", function()
    chat.open()
  end, { desc = "Open chatforge window" })
 
  -- ── :ChatSend [message] ───────────────────────────────────────────────
  -- No args      → focuses the right-side input pane
  -- With args    → sends the text directly
  -- Visual range → wraps selected lines in a code block and sends
  vim.api.nvim_create_user_command("ChatSend", function(cmd)
    local src = vim.api.nvim_get_current_buf()
 
    -- Don't let src be the chat UI itself
    if state.is_plugin_buf(src) then
      src = state.source_bufnr
    end

    if not src or not vim.api.nvim_buf_is_valid(src) then
      vim.notify(
        "[chatforge] Switch to your source buffer first, then run :ChatSend.",
        vim.log.levels.WARN
      )
      return
    end
 
    local input = nil
 
    if cmd.range > 0 then
      -- Visual selection — wrap in a fenced code block
      local lines = vim.api.nvim_buf_get_lines(src, cmd.line1 - 1, cmd.line2, false)
      local ft    = vim.bo[src].filetype or ""
      input = string.format("```%s\n%s\n```", ft, table.concat(lines, "\n"))
    elseif cmd.args ~= "" then
      input = cmd.args
    end
    -- input == nil  →  send_message focuses the right-side input pane
 
    chat.open(src)
    vim.defer_fn(function()
      chat.send_message(src, input)
    end, 80)
  end, { desc = "Send a message to chatforge", nargs = "*", range = true })
 
  -- ── :ChatSetModel [model] ─────────────────────────────────────────────
  vim.api.nvim_create_user_command("ChatSetModel", function(cmd)
    local src = vim.api.nvim_get_current_buf()
    if state.is_plugin_buf(src) then
      src = state.source_bufnr or src
    end
    if cmd.args ~= "" then
      state.set_model(src, cmd.args)
      vim.notify("[chatforge] Model → " .. cmd.args, vim.log.levels.INFO)
    else
      picker.pick(src)
    end
  end, { desc = "Set AI model for current buffer", nargs = "?" })
 
  -- ── :ChatReset ────────────────────────────────────────────────────────
  vim.api.nvim_create_user_command("ChatReset", function()
    local src = vim.api.nvim_get_current_buf()
    if state.is_plugin_buf(src) then
      src = state.source_bufnr or src
    end
    chat.open(src)
    vim.defer_fn(function() chat.reset(src) end, 80)
  end, { desc = "Reset chatforge history" })
 
  -- ── :ChatActivate ─────────────────────────────────────────────────────
  vim.api.nvim_create_user_command("ChatActivate", function()
    chat.activate_cursor_button()
  end, { desc = "Activate action button under cursor" })
 
  -- ── :ChatApply [N] / :ChatAccept [N] ────────────────────────────────
  local function do_apply(cmd)
    local n = tonumber(cmd.args) or 1
    actions.apply_to_current(n)
  end
  vim.api.nvim_create_user_command("ChatApply",  do_apply, { desc = "Apply pending code block N", nargs = "?" })
  vim.api.nvim_create_user_command("ChatAccept", do_apply, { desc = "Accept pending code block N (alias for ChatApply)", nargs = "?" })
 
  -- ── :ChatDiff [N] ─────────────────────────────────────────────────────
  vim.api.nvim_create_user_command("ChatDiff", function(cmd)
    local n = tonumber(cmd.args) or 1
    actions.diff_with_current(n)
  end, { desc = "Diff pending code block N against current buffer", nargs = "?" })
 
  -- ── :ChatYank [N] ─────────────────────────────────────────────────────
  vim.api.nvim_create_user_command("ChatYank", function(cmd)
    local n = tonumber(cmd.args) or 1
    actions.yank(n)
  end, { desc = "Yank pending code block N to unnamed register", nargs = "?" })
 
  -- ── :ChatPreview [N] ──────────────────────────────────────────────────
  vim.api.nvim_create_user_command("ChatPreview", function(cmd)
    local n = tonumber(cmd.args) or 1
    floating.preview(n)
  end, { desc = "Preview pending code block N in float", nargs = "?" })
 
  -- ── :ChatReject ───────────────────────────────────────────────────────
  vim.api.nvim_create_user_command("ChatReject", function()
    actions.reject_all()
  end, { desc = "Reject all pending code blocks" })
 
  log.log("chatforge ready  default_model=%s", config.values.default_model)
end
 
function M.open() require("chatforge.ui.chat").open() end
 
return M
