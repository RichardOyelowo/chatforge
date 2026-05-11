local M = {}

local state = require("chatforge.core.state")

local function notify(msg, level)
  vim.notify("[chatforge] " .. msg, level or vim.log.levels.INFO)
end

function M.ollama_status()
  if state.ollama_job and vim.fn.jobwait({ state.ollama_job }, 0)[1] == -1 then
    return "managed-running"
  end
  state.ollama_job = nil
  state.ollama_job_stopping = false
  return "not-managed"
end

function M.pull_status()
  if state.ollama_pull_job and vim.fn.jobwait({ state.ollama_pull_job }, 0)[1] == -1 then
    return "pull-running"
  end
  state.ollama_pull_job = nil
  state.ollama_pull_job_stopping = false
  return "pull-idle"
end

function M.start_ollama()
  if M.ollama_status() == "managed-running" then
    notify("ollama serve is already running from this Neovim session.")
    return
  end

  local job
  job = vim.fn.jobstart({ "ollama", "serve" }, {
    detach = false,
    stdout_buffered = false,
    stderr_buffered = false,
    on_stderr = function(_, data)
      if data and data[1] and data[1] ~= "" then
        notify("ollama: " .. data[1], vim.log.levels.DEBUG)
      end
    end,
    on_exit = function(_, code)
      if state.ollama_job == job then
        state.ollama_job = nil
      end
      local stopped = state.ollama_job_stopping
      state.ollama_job_stopping = false
      if code ~= 0 and not stopped then
        notify("ollama serve stopped with code " .. code, vim.log.levels.WARN)
      end
    end,
  })

  if job <= 0 then
    notify("Could not start `ollama serve`. Run it in a terminal.", vim.log.levels.ERROR)
    return
  end

  state.ollama_job = job
  notify("Started `ollama serve`. Stop it with :ChatBackend stop.")
end

function M.stop_ollama()
  local stopped = false
  if M.ollama_status() == "managed-running" then
    state.ollama_job_stopping = true
    vim.fn.jobstop(state.ollama_job)
    state.ollama_job = nil
    stopped = true
  end

  if state.ollama_pull_job and vim.fn.jobwait({ state.ollama_pull_job }, 0)[1] == -1 then
    state.ollama_pull_job_stopping = true
    vim.fn.jobstop(state.ollama_pull_job)
    state.ollama_pull_job = nil
    stopped = true
  end

  if not stopped then
    notify("No plugin-managed Ollama server is running.")
    return
  end

  notify("Stopped plugin-managed Ollama process.")
end

function M.offer_ollama_start(reason)
  vim.schedule(function()
    local msg = reason or "Ollama is not reachable."
    vim.ui.select({
      "Start `ollama serve` for this Neovim session",
      "Show command only",
      "Ignore",
    }, {
      prompt = msg .. " What do you want to do?",
    }, function(choice)
      if choice == "Start `ollama serve` for this Neovim session" then
        M.start_ollama()
      elseif choice == "Show command only" then
        notify("Run this in a terminal: ollama serve")
      end
    end)
  end)
end

function M.pull_ollama_model(model)
  if not model or model == "" then
    notify("No model selected to pull.", vim.log.levels.WARN)
    return
  end

  if state.ollama_pull_job and vim.fn.jobwait({ state.ollama_pull_job }, 0)[1] == -1 then
    notify("An `ollama pull` job is already running. Stop it with :ChatBackend stop.", vim.log.levels.WARN)
    return
  end

  local job
  job = vim.fn.jobstart({ "ollama", "pull", model }, {
    detach = false,
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      if data and data[1] and data[1] ~= "" then
        notify("ollama pull: " .. data[1], vim.log.levels.DEBUG)
      end
    end,
    on_stderr = function(_, data)
      if data and data[1] and data[1] ~= "" then
        notify("ollama pull: " .. data[1], vim.log.levels.DEBUG)
      end
    end,
    on_exit = function(_, code)
      if state.ollama_pull_job == job then
        state.ollama_pull_job = nil
      end
      local stopped = state.ollama_pull_job_stopping
      state.ollama_pull_job_stopping = false
      if code == 0 then
        notify("Pulled Ollama model `" .. model .. "`.")
      elseif not stopped then
        notify("`ollama pull " .. model .. "` stopped with code " .. code, vim.log.levels.WARN)
      end
    end,
  })

  if job <= 0 then
    notify("Could not run `ollama pull " .. model .. "`. Run it in a terminal.", vim.log.levels.ERROR)
    return
  end

  state.ollama_pull_job = job
  notify("Started `ollama pull " .. model .. "`. Stop it with :ChatBackend stop.")
end

function M.offer_model_pull(model, reason)
  vim.schedule(function()
    local command = "ollama pull " .. model
    vim.ui.select({
      "Run `" .. command .. "` from Neovim",
      "Show command only",
      "Ignore",
    }, {
      prompt = (reason or "Model is not available.") .. " What do you want to do?",
    }, function(choice)
      if choice == "Run `" .. command .. "` from Neovim" then
        M.pull_ollama_model(model)
      elseif choice == "Show command only" then
        notify("Run this in a terminal: " .. command)
      end
    end)
  end)
end

function M.command(arg)
  arg = (arg or "status"):lower()
  if arg == "start" then
    M.start_ollama()
  elseif arg == "stop" then
    M.stop_ollama()
  elseif arg == "status" then
    notify("Ollama backend status: server=" .. M.ollama_status() .. ", pull=" .. M.pull_status())
  else
    notify("Usage: :ChatBackend start|stop|status", vim.log.levels.WARN)
  end
end

return M
