from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "images"
OUT.mkdir(exist_ok=True)

W, H = 1500, 900

BG = "#070a18"
TOP = "#090d20"
TAB = "#12162a"
TAB_ACTIVE = "#182039"
SIDEBAR = "#080d1c"
EDITOR = "#0b1024"
PANEL = "#0b1020"
FLOAT = "#10182c"
BORDER = "#26324d"
TEXT = "#d9e2f1"
MUTED = "#6f7b92"
GREEN = "#50fa7b"
BLUE = "#8be9fd"
PURPLE = "#bd93f9"
PINK = "#ff79c6"
YELLOW = "#f1fa8c"
ORANGE = "#ffb86c"
RED = "#ff6b6b"
CYAN = "#72e0ff"
STATUS = "#151c31"
PROPOSED = "#243b2a"
SELECTED = "#23365a"
TERMINAL = "#060914"

FONT = "/usr/share/fonts/google-noto/NotoSansMono-Regular.ttf"
BOLD = "/usr/share/fonts/google-noto/NotoSansMono-Bold.ttf"


def font(size=18, bold=False):
    return ImageFont.truetype(BOLD if bold else FONT, size)


F12 = font(12)
F13 = font(13)
F14 = font(14)
F15 = font(15)
F16 = font(16)
F18 = font(18)
F20 = font(20)
F22B = font(22, True)
F26B = font(26, True)


def t(draw, xy, s, fill=TEXT, f=F15):
    draw.text(xy, s, font=f, fill=fill)


def rounded(draw, box, fill, outline=None, radius=8, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def mono_width(s, f=F16):
    return f.getbbox(s)[2]


def code_tokens(draw, x, y, parts, f=F16):
    cur = x
    for s, color in parts:
        t(draw, (cur, y), s, color, f)
        cur += mono_width(s, f)


def shell(draw, lines):
    y = 728
    for line, color in lines[:5]:
        t(draw, (380, y), line, color, F13)
        y += 22


def chrome(title="chatforge.nvim", active="user_service.py"):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)

    d.rectangle((0, 0, W, 38), fill=TOP)
    for i, label in enumerate(["team_service.py", "org_service.py", "activity_service.py", active]):
        x = 32 + i * 185
        fill = TAB_ACTIVE if label == active else TAB
        rounded(d, (x, 4, x + 174, 35), fill, "#1f2944", 5)
        t(d, (x + 12, 12), " " + label, CYAN if label == active else MUTED, F13)
    t(d, (W - 210, 12), "lua    ", MUTED, F13)

    d.rectangle((0, 38, 48, H - 30), fill="#080c1a")
    for i, icon in enumerate(["󰈙", "󰊢", "󰘬", "󰙅", "󰒓"]):
        t(d, (15, 62 + i * 52), icon, MUTED, F18)

    d.rectangle((48, 38, 330, H - 30), fill=SIDEBAR)
    t(d, (70, 58), "LUA", MUTED, F13)
    tree = [
        ("▾ lua", MUTED),
        ("  ▾ chatforge", MUTED),
        ("    ▾ api", MUTED),
        ("      backend_control.lua", BLUE),
        ("      backends.lua", BLUE),
        ("      client.lua", BLUE),
        ("    ▾ core", MUTED),
        ("      actions.lua", BLUE),
        ("      dispatcher.lua", BLUE),
        ("      state.lua", BLUE),
        ("    ▾ ui", MUTED),
        ("      chat.lua", BLUE),
        ("      render.lua", BLUE),
        ("  ▾ images", MUTED),
        ("    demo-neovim-overview.png", GREEN),
    ]
    y = 92
    for item, color in tree:
        t(d, (72, y), item, color, F13)
        y += 25

    d.rectangle((330, 38, 1054, H - 30), fill=EDITOR)
    d.rectangle((1054, 38, W, H - 30), fill=PANEL)
    d.rectangle((0, H - 30, W, H), fill=STATUS)
    t(d, (18, H - 23), "NORMAL", BLUE, F14)
    t(d, (118, H - 23), f" {active}", TEXT, F14)
    t(d, (300, H - 23), " main", MUTED, F14)
    t(d, (W - 310, H - 23), " 0   LSP ~ pyright", BLUE, F14)
    t(d, (W - 76, H - 23), "15/1", GREEN, F14)

    t(d, (350, 58), f" {active}", MUTED, F13)
    t(d, (1080, 58), title, GREEN, F20)
    d.line((1072, 88, W - 28, 88), fill=BORDER, width=1)
    return img, d


