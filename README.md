# <img src="images/chatforge_logo.svg">

An AI dev assistant that lives inside Neovim. Persistent chat per buffer, Ollama backend, code actions, file and directory injection, per-buffer model switching. No keymaps forced on you.

Most AI plugins give you a one-shot prompt or a floating thing that vanishes. This one stays open, remembers your full conversation per buffer, understands what you're actually trying to do — fix a bug, explain something, look at this directory — and drops the action commands right under every code block so you never have to remember a thing.

---

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [How the Chat Works](#how-the-chat-works)
- [Sending Messages](#sending-messages)
- [Working With Files and Directories](#working-with-files-and-directories)
- [How Chatforge Reads Your Intent](#how-chatforge-reads-your-intent)
- [Code Blocks and Actions](#code-blocks-and-actions)
- [Floating Code Preview](#floating-code-preview)
- [Model Picker](#model-picker)
- [Commands](#commands)
- [Setting Up Keymaps](#setting-up-keymaps)
- [Project Layout](#project-layout)
- [Adding Another Backend](#adding-another-backend)
- [Troubleshooting](#troubleshooting)
- [Known Limitations](#known-limitations)

---

## Requirements

- Neovim >= 0.10
- [Ollama](https://ollama.com) running locally — default `localhost:11434`
- `curl` in `$PATH`

Optional but worth having:
- [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim) — chat buffer is `filetype=markdown` so it just picks it up automatically
- [dressing.nvim](https://github.com/stevearc/dressing.nvim) — nicer vim.ui overall

---

## Installation
**If you want no automatic context at all** — just ask a plain question that doesn't start with `fix`, `explain`, or `refactor`. chatforge only injects context when the phrasing suggests you're working on the current file.

---

### lazy.nvim

```lua
{
  "RichardOyelowo/chatforge.nvim",

  cmd = {
    "Chat", "ChatSend", "ChatSetModel", "ChatReset",
    "ChatActivate", "ChatApply", "ChatAccept",
    "ChatDiff", "ChatYank", "ChatPreview", "ChatReject",
  },

  config = function()
    require("chatforge").setup({
      default_model = "llama3",
      ollama_url    = "http://localhost:11434",
    })
  end,
}
```

The `cmd` list lazy-loads the plugin on first command. Swap it for `event = "VeryLazy"` if you'd rather it load on startup.

---

## Configuration

Everything optional. Defaults shown:

```lua
require("chatforge").setup({
  default_model = "llama3",
  ollama_url    = "http://localhost:11434",
  max_tokens    = 4096,
  temperature   = 0.2,
  debug         = false,
  system_prompt = "You are a helpful coding assistant embedded in Neovim. "
               .. "Be concise. Use fenced code blocks with language tags for all code. "
               .. "When suggesting file changes, clearly state the filename.",
})
```

`debug = true` turns on `[chatforge]` notifications at every step — request sent, response received, blocks parsed. Use it when something isn't working and you want to trace where it breaks.

---

## How the Chat Works

`:Chat` opens a vertical split on the right. The buffer is `filetype=markdown` and read-only — it's a display surface, not an input field. You send messages with `:ChatSend`, not by typing in the buffer.

Conversation is stored per source buffer. Whichever buffer you had open when you ran `:Chat` owns that session. Open a chat from `init.lua` and another from `server.go` — they each get their own history and their own model selection. Nothing bleeds between them.

**Code the model writes is highlighted green.** Code you send is shown with the default blockquote style. At the end of every response that contains code, chatforge shows you exactly which commands are available for that response — you never have to guess.

---

## Sending Messages

There are three ways, pick whichever suits the moment:

**Floating input** — `:ChatSend` with no arguments opens a small floating window in insert mode. `<Enter>` sends, `<Esc>` cancels. This is the main way to have a back-and-forth conversation.

**Inline** — `:ChatSend fix the null check in the auth handler` if you already know what you want to say and don't need the prompt.

**Visual selection** — highlight lines in visual mode then `:'<,'>ChatSend`. The selected code gets wrapped in a fenced block with the correct filetype and sent. Good for asking about a specific function without having to describe where it is or copy-paste anything.

---

## Working With Files and Directories

This is where chatforge gets a lot more useful than just a chat window. You can pull any file or directory listing directly into your message using `@file` and `@dir` — chatforge reads them off disk and injects their contents into the prompt before it goes to the model.

### @file — pull a file into the conversation

The basic idea: anywhere you'd normally have to paste code or describe what's in a file, just reference it directly.

```
:ChatSend explain @file lua/chatforge/core/parser.lua
```

chatforge reads `parser.lua`, wraps it in a fenced code block with the correct filetype, and injects it into the prompt. The model sees the actual file contents — not a description of it, the real code.

```
:ChatSend there's a bug somewhere in @file src/auth/middleware.go can you find it
```

```
:ChatSend @file config/database.yml is there anything wrong with this config
```

The `@file` can go anywhere in the message — start, middle, end, doesn't matter. And you can use multiple in one message:

```
:ChatSend compare @file src/old_parser.lua and @file src/new_parser.lua
```

Both files get resolved before the message goes out. The model sees both.

**Paths are relative to Neovim's cwd.** Run `:pwd` if you're not sure where that is. `@file ~/.config/nvim/init.lua` with an absolute path or `~` expansion works too.

### @dir — give the model a view of a directory

```
:ChatSend @dir lua/chatforge give me an overview of how this codebase is structured
```

chatforge lists the directory one level deep — each entry marked `f` for file or `d` for directory. The model gets a clear picture of what's there without you having to paste a tree manually or describe the structure yourself.

```
:ChatSend what's in @dir src/components and which ones look like they handle state
```

```
:ChatSend @dir . what should I clean up in this project root
```

Like `@file`, `@dir` can go anywhere in the message and you can use multiple.

### Combining @file and @dir

```
:ChatSend here's the project @dir lua/chatforge and here's the file I'm working on @file lua/chatforge/ui/chat.lua — what's the best place to add streaming support
```

Both get resolved and injected. The model sees the directory structure and the specific file in one prompt.

**Both are case-insensitive** — `@FILE`, `@File`, `@file` all work the same. If a path can't be read, chatforge drops an inline comment into the prompt explaining what failed so the model can acknowledge it rather than silently pretending the file doesn't exist.

---

## How Chatforge Reads Your Intent

Beyond `@file` and `@dir`, chatforge also reads the start of your message to figure out what you're trying to do and automatically adds the right context before sending.

If you're in a file and you say `fix`, `explain`, or `refactor`, chatforge injects the entire current buffer into the prompt for you:

```
:ChatSend fix the edge case in the pattern match
```

If you're currently editing `lua/chatforge/core/parser.lua`, that message becomes:

```
:ChatSend fix the edge case in the pattern match
```

If you're currently editing `lua/chatforge/core/parser.lua`, that message becomes:

fix the edge case in the pattern match

File: lua/chatforge/core/parser.lua

```lua
-- entire file contents here
```

You didn't have to paste the code. You didn't have to say which file. The model gets exactly what it needs to give you a useful answer.

This automatic injection happens for:

| What you type | What gets added |
|---|---|
| `fix …` | Current buffer contents + filename |
| `explain …` | Current buffer contents + filename |
| `refactor …` | Current buffer contents + filename |
| `edit file <path>` | Current buffer contents |
| `create file <path>` | Nothing extra |
| `delete file <path>` | Nothing extra |
| Anything else | Sent as-is |

**If you want to ask about a different file** not the one you currently have open use `@file` explicitly. That overrides the auto-injection and lets you point at anything:

```
-- you're in init.lua but want to ask about parser.lua
:ChatSend fix the edge case in @file lua/chatforge/core/parser.lua
```

**If you want no automatic context at all** just ask a plain question that doesn't start with `fix`, `explain`, or `refactor`. chatforge only injects context when the phrasing suggests you're working on the current file.

---


## Code Blocks and Actions

Every response that has code ends with a command hint line:

```
  :ChatPreview   :ChatApply   :ChatDiff   :ChatReject
```

If there are multiple blocks:

```
  :ChatPreview 1   :ChatPreview 2   :ChatPreview 3
  :ChatApply N   :ChatDiff N   :ChatReject
```

**`:ChatApply N`** / **`:ChatAccept N`** — replaces the current buffer with block N. chatforge won't let you accidentally apply to the chat buffer itself.

**`:ChatDiff N`** — opens a tab with a side-by-side diff between your current buffer and block N. `:tabclose` when done.

**`:ChatYank N`** — yanks the block to the unnamed register. `p` it wherever you want.

**`:ChatReject`** — discards all pending blocks from the last response.

**`:ChatPreview N`** — opens the block in a floating window. See below.

Block numbers are just the order they appeared in the response — first code block is 1, second is 2.

---

## Floating Code Preview

`:ChatPreview N` opens the code block in a centred floating window with full syntax highlighting. A `lua` block opens with `filetype=lua`, `python` with `filetype=python`, and so on — whatever the model tagged the fenced block with.

A small action bar sits below it:

```
  a Apply   d Diff   y Yank   q Close   (block #1)
```

- `a` — applies to current buffer, closes the float
- `d` — opens diff tab, closes the float
- `y` — yanks to register, float stays open
- `q` or `<Esc>` — closes without doing anything

The float closes on its own if focus moves away.

---

## Model Picker

`:ChatSetModel` without a name opens a native floating picker that fetches your installed models from Ollama's API. Current model is marked ✓. Navigate with `j`/`k`, confirm with `<CR>`, cancel with `q` or `<Esc>`.

`:ChatSetModel codestral` skips the picker and sets it directly.

Model selection is per buffer. One buffer can use `codestral` while another uses `llama3` — state is stored per source buffer.

If Ollama isn't reachable the picker falls back to just showing the configured default so you're not stuck.

---

## Commands

| Command | What it does |
|---|---|
| `:Chat` | Open or focus the chat window |
| `:ChatSend [message]` | No args = floating prompt. With args = send directly |
| `:ChatSetModel [name]` | No args = floating picker. With name = set directly |
| `:ChatReset` | Clear history, reopen chat |
| `:ChatActivate` | Activate the action button under cursor |
| `:ChatApply [N]` | Apply block N to current buffer. Default 1 |
| `:ChatAccept [N]` | Same as `:ChatApply` |
| `:ChatDiff [N]` | Diff block N against current buffer |
| `:ChatYank [N]` | Yank block N to register |
| `:ChatPreview [N]` | Preview block N in floating window |
| `:ChatReject` | Discard all pending blocks |

---

## Setting Up Keymaps

No keymaps set by default. Here's a starting point:

```lua
vim.keymap.set("n", "<leader>ac", "<cmd>Chat<cr>",         { desc = "chatforge open" })
vim.keymap.set("n", "<leader>as", "<cmd>ChatSend<cr>",     { desc = "chatforge send" })
vim.keymap.set("n", "<leader>am", "<cmd>ChatSetModel<cr>", { desc = "chatforge model" })

-- visual selection → send as code block
vim.keymap.set("v", "<leader>as", ":'<,'>ChatSend<cr>",    { desc = "chatforge send selection" })
```

---

## Project Layout

```
lua/chatforge/
  init.lua              entry point — setup(), all command registrations
  config.lua            defaults + M.setup()

  ui/
    chat.lua            chat buffer, floating input, send flow
    render.lua          markdown rendering, green code highlights, action hints
    model_picker.lua    native floating model picker, fetches from Ollama
    floating.lua        syntax-highlighted code preview popup + action bar

  core/
    state.lua           per-buffer { model, history } + pending_blocks
    dispatcher.lua      @file/@dir injection, intent classification, context enrichment
    parser.lua          splits AI response into text / code / action segments
    actions.lua         apply / diff / yank / reject_all

  api/
    client.lua          unified send — picks backend, prepends system prompt
    backends.lua        Ollama HTTP via curl
    prompts.lua         optional prompt templates

  utils/
    buffer.lua          get_content, get_visual_selection, get_name, get_filetype
    window.lua          open_float / close_float helpers
    logger.lua          log / warn / err — gated by config.debug
```

---

## Adding Another Backend

`api/backends.lua` has a registry. Add an entry with the same contract:

```lua
local openai = {}

function openai.ask(base_url, model, messages, on_done)
  -- on_done(text, nil) on success
  -- on_done(nil, err_string) on failure
  -- must be async — use vim.system
end

local registry = {
  ollama = ollama,
  openai = openai,
}
```

Then in `api/client.lua` change `backends.get("ollama")` to read from `config.values.backend`. Nothing else in the stack needs to change.

---

## Troubleshooting

**`Ollama unreachable`**
Make sure `ollama serve` is running. Check `ollama_url` in your config matches where it's listening.

**Model not found**
Run `ollama pull <model>` first. The picker only shows models Ollama already has downloaded.

**`No pending blocks`**
The last response had no fenced code blocks — model responded with plain text. Nothing to apply or preview.

**`Switch to your source buffer first`**
You ran `:ChatSend` or `:ChatApply` while focused on the chat buffer itself. Switch to your actual file first.

**`@file path could not be read`**
Path doesn't exist or can't be opened. Paths are relative to Neovim's cwd — `:pwd` shows you where that is.

**Debug mode**
`debug = true` in `setup()`. Every step emits a `[chatforge]` notification.

---

## Known Limitations

- No streaming — response appears all at once when the request finishes
- Only Ollama right now — adding another backend is a couple dozen lines in `backends.lua`
- Pending blocks are replaced on each new response — act on them before sending another message
- `@dir` is one level deep, no recursive tree
- No multi-buffer edits from a single response

---

**Built by Richard for the love of development.**