-- Entry point. Call require("chatforge").setup({ ... }) once in your config.
-- Commands:
--   :Chat                   open / focus the chat window
--   :ChatSend <message>     send a message (non-interactive)
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
  end, { desc = "Open AI chat window" })

  -- ── :ChatSend <message> ───────────────────────────────────────────────
  vim.api.nvim_create_user_command("ChatSend", function(cmd)
    if cmd.args == "" then
      vim.notify("[chatforge] :ChatSend requires a message.", vim.log.levels.WARN)
      return
    end
    local src = vim.api.nvim_get_current_buf()
    chat.open(src)
    vim.defer_fn(function()
      chat.send_message(src, cmd.args)
    end, 60)
  end, { desc = "Send a message to AI chat", nargs = "+" })

  -- ── :ChatSetModel [model] ─────────────────────────────────────────────
  vim.api.nvim_create_user_command("ChatSetModel", function(cmd)
    local src = vim.api.nvim_get_current_buf()
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
    chat.open(src)
    vim.defer_fn(function() chat.reset(src) end, 60)
  end, { desc = "Reset AI chat history" })

  -- ── :ChatActivate ─────────────────────────────────────────────────────
  -- Activate the action button (Accept / Diff / Yank / Preview) under cursor.
  vim.api.nvim_create_user_command("ChatActivate", function()
    chat.activate_cursor_button()
  end, { desc = "Activate AI chat action button under cursor" })

  -- ── :ChatApply [N] ────────────────────────────────────────────────────
  vim.api.nvim_create_user_command("ChatApply", function(cmd)
    local n = tonumber(cmd.args) or 1
    actions.apply_to_current(n)
  end, { desc = "Apply pending code block N to current buffer", nargs = "?" })

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
  end, { desc = "Preview pending code block N in floating window", nargs = "?" })

  -- ── :ChatReject ───────────────────────────────────────────────────────
  vim.api.nvim_create_user_command("ChatReject", function()
    actions.reject_all()
  end, { desc = "Reject all pending AI code blocks" })

  log.log("chatforge ready  default_model=%s", config.values.default_model)
end

function M.open() require("chatforge.ui.chat").open() end

return M