def draw_python(draw, lines, highlights=None, selection=None, cursor_line=None):
    highlights = highlights or {}
    y0 = 92
    for i, parts in enumerate(lines, start=1):
        y = y0 + (i - 1) * 28
        if selection and selection[0] <= i <= selection[1]:
            draw.rectangle((342, y - 4, 1030, y + 24), fill=SELECTED)
        if i in highlights:
            draw.rectangle((342, y - 4, 1030, y + 24), fill=highlights[i])
        if cursor_line == i:
            draw.rectangle((344, y - 4, 352, y + 24), fill=PINK)
        t(draw, (356, y), f"{i:>2}", MUTED, F14)
        code_tokens(draw, 410, y, parts, F16)


def chat_panel(draw, messages, input_text="", status=None, actions=None, menu=None):
    y = 112
    for role, body, color in messages:
        rounded(draw, (1080, y, 1470, y + 34), "#111a2e", "#1d2944", 8)
        t(draw, (1096, y + 8), role, color, F14)
        y += 44
        for line in body.splitlines():
            t(draw, (1096, y), line, TEXT, F13)
            y += 23
        y += 18
    if status:
        t(draw, (1096, min(y, 610)), status, YELLOW, F13)
    if actions:
        ay = 598
        for action in actions:
            rounded(draw, (1090, ay, 1466, ay + 34), "#142033", "#33415f", 8)
            t(draw, (1106, ay + 9), action, GREEN if "Apply" in action else TEXT, F13)
            ay += 44
    rounded(draw, (1080, 764, 1470, 842), FLOAT, "#3a4764", 10)
    t(draw, (1098, 780), "message", MUTED, F12)
    t(draw, (1098, 808), input_text or ":ChatSend focuses this box", TEXT if input_text else MUTED, F13)
    if menu:
        rounded(draw, (1100, 602, 1468, 748), "#111827", "#40506d", 8)
        for i, item in enumerate(menu):
            color = GREEN if i == 0 else TEXT
            t(draw, (1118, 620 + i * 28), item, color, F13)


base_lines = [
    [("from uuid import UUID", BLUE)],
    [("", TEXT)],
    [("class ", PINK), ("UserService", BLUE), (":", TEXT)],
    [("    \"\"\"", GREEN)],
    [("    service class for user routes operations", GREEN)],
    [("    \"\"\"", GREEN)],
    [("", TEXT)],
    [("    async def ", PINK), ("get_user", BLUE), ("(self, user_id: UUID, db: AsyncSession) -> UserResponse:", TEXT)],
    [("        \"\"\" return a user by their id \"\"\"", GREEN)],
    [("        result = ", TEXT), ("await", PINK), (" db.execute(select(User).where(User.id == user_id))", TEXT)],
    [("        user = result.scalar_one_or_none()", TEXT)],
    [("", TEXT)],
    [("        if", PINK), (" not user:", TEXT)],
    [("            raise", PINK), (" HTTPException(status_code=", TEXT), ("404", ORANGE), (", detail=", TEXT), ("\"User not found\"", GREEN), (")", TEXT)],
    [("", TEXT)],
    [("        return", PINK), (" user", TEXT)],
]


def save_png(name, img):
    img.save(OUT / name, optimize=True)


def save_gif(name, frames, durations):
    frames[0].save(
        OUT / name,
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
        optimize=False,
        disposal=2,
    )


def overview():
    img, d = chrome()
    draw_python(d, base_lines, cursor_line=8)
    chat_panel(
        d,
        [
            ("You", "fix get_user to handle invalid UUIDs", BLUE),
            ("Assistant", "Implementation #1 staged in the source buffer.\nCode is hidden from this chat pane.", GREEN),
        ],
        input_text=":ChatSend fix invalid UUID handling",
        actions=[":ChatApply 1", ":ChatReject", ":ChatDiff 1"],
    )
    shell(d, [("Terminal", MUTED), ("git status --short", TEXT), ("M lua/chatforge/ui/chat.lua", GREEN)])
    save_png("demo-neovim-overview.png", img)


