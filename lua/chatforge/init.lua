-- Commands:
--   :Chat                   open / focus the chat window
--   :ChatSend [message]     no args = focus input area, args = send, visual = send selection
--   :ChatModel [model]      set model for current buffer, or open picker
--   :ChatReset              clear history and reopen
--   :ChatApply [N]          accept staged implementation N
--   :ChatAccept             accept the first staged implementation
--   :ChatDiff  [N]          diff block N against current buffer
--   :ChatReject             discard all pending blocks
--   :ChatBackend <cmd>      manage local backend helpers
 
local M = {}
 
function M.setup(opts)
  local config  = require("chatforge.config")
  local log     = require("chatforge.utils.logger")
 
  config.setup(opts)
  log.setup(config.values.debug)
 
  local chat     = require("chatforge.ui.chat")
  local actions  = require("chatforge.core.actions")
  local state    = require("chatforge.core.state")
  local backend_control = require("chatforge.api.backend_control")

  local group = vim.api.nvim_create_augroup("chatforge_source_tracking", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = group,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      if state.is_plugin_buf(bufnr) or vim.bo[bufnr].buftype ~= "" then
        return
      end
      state.source_bufnr = bufnr
      state.source_winnr = vim.api.nvim_get_current_win()
    end,
  })
 
  -- ── :Chat ──────────────────────────────────────────────────────────────
  vim.api.nvim_create_user_command("Chat", function()
    chat.open()
  end, { desc = "Open chatforge window" })
 
  -- ── :ChatSend [message] ───────────────────────────────────────────────
  -- No args      → focuses the right-side input area
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
      -- Visual selection: wrap in a fenced code block
      local lines = vim.api.nvim_buf_get_lines(src, cmd.line1 - 1, cmd.line2, false)
      local ft    = vim.bo[src].filetype or ""
      state.edit_target = {
        bufnr = src,
        line1 = cmd.line1,
        line2 = cmd.line2,
        kind = "selection",
      }
      input = string.format(
        "Rewrite only this selected range. Return only the replacement code for these selected lines.\n\n```%s\n%s\n```",
        ft,
        table.concat(lines, "\n")
      )
    elseif cmd.args ~= "" then
      state.edit_target = nil
      input = cmd.args
    else
      state.edit_target = nil
    end
    -- input == nil  →  send_message focuses the right-side input area
 
    chat.open(src)
    vim.defer_fn(function()
      chat.send_message(src, input)
    end, 80)
  end, { desc = "Send a message to chatforge", nargs = "*", range = true })
 
  -- ── :ChatModel [model] ────────────────────────────────────────────────
  vim.api.nvim_create_user_command("ChatModel", function(cmd)
    local src = vim.api.nvim_get_current_buf()
    if state.is_plugin_buf(src) then
      src = state.source_bufnr or src
    end
    if cmd.args ~= "" then
      state.set_model(src, cmd.args)
      vim.notify("[chatforge] Model → " .. cmd.args, vim.log.levels.INFO)
    else
      vim.ui.input({ prompt = "Model: ", default = state.get_model(src) }, function(model)
        if model and model ~= "" then
          state.set_model(src, model)
          vim.notify("[chatforge] Model → " .. model, vim.log.levels.INFO)
        end
      end)
    end
  end, { desc = "Set chatforge model for current buffer", nargs = "?" })
 
  -- ── :ChatReset ────────────────────────────────────────────────────────
  vim.api.nvim_create_user_command("ChatReset", function()
    local src = vim.api.nvim_get_current_buf()
    if state.is_plugin_buf(src) then
      src = state.source_bufnr or src
    end
    chat.open(src)
    vim.defer_fn(function() chat.reset(src) end, 80)
  end, { desc = "Reset chatforge history" })
 
  -- ── :ChatApply [N] ───────────────────────────────────────────────────
  local function do_apply(cmd)
    local n = tonumber(cmd.args) or 1
    actions.apply_to_current(n)
  end
  vim.api.nvim_create_user_command("ChatApply", do_apply, { desc = "Accept staged implementation N", nargs = "?" })

  vim.api.nvim_create_user_command("ChatAccept", function()
    actions.accept_current()
  end, { desc = "Accept the first staged implementation" })
 
  -- ── :ChatDiff [N] ─────────────────────────────────────────────────────
  vim.api.nvim_create_user_command("ChatDiff", function(cmd)
    local n = tonumber(cmd.args) or 1
    actions.diff_with_current(n)
  end, { desc = "Diff pending code block N against current buffer", nargs = "?" })

  vim.api.nvim_create_user_command("ChatReviewDiff", function()
    actions.diff_current()
  end, { desc = "Diff the first staged implementation" })

  vim.api.nvim_create_user_command("ChatNextChange", function()
    actions.jump_next()
  end, { desc = "Jump to the next staged implementation line" })

  vim.api.nvim_create_user_command("ChatPrevChange", function()
    actions.jump_prev()
  end, { desc = "Jump to the previous staged implementation line" })
 
  -- ── :ChatReject ───────────────────────────────────────────────────────
  vim.api.nvim_create_user_command("ChatReject", function()
    actions.reject_all()
  end, { desc = "Reject all pending code blocks" })

  -- ── :ChatBackend start|stop|status ───────────────────────────────────
  vim.api.nvim_create_user_command("ChatBackend", function(cmd)
    backend_control.command(cmd.args)
  end, {
    desc = "Manage chatforge backend helpers",
    nargs = "?",
    complete = function()
      return { "status", "start", "stop" }
    end,
  })
 
  log.log("chatforge ready  default_model=%s", config.values.default_model)
end
 
function M.open() require("chatforge.ui.chat").open() end
 
return M
