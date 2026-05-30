import readline from "node:readline";
import * as Session from "../lib/es6/src/Session.mjs";
import * as SessionList from "../lib/es6/src/SessionList.mjs";

const ESC = "\x1b[";

function clear() {
  process.stdout.write(`${ESC}?25l${ESC}2J${ESC}H`);
}

function showCursor() {
  process.stdout.write(`${ESC}?25h`);
}

function inverse(text) {
  return `${ESC}7m${text}${ESC}27m`;
}

function dim(text) {
  return `${ESC}2m${text}${ESC}22m`;
}

function truncate(value, width) {
  const text = String(value ?? "")
    .replace(/\s+/g, " ")
    .trim();
  if (width <= 1) return "";
  return text.length > width ? `${text.slice(0, width - 1)}…` : text.padEnd(width, " ");
}

function wrap(text, width, maxLines) {
  const words = String(text ?? "")
    .replace(/\s+/g, " ")
    .trim()
    .split(" ")
    .filter(Boolean);
  const lines = [];
  let line = "";

  for (const word of words) {
    const next = line ? `${line} ${word}` : word;
    if (next.length > width && line) {
      lines.push(line);
      line = word;
    } else {
      line = next;
    }
    if (lines.length >= maxLines) break;
  }
  if (line && lines.length < maxLines) lines.push(line);
  return lines;
}

export function renderDetailsLines(session, width) {
  const innerWidth = Math.max(20, width - 4);
  const command = Session.copyCommand(session);
  const previewLines = wrap(session.preview, innerWidth - 2, 2);
  while (previewLines.length < 2) {
    previewLines.push("");
  }
  const line = "─".repeat(innerWidth);
  const out = [
    `┌${line}┐`,
    `│ ${truncate(`${session.tool} ${session.id}`, innerWidth - 2)} │`,
    `│ ${truncate(`Command ${command}`, innerWidth - 2)} │`,
    `│ ${truncate(`Path ${session.path}`, innerWidth - 2)} │`,
    `│ ${" ".repeat(innerWidth - 2)} │`,
  ];

  for (const previewLine of previewLines) {
    out.push(`│ ${truncate(previewLine, innerWidth - 2)} │`);
  }

  out.push(`└${line}┘`);
  return out;
}

export function selectedCommandOutput(session) {
  return Session.copyCommand(session);
}

function cwdLabel(cwd) {
  if (!cwd) return "";
  return cwd.replace(process.env.HOME || "", "~");
}

function render(state) {
  const width = Math.max(80, process.stdout.columns || 100);
  const height = Math.max(24, process.stdout.rows || 30);
  const rowsHeight = Math.max(6, height - 12);
  const now = Date.now();
  const visible = SessionList.visible(state.query, state.sessions);

  if (state.selected >= visible.length) state.selected = Math.max(0, visible.length - 1);
  if (state.selected < 0) state.selected = 0;
  if (state.selected < state.offset) state.offset = state.selected;
  if (state.selected >= state.offset + rowsHeight) state.offset = state.selected - rowsHeight + 1;

  const selected = visible[state.selected];
  const shown = visible.slice(state.offset, state.offset + rowsHeight);
  const exactW = state.showExactTime ? 19 : 0;
  const toolW = 8;
  const ageW = 9;
  const countW = 5;
  const cwdW = Math.max(14, Math.floor(width * 0.22));
  const titleW = Math.max(18, width - exactW - toolW - ageW - countW - cwdW - 11);

  clear();
  process.stdout.write(
    `resume ${dim("search coding-agent sessions")} ${state.notice ? ` ${state.notice}` : ""}\n`,
  );
  process.stdout.write(
    `Search: ${state.query}${dim("  enter print · ↑/↓ move · t timestamp · esc quit · ctrl+u clear")}\n\n`,
  );
  const exactHeader = state.showExactTime ? `${truncate("Timestamp", exactW)} ` : "";
  process.stdout.write(
    `${exactHeader}${truncate("Tool", toolW)} ${truncate("Title", titleW)} ${truncate("Msgs", countW)} ${truncate("Updated", ageW)} ${truncate("CWD", cwdW)}\n`,
  );
  process.stdout.write(
    `${"─".repeat(Math.min(width, exactW + toolW + titleW + countW + ageW + cwdW + 5))}\n`,
  );

  if (shown.length === 0) {
    process.stdout.write(dim("No sessions match your search.\n"));
  } else {
    shown.forEach((session, index) => {
      const absoluteIndex = state.offset + index;
      const exact = state.showExactTime
        ? `${truncate(Session.exactTimestamp(session.updatedAtMs), exactW)} `
        : "";
      const row = `${exact}${truncate(session.tool, toolW)} ${truncate(session.title, titleW)} ${truncate(session.messageCount, countW)} ${truncate(Session.timeAgo(now, session.updatedAtMs), ageW)} ${truncate(cwdLabel(session.cwd), cwdW)}`;
      process.stdout.write(`${absoluteIndex === state.selected ? inverse(row) : row}\n`);
    });
  }

  process.stdout.write("\n");
  if (selected) {
    for (const line of renderDetailsLines(selected, width)) {
      process.stdout.write(`${dim(line)}\n`);
    }
  }
}

export async function runPicker(sessions) {
  if (sessions.length === 0) {
    console.log("No resumable sessions found.");
    return;
  }

  const state = { sessions, query: "", selected: 0, offset: 0, notice: "", showExactTime: false };
  const input = process.stdin;

  readline.emitKeypressEvents(input);
  input.setRawMode(true);
  input.resume();

  await new Promise((resolve) => {
    const onResize = () => render(state);

    const cleanup = () => {
      input.setRawMode(false);
      input.removeListener("keypress", onKeypress);
      process.stdout.removeListener("resize", onResize);
      showCursor();
      process.stdout.write("\n");
      resolve();
    };

    const onKeypress = async (str, key = {}) => {
      if ((key.ctrl && key.name === "c") || key.name === "escape") {
        cleanup();
        return;
      }

      const visible = SessionList.visible(state.query, state.sessions);
      if (key.name === "return") {
        const selected = visible[state.selected];
        if (selected) {
          const command = selectedCommandOutput(selected);
          cleanup();
          console.log(command);
        }
        return;
      }

      if (key.name === "down") {
        state.selected = Math.min(state.selected + 1, Math.max(0, visible.length - 1));
      } else if (key.name === "up") {
        state.selected = Math.max(0, state.selected - 1);
      } else if (key.name === "pagedown") {
        state.selected = Math.min(state.selected + 10, Math.max(0, visible.length - 1));
      } else if (key.name === "pageup") {
        state.selected = Math.max(0, state.selected - 10);
      } else if (key.name === "backspace") {
        state.query = state.query.slice(0, -1);
        state.selected = 0;
        state.offset = 0;
      } else if (key.ctrl && key.name === "u") {
        state.query = "";
        state.selected = 0;
        state.offset = 0;
      } else if (key.name === "t") {
        state.showExactTime = !state.showExactTime;
      } else if (str && !key.ctrl && !key.meta && str >= " ") {
        state.query += str;
        state.selected = 0;
        state.offset = 0;
      }

      render(state);
    };

    input.on("keypress", onKeypress);
    process.stdout.on("resize", onResize);
    render(state);
  });
}