def full_workflow_gif():
    frames, durations = [], []
    staged_lines = [
        [("from uuid import UUID", BLUE)],
        [("", TEXT)],
        [("class ", PINK), ("UserService", BLUE), (":", TEXT)],
        [("    \"\"\"", GREEN)],
        [("    service class for user routes operations", GREEN)],
        [("    \"\"\"", GREEN)],
        [("", TEXT)],
        [("    async def ", PINK), ("get_user", BLUE), ("(self, user_id: UUID, db: AsyncSession) -> UserResponse:", TEXT)],
        [("        if", PINK), (" not user_id:", TEXT)],
        [("            raise", PINK), (" HTTPException(status_code=", TEXT), ("400", ORANGE), (", detail=", TEXT), ("\"Invalid user id\"", GREEN), (")", TEXT)],
        [("        result = ", TEXT), ("await", PINK), (" db.execute(select(User).where(User.id == user_id))", TEXT)],
        [("        user = result.scalar_one_or_none()", TEXT)],
        [("        if", PINK), (" not user:", TEXT)],
        [("            raise", PINK), (" HTTPException(status_code=", TEXT), ("404", ORANGE), (", detail=", TEXT), ("\"User not found\"", GREEN), (")", TEXT)],
        [("        return", PINK), (" user", TEXT)],
    ]
    flow = [
        ("Open chat beside the file", base_lines, {}, ":Chat", "chatforge opens on the right"),
        ("Write in the right-side message box", base_lines, {}, "fix get_user invalid id handling", "waiting for :ChatSend"),
        ("Request is sent", base_lines, {}, "", "Thinking..."),
        ("Generated code writes into the buffer", staged_lines[:10] + base_lines[10:], {9: PROPOSED, 10: PROPOSED}, "", "Implementing in source buffer..."),
        ("More generated lines appear live", staged_lines[:12] + base_lines[10:], {9: PROPOSED, 10: PROPOSED, 11: PROPOSED, 12: PROPOSED}, "", "Implementing in source buffer..."),
        ("Implementation is staged, not accepted", staged_lines, {9: PROPOSED, 10: PROPOSED, 11: PROPOSED, 12: PROPOSED}, "", "Implementation #1 staged."),
        ("Review commands stay in the chat pane", staged_lines, {9: PROPOSED, 10: PROPOSED, 11: PROPOSED, 12: PROPOSED}, "", ":ChatApply 1    :ChatReject    :ChatDiff 1"),
        ("Apply blends the change into the file", staged_lines, {}, "", "Accepted implementation #1."),
    ]
    for caption, lines, highlights, input_text, status in flow:
        img, d = chrome()
        draw_python(d, lines, highlights=highlights, cursor_line=8)
        chat_panel(
            d,
            [("You", caption, BLUE), ("Assistant", "Generated code is kept out of chat and staged in the file.", GREEN)],
            input_text=input_text,
            status=status,
            actions=[":ChatApply 1", ":ChatReject", ":ChatDiff 1"],
        )
        shell(d, [("Source buffer is the review surface.", GREEN), ("Chat pane keeps commands and explanations.", MUTED)])
        frames.append(img)
        durations.append(1400)
    save_gif("demo-full-chat-workflow.gif", frames, durations)


def context_gif():
    frames, durations = [], []
    steps = [
        ("Open chat panel", "", None),
        ("Focus the message box", "", None),
        ("Type @", "@", ["@file lua/chatforge/core/actions.lua", "@dir lua/chatforge", "@file README.md"]),
        ("Move through suggestions", "@", ["@dir lua/chatforge", "@file lua/chatforge/core/actions.lua", "@file README.md"]),
        ("Choose @file", "@file lua/chatforge/core/actions.lua", None),
        ("Ask with real file context", "explain @file lua/chatforge/core/actions.lua", None),
        ("Assistant responds with text only", "", None),
    ]
    for caption, input_text, menu in steps:
        img, d = chrome("chatforge.nvim")
        draw_python(d, base_lines)
        chat_panel(
            d,
            [("You", caption, BLUE), ("Assistant", "Use @file or @dir to inject real project context.", GREEN)],
            input_text=input_text,
            menu=menu,
        )
        shell(d, [("No copy/paste needed", MUTED), ("@ completion reads project paths", GREEN)])
        frames.append(img)
        durations.append(1600)
    save_gif("demo-context-completion-walkthrough.gif", frames, durations)


