local M      = {}
local state  = require("chatforge.core.state")
local config = require("chatforge.config")
local log    = require("chatforge.utils.logger")
 
local function fetch_models(on_done)
  local url = config.values.ollama_url .. "/api/tags"
  vim.system({ "curl", "--silent", url }, { text = true }, function(result)
    if result.code ~= 0 then
      vim.schedule(function() on_done({ config.values.default_model }, nil) end)
      return
    end
    local ok, decoded = pcall(vim.json.decode, result.stdout)
    if not ok or not decoded.models then
      vim.schedule(function() on_done({ config.values.default_model }, nil) end)
      return
    end
    local names = {}
    for _, m in ipairs(decoded.models) do table.insert(names, m.name) end
    table.sort(names)
    vim.schedule(function() on_done(names, nil) end)
  end)
end
 
-- Build a native floating window picker.
local function open_float_picker(models, current, on_choice)
  local width  = 50
  local height = math.min(#models + 2, 20)  -- +2 for border padding
  local row    = math.floor((vim.o.lines   - height) / 2)
  local col    = math.floor((vim.o.columns - width)  / 2)
 
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
 
  -- Build display lines
  local display = {}
  local sel_line = 1
  for i, m in ipairs(models) do
    local marker = (m == current) and "  ✓  " or "     "
    table.insert(display, marker .. m)
    if m == current then sel_line = i end
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display)
  vim.bo[buf].modifiable = false
 
  local win = vim.api.nvim_open_win(buf, true, {
    relative  = "editor",
    width     = width,
    height    = height,
    row       = row,
    col       = col,
    style     = "minimal",
    border    = "rounded",
    title     = " chatforge · select model ",
    title_pos = "center",
  })
  vim.wo[win].cursorline = true
  vim.api.nvim_win_set_cursor(win, { sel_line, 0 })
 
  local function close() vim.api.nvim_win_close(win, true) end
 
  local function confirm()
    local idx = vim.api.nvim_win_get_cursor(win)[1]
    local choice = models[idx]
    close()
    if choice then on_choice(choice) end
  end
 
  local o = { noremap = true, silent = true, buffer = buf }
  vim.keymap.set("n", "<CR>",  confirm, o)
  vim.keymap.set("n", "q",     close,   o)
  vim.keymap.set("n", "<Esc>", close,   o)
end
 
function M.pick(src_bufnr)
  fetch_models(function(models, _)
    local current = state.get_model(src_bufnr)
    open_float_picker(models, current, function(choice)
      state.set_model(src_bufnr, choice)
      vim.notify("[chatforge] Model → " .. choice, vim.log.levels.INFO)
      log.log("model_picker: bufnr=%d model=%s", src_bufnr, choice)
    end)
  end)
end
 
return M