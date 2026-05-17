# <img src="images/chatforge_logo.svg">

An AI dev assistant that lives inside Neovim. Persistent chat per buffer, Ollama backend, code actions, file and directory injection, per-buffer model switching. No global keymaps forced on you.

Most AI plugins give you a one-shot prompt or a floating thing that vanishes. This one stays open, remembers your full conversation per buffer, understands what you're actually trying to do: fix a bug, explain something, look at this directory. It drops the action commands right under every code block so you never have to remember a thing.

---

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Demo](#demo)
- [How the Chat Works](#how-the-chat-works)
- [Sending Messages](#sending-messages)
- [Working With Files and Directories](#working-with-files-and-directories)
- [How Chatforge Reads Your Intent](#how-chatforge-reads-your-intent)
- [Code Blocks and Actions](#code-blocks-and-actions)
- [Model Selection](#model-selection)
- [Commands](#commands)
- [Keymaps](#keymaps)
- [Project Layout](#project-layout)
- [Adding Another Backend](#adding-another-backend)
- [Troubleshooting](#troubleshooting)
- [Known Limitations](#known-limitations)

---

## Requirements

- Neovim >= 0.10
- [Ollama](https://ollama.com) running locally, default `localhost:11434`
- `curl` in `$PATH`

Optional but worth having:
- [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim), chat buffer is `filetype=markdown` so it just picks it up automatically
- [dressing.nvim](https://github.com/stevearc/dressing.nvim), nicer vim.ui overall

---

## Installation

### lazy.nvim

```lua
{
  "RichardOyelowo/chatforge.nvim",

  cmd = {
    "Chat", "ChatSend", "ChatModel", "ChatReset",
    "ChatApply", "ChatDiff", "ChatReject", "ChatBackend",
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

`debug = true` turns on `[chatforge]` notifications at every step: request sent, response received, blocks parsed. Use it when something isn't working and you want to trace where it breaks.

---

## Demo

**Overview**

The chat panel lives on the right. The source buffer stays on the left.

<video src="images/demo-overview.webm" controls muted loop></video>

**Full chat workflow**

Open chat, type in the right-side input, watch generated code write into the buffer, then accept it.

<video src="images/demo-full-chat-workflow.webm" controls muted loop></video>

**Staged apply, diff, and reject**

Generated edits are staged into the source buffer first. Diff compares the original text with the proposed change. Apply accepts it. Reject restores the original lines.

<video src="images/demo-staged-apply-diff-reject.webm" controls muted loop></video>

**@file and @dir completion**

Typing `@` in the message box opens file and directory suggestions.

<video src="images/demo-context-completion.webm" controls muted loop></video>

**Selected-range edits**

Visual selection sends only the highlighted range. The replacement is staged back into that range.

<video src="images/demo-selection-edit.webm" controls muted loop></video>

**Safe examples**

Plain chat and example code stay in the chat flow. They do not modify files.

<video src="images/demo-safe-example.webm" controls muted loop></video>

**Backend and model recovery**

chatforge can prompt to start Ollama, pull a missing model, and manage backend helper jobs.

<video src="images/demo-backend-model-recovery.webm" controls muted loop></video>

---

## How the Chat Works

`:Chat` opens a styled chat panel on the right. The conversation stays text-only, and a bordered message box sits inside the panel near the bottom. `:ChatSend` with no arguments focuses that box. Run `:ChatSend` again while focused in the box to send its contents, or map that command to a key yourself.

See the [overview demo](images/demo-overview.webm) for the normal layout: source buffer on the left, chat panel on the right.

Conversation is stored per source buffer. Whichever buffer you had open when you ran `:Chat` owns that session. Open a chat from `init.lua` and another from `server.go`, and they each get their own history and model selection. Nothing bleeds between them.

Generated code stays out of the chat pane. If the response is meant to change a file, chatforge stages the code in the source buffer and highlights the proposed edit there. The chat pane shows the commands available for that response.

---

## Sending Messages

There are three ways, pick whichever suits the moment:

**Right-side input**, `:ChatSend` with no arguments focuses the message box in the chat panel. Type there, then press `<Enter>` or run `:ChatSend` again to send its contents. Typing `@` opens file and directory suggestions for `@file` and `@dir` context.

**Inline**, `:ChatSend fix the null check in the auth handler` if you already know what you want to say and don't need the prompt.

**Visual selection**, highlight lines in visual mode then `:'<,'>ChatSend`. The selected code gets wrapped in a fenced block with the correct filetype and sent. Good for asking about a specific function without having to describe where it is or copy-paste anything. See the [selected-range edit demo](images/demo-selection-edit.webm).

Plain chat and example requests do not modify files. If the model returns example code outside an edit, fix, refactor, create file, or selected-range request, chatforge keeps it as an example in the chat pane. See the [safe examples demo](images/demo-safe-example.webm).

---

## Working With Files and Directories

This is where chatforge gets a lot more useful than just a chat window. You can pull any file or directory listing directly into your message using `@file` and `@dir`. chatforge reads them off disk and injects their contents into the prompt before it goes to the model.

The input box can complete `@file` and `@dir` paths for you. See the [context completion demo](images/demo-context-completion.webm).

### @file: pull a file into the conversation

The basic idea: anywhere you'd normally have to paste code or describe what's in a file, just reference it directly.

```
:ChatSend explain @file lua/chatforge/core/parser.lua
```

chatforge reads `parser.lua`, wraps it in a fenced code block with the correct filetype, and injects it into the prompt. The model sees the actual file contents, not a description of it.

```
:ChatSend there's a bug somewhere in @file src/auth/middleware.go can you find it
```

```
:ChatSend @file config/database.yml is there anything wrong with this config
```

The `@file` can go anywhere in the message: start, middle, end, doesn't matter. And you can use multiple in one message:

```
:ChatSend compare @file src/old_parser.lua and @file src/new_parser.lua
```

Both files get resolved before the message goes out. The model sees both.

**Paths are relative to Neovim's cwd.** Run `:pwd` if you're not sure where that is. `@file ~/.config/nvim/init.lua` with an absolute path or `~` expansion works too.

### @dir: give the model a view of a directory

```
:ChatSend @dir lua/chatforge give me an overview of how this codebase is structured
```

chatforge lists the directory one level deep. Each entry is marked `f` for file or `d` for directory. The model gets a clear picture of what's there without you having to paste a tree manually or describe the structure yourself.

```
:ChatSend what's in @dir src/components and which ones look like they handle state
```

```
:ChatSend @dir . what should I clean up in this project root
```

Like `@file`, `@dir` can go anywhere in the message and you can use multiple.

### Combining @file and @dir

```
:ChatSend here's the project @dir lua/chatforge and here's the file I'm working on @file lua/chatforge/ui/chat.lua, what's the best place to add streaming support
```

Both get resolved and injected. The model sees the directory structure and the specific file in one prompt.

**Both are case-insensitive**. `@FILE`, `@File`, `@file` all work the same. If a path can't be read, chatforge drops an inline comment into the prompt explaining what failed so the model can acknowledge it rather than silently pretending the file doesn't exist.

---

## How Chatforge Reads Your Intent

Beyond `@file` and `@dir`, chatforge also reads the start of your message to figure out what you're trying to do and automatically adds the right context before sending.

If you're in a file and you say `fix`, `explain`, or `refactor`, chatforge injects the entire current buffer into the prompt for you:

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

When a response is an implementation request, chatforge stages the generated code directly into the source buffer with a proposed-change highlight before you accept it. The chat pane stays text-only and shows command hints.

See the [staged apply, diff, and reject demo](images/demo-staged-apply-diff-reject.webm).

```
  :ChatApply 1    :ChatReject    :ChatDiff 1
```

**`:ChatApply N`** accepts the staged implementation, clears the proposed-change highlight, and leaves the code in the source buffer. If the prompt came from a visual selection, only that selected range is staged and accepted.

**`:ChatDiff N`** opens a tab with a side-by-side comparison. For a staged change, it compares the original lines against the proposed implementation. `:tabclose` when done.

**`:ChatReject`** restores the original source lines and removes the staged implementation.

Block numbers are just the order they appeared in the response. First code block is 1, second is 2. Apply only accepts a block that has been staged into the source buffer.

---

## Model Selection

`:ChatModel` prompts for a model name.

`:ChatModel codestral` skips the prompt and sets it directly.

Model selection is per buffer. One buffer can use `codestral` while another uses `llama3`. State is stored per source buffer.

If Ollama is not reachable, chatforge offers to start `ollama serve`, show the command, or ignore it. If the model is missing, chatforge offers to run `ollama pull <model>`, show the command, or ignore it.

Use `:ChatBackend status` to inspect plugin-managed backend helpers. Use `:ChatBackend start` to start `ollama serve`. Use `:ChatBackend stop` to stop plugin-managed backend jobs.

See the [backend and model recovery demo](images/demo-backend-model-recovery.webm).

---

## Commands

| Command | What it does |
|---|---|
| `:Chat` | Open or focus the chat window |
| `:ChatSend [message]` | No args = focus input pane. With args = send directly |
| `:ChatModel [name]` | No args = prompt for a model. With name = set directly |
| `:ChatReset` | Clear history, reopen chat |
| `:ChatApply [N]` | Accept staged implementation N. Default 1 |
| `:ChatDiff [N]` | Diff block N against current buffer |
| `:ChatReject` | Restore original lines and discard staged changes |
| `:ChatBackend [status/start/stop]` | Inspect, start, or stop plugin-managed backend helpers |

---

## Keymaps

chatforge does not set global user keymaps. The scratch message box has buffer-local input behavior: `<Enter>` sends and `<C-j>` inserts a newline. Add your own mappings in your Neovim config if you want shortcuts outside that input box.

---

## Project Layout

```
lua/chatforge/
  init.lua              entry point, setup(), all command registrations
  config.lua            defaults + M.setup()

  ui/
    chat.lua            chat display, right-side input pane, send flow
    render.lua          text-only chat rendering and command hints

  core/
    state.lua           per-buffer { model, history } + pending_blocks
    dispatcher.lua      @file/@dir injection, intent classification, context enrichment
    parser.lua          splits AI response into text / code / action segments
    actions.lua         apply / diff / reject_all

  api/
    client.lua          unified send, picks backend, prepends system prompt
    backends.lua        Ollama HTTP via curl
    backend_control.lua start, stop, and inspect plugin-managed Ollama jobs
    prompts.lua         optional prompt templates

  utils/
    buffer.lua          get_content, get_visual_selection, get_name, get_filetype
    logger.lua          log / warn / err, gated by config.debug
```

---

## Adding Another Backend

`api/backends.lua` has a registry. Add an entry with the same contract:

```lua
local openai = {}

function openai.ask(base_url, model, messages, on_done)
  -- on_done(text, nil) on success
  -- on_done(nil, err_string) on failure
  -- must be async, use vim.system
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
chatforge will ask whether to start `ollama serve`, show the command, or ignore it. You can also run `:ChatBackend start` yourself. Stop plugin-managed Ollama with `:ChatBackend stop`.

**Model not found**
chatforge will ask whether to run `ollama pull <model>`, show the command, or ignore it. Stop a plugin-managed pull with `:ChatBackend stop`.

**`No pending blocks`**
The last response had no fenced code blocks. The model responded with plain text. Nothing to apply or preview.

**`Open or focus a source buffer first`**
chatforge could not find the file buffer that should receive an apply or diff. Open the target file, then run `:Chat`.

**`@file path could not be read`**
Path doesn't exist or can't be opened. Paths are relative to Neovim's cwd. `:pwd` shows you where that is.

**Debug mode**
`debug = true` in `setup()`. Every step emits a `[chatforge]` notification.

---

## Known Limitations

- Ollama response text is non-streaming right now; proposed code is staged live once the response returns
- Only Ollama right now. Adding another backend is a couple dozen lines in `backends.lua`
- Pending blocks are replaced on each new response. Act on them before sending another message
- `@dir` is one level deep, no recursive tree
- No multi-buffer edits from a single response

---

**Built by Richard for the love of development.**