def staged_gif():
    frames, durations = [], []
    staged_lines = [
        [("from uuid import UUID", BLUE)],
        [("", TEXT)],
        [("class ", PINK), ("UserService", BLUE), (":", TEXT)],
        [("    \"\"\" service class for user routes operations \"\"\"", GREEN)],
        [("", TEXT)],
        [("    async def ", PINK), ("get_user", BLUE), ("(self, user_id: UUID, db: AsyncSession) -> UserResponse:", TEXT)],
        [("        if", PINK), (" not user_id:", TEXT)],
        [("            raise", PINK), (" HTTPException(status_code=", TEXT), ("400", ORANGE), (", detail=", TEXT), ("\"Invalid user id\"", GREEN), (")", TEXT)],
        [("        result = ", TEXT), ("await", PINK), (" db.execute(select(User).where(User.id == user_id))", TEXT)],
        [("        user = result.scalar_one_or_none()", TEXT)],
        [("        if", PINK), (" not user:", TEXT)],
        [("            raise", PINK), (" HTTPException(status_code=", TEXT), ("404", ORANGE), (", detail=", TEXT), ("\"User not found\"", GREEN), (")", TEXT)],
        [("        return", PINK), (" user", TEXT)],
    ]
    flow = [
        ("Ask for an implementation", base_lines, {}, "fix get_user invalid id handling", None),
        ("Ollama returns implementation", base_lines, {}, "", "Thinking..."),
        ("Writing proposed change 1/4", staged_lines[:8] + base_lines[9:], {7: PROPOSED, 8: PROPOSED}, "", "Implementing in source buffer..."),
        ("Writing proposed change 2/4", staged_lines[:10] + base_lines[10:], {7: PROPOSED, 8: PROPOSED, 9: PROPOSED, 10: PROPOSED}, "", "Implementing in source buffer..."),
        ("Proposed change staged", staged_lines, {7: PROPOSED, 8: PROPOSED, 9: PROPOSED, 10: PROPOSED}, "", "Implementation #1 staged. Apply accepts; Reject restores."),
        ("Review commands stay in chat", staged_lines, {7: PROPOSED, 8: PROPOSED, 9: PROPOSED, 10: PROPOSED}, "", "Highlighted code is still pending."),
        ("Apply accepted", staged_lines, {}, "", "Accepted implementation #1."),
        ("Reject restores original", base_lines, {}, "", "Reject restores original lines exactly."),
    ]
    for caption, lines, highlights, input_text, status in flow:
        img, d = chrome()
        draw_python(d, lines, highlights=highlights, cursor_line=8)
        chat_panel(
            d,
            [("You", "fix get_user invalid id handling", BLUE), ("Assistant", "Implementation #1 ready.\nCode is staged in the source buffer.", GREEN)],
            input_text=input_text,
            status=status,
            actions=[":ChatApply 1", ":ChatReject", ":ChatDiff 1"],
        )
        shell(d, [("Proposed lines are highlighted until Apply or Reject.", YELLOW)])
        frames.append(img)
        durations.append(1400)
    save_gif("demo-staged-apply-diff-reject.gif", frames, durations)


