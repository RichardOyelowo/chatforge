-- Enriches user input before it goes to the API.
-- Handles:
--   @file path/to/file   inject that file's contents into the prompt
--   @dir  path/to/dir    inject a tree listing of the directory
--   explain / fix / refactor prefix → inject current buffer content

local M     = {}
local log   = require("chatforge.utils.logger")
local buf_u = require("chatforge.utils.buffer")

local RULES = {
  { pattern = "^create%s+file%s+(%S+)",  action = "create_file", capture = 1 },
  { pattern = "^edit%s+file%s+(%S+)",    action = "edit_file",   capture = 1 },
  { pattern = "^delete%s+file%s+(%S+)",  action = "delete_file", capture = 1 },
  { pattern = "^explain%s+",             action = "explain" },
  { pattern = "^fix%s+",                 action = "edit_file" },
  { pattern = "^refactor%s+",            action = "edit_file" },
}

local function classify(input)
  local lower = input:lower()
  for _, rule in ipairs(RULES) do
    local m = { lower:match(rule.pattern) }
    if m[1] ~= nil then
      return rule.action, rule.capture and m[rule.capture] or nil
    end
  end
  return "chat", nil
end

-- Read a file from disk and return its contents, or an error string.
-- Uses vim.fn.expand so ~, $VAR, relative, and absolute paths all work as-is.
local function read_file(path)
  local expanded = vim.fn.expand(path)
  local f, err = io.open(expanded, "r")
  if not f then return nil, "cannot open " .. expanded .. ": " .. (err or "unknown") end
  local contents = f:read("*a")
  f:close()
  return contents, nil
end

-- True when the path means "inject the currently open buffer" rather than read a real path.
local function is_current_file_ref(path)
  return path == "/" or path == "." or path == ""
end

-- Resolve a dir path relative to cwd.
-- "/" and "." both mean cwd — no way to escape outside the project root
-- by accident. "/src" means cwd/src, not filesystem /src.
local function resolve_dir_path(path)
  local cwd = vim.fn.getcwd()
  if path == "/" or path == "." or path == "" then
    return cwd
  end
  -- strip a leading slash so @dir /src means cwd/src
  local stripped = path:match("^/(.+)$")
  if stripped then
    return cwd .. "/" .. stripped
  end
  -- relative path — resolve from cwd
  return cwd .. "/" .. path
end

-- Return a simple directory listing (one level deep).
local function read_dir(path)
  local resolved = resolve_dir_path(path)
  local handle = vim.loop.fs_opendir(resolved, nil, 64)
  if not handle then return nil, "cannot open dir: " .. resolved end
  local entries, err2 = vim.loop.fs_readdir(handle)
  vim.loop.fs_closedir(handle)
  if not entries then return nil, err2 or "readdir failed" end
  local lines = { "Directory: " .. resolved }
  table.sort(entries, function(a, b) return a.name < b.name end)
  for _, e in ipairs(entries) do
    table.insert(lines, string.format("  %s  %s", e.type == "directory" and "d" or "f", e.name))
  end
  return table.concat(lines, "\n"), nil
end

-- Resolve all @file and @dir mentions in the input.
-- @file behaviours:
--   @file          (bare)   → inject current open buffer (in-memory content)
--   @file /        or .     → inject current open buffer
--   @file some/path         → read from disk via vim.fn.expand (relative or absolute)
-- @dir always resolves relative to cwd (/ and . mean cwd).
local function resolve_at_mentions(input, src_bufnr)
  local injections = {}
  local resolved   = input

  -- 1. Bare @file with no path — replace before the path-based loop
  --    Pattern: @file not followed by non-whitespace (end of string or space/newline next)
  resolved = resolved:gsub("(@[fF][iI][lL][eE])(%s+[%./]?%s*$)", function(tag, _)
    return tag .. " /"  -- normalise to @file / so the path loop handles it
  end)
  resolved = resolved:gsub("(@[fF][iI][lL][eE])%s*$", function(_)
    -- bare @file at very end of string
    local name    = buf_u.get_name(src_bufnr)
    local ft      = buf_u.get_filetype(src_bufnr)
    local content = buf_u.get_content(src_bufnr)
    table.insert(injections, { tag = "@file", path = "(current buffer)", ok = true })
    return string.format("\n\nFile: %s\n```%s\n%s\n```", name ~= "" and name or "(unnamed)", ft, content)
  end)

  -- 2. @file <path> — path ends at whitespace or end of string
  for tag, path in input:gmatch("(@[fF][iI][lL][eE]%s+(%S+))") do
    local block
    if is_current_file_ref(path) then
      -- / or . → inject current buffer content (in-memory, not read from disk)
      local name    = buf_u.get_name(src_bufnr)
      local ft      = buf_u.get_filetype(src_bufnr)
      local content = buf_u.get_content(src_bufnr)
      block = string.format("\n\nFile: %s\n```%s\n%s\n```", name ~= "" and name or "(unnamed)", ft, content)
      table.insert(injections, { tag = "@file", path = path .. " (current buffer)", ok = true })
    else
      -- explicit path — read from disk exactly as written
      local contents, err = read_file(path)
      if err then
        block = "\n<!-- @file " .. path .. " could not be read: " .. err .. " -->"
      else
        local ft = vim.filetype.match({ filename = path }) or ""
        block = string.format("\n\nFile: %s\n```%s\n%s\n```", path, ft, contents)
        table.insert(injections, { tag = "@file", path = path, ok = true })
      end
    end
    resolved = resolved:gsub(vim.pesc(tag), block, 1)
  end

  -- 3. @dir <path> — always cwd-anchored
  for tag, path in input:gmatch("(@[dD][iI][rR]%s+(%S+))") do
    local listing, err = read_dir(path)
    if err then
      local msg = "\n<!-- @dir " .. path .. " could not be read: " .. err .. " -->"
      resolved = resolved:gsub(vim.pesc(tag), msg, 1)
    else
      local block = string.format("\n\n```\n%s\n```", listing)
      resolved = resolved:gsub(vim.pesc(tag), block, 1)
      table.insert(injections, { tag = "@dir", path = path, ok = true })
    end
  end

  return resolved, injections
end

local function build_prompt(input, action, src_bufnr)
  local ft   = buf_u.get_filetype(src_bufnr)
  local name = buf_u.get_name(src_bufnr)

  if action == "edit_file" or action == "explain" then
    local content = buf_u.get_content(src_bufnr)
    if content ~= "" then
      return string.format("%s\n\nFile: %s\n```%s\n%s\n```",
        input, name ~= "" and name or "(unnamed)", ft, content)
    end
  end

  return input
end

function M.dispatch(input, src_bufnr)
  -- 1. Resolve @file / @dir mentions first
  local resolved, injections = resolve_at_mentions(input, src_bufnr)
  for _, inj in ipairs(injections) do
    log.log("dispatch: injected %s %s", inj.tag, inj.path)
  end

  -- 2. Classify action
  local action, target = classify(resolved)

  -- 3. Enrich with buffer content for edit/explain actions
  local prompt = build_prompt(resolved, action, src_bufnr)

  log.log("dispatch: action=%s target=%s", action, target or "nil")

  return { action = action, prompt = prompt, target = target }
end

return M