def selection_gif():
    frames, durations = [], []
    lines = [
        [("async def ", PINK), ("edit_user", BLUE), ("(self, user_id: UUID, update_data: UserUpdate, db: AsyncSession) -> UserResponse:", TEXT)],
        [("    result = ", TEXT), ("await", PINK), (" db.execute(select(User).where(User.id == user_id))", TEXT)],
        [("    user = result.scalar_one_or_none()", TEXT)],
        [("    if", PINK), (" not user:", TEXT)],
        [("        raise", PINK), (" HTTPException(status_code=", TEXT), ("404", ORANGE), (", detail=", TEXT), ("\"User not found\"", GREEN), (")", TEXT)],
        [("    updated_data = update_data.model_dump(exclude_unset=", TEXT), ("True", BLUE), (")", TEXT)],
        [("    return", PINK), (" user", TEXT)],
    ]
    changed = lines.copy()
    changed[5] = [("    updated_data = update_data.model_dump(exclude_unset=", TEXT), ("True", BLUE), (", exclude_none=", TEXT), ("True", BLUE), (")", TEXT)]
    flow = [
        ("Select the exact range", lines, {}, (6, 6), ":'<,'>ChatSend make selected line skip None values"),
        ("Only selected range is sent", lines, {}, (6, 6), "Rewrite only this selected range..."),
        ("Replacement writes only there", changed, {6: PROPOSED}, None, "Implementation #1 staged."),
        ("Apply keeps only that edit", changed, {}, None, "Accepted implementation #1."),
        ("Other lines never changed", changed, {}, None, "Surrounding code is untouched."),
        ("Reject would restore the selected line", lines, {}, None, "Reject restores original selected text."),
    ]
    for caption, code, highlights, selection, status in flow:
        img, d = chrome(active="user_service.py")
        draw_python(d, code, highlights=highlights, selection=selection, cursor_line=6)
        chat_panel(
            d,
            [("You", caption, BLUE), ("Assistant", "Selected-range replacement is scoped to the highlighted lines.", GREEN)],
            status=status,
            actions=[":ChatApply 1", ":ChatReject"],
        )
        frames.append(img)
        durations.append(1800)
    save_gif("demo-selection-edit-walkthrough.gif", frames, durations)


def backend_gif():
    frames, durations = [], []
    commands = [
        [(":ChatModel codestral", BLUE)],
        [(":ChatBackend status", GREEN)],
        [(":ChatBackend start", GREEN)],
        [(":ChatBackend stop", GREEN)],
        [("", TEXT)],
        [("# No keymaps are set by chatforge.", MUTED)],
        [("# Users map commands themselves.", MUTED)],
    ]
    flow = [
        ("Model selected", "codestral", "Model -> codestral"),
        ("Backend unreachable", "", "Ollama unreachable."),
        ("User chooses start", ":ChatBackend start", "Started `ollama serve`."),
        ("Missing model prompt", "", "Model missing: pull `codestral`?"),
        ("User chooses pull", "", "Started `ollama pull codestral`."),
        ("Check status", ":ChatBackend status", "server=managed-running, pull=pull-running"),
        ("Stop managed jobs", ":ChatBackend stop", "Stopped plugin-managed Ollama process."),
    ]
    for caption, input_text, status in flow:
        img, d = chrome("backend recovery")
        draw_python(d, commands)
        chat_panel(
            d,
            [
                ("System", caption, YELLOW),
                ("Choices", "Run helper from Neovim\nShow command only\nIgnore", TEXT),
            ],
            input_text=input_text,
            status=status,
            actions=[":ChatBackend status", ":ChatBackend start", ":ChatBackend stop"],
        )
        shell(d, [("User can run commands manually or let chatforge start managed jobs.", GREEN)])
        frames.append(img)
        durations.append(1600)
    save_gif("demo-backend-model-recovery.gif", frames, durations)


def no_file_touch_png():
    img, d = chrome("plain chat is safe")
    draw_python(d, base_lines)
    chat_panel(
        d,
        [
            ("You", "show me an example of a guard clause", BLUE),
            ("Assistant", "Example code #1 hidden from chat pane.\nNo file was modified.", GREEN),
        ],
        input_text="normal explanation",
    )
    shell(d, [("Plain examples do not stage source edits.", GREEN)])
    save_png("demo-safe-example-response.png", img)


if __name__ == "__main__":
    overview()
    full_workflow_gif()
    context_gif()
    staged_gif()
    selection_gif()
    backend_gif()
    no_file_touch_png()
    print("generated Neovim-style demo assets in", OUT)
