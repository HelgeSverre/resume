import { access, mkdir, readdir, readFile, stat, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { basename, dirname, join } from "node:path";

async function exists(path) {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

async function walkFiles(root, predicate) {
  if (!(await exists(root))) return [];
  const out = [];
  const stack = [root];

  while (stack.length > 0) {
    const dir = stack.pop();
    for (const entry of await readdir(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) {
        stack.push(path);
      } else if (entry.isFile() && predicate(path)) {
        out.push(path);
      }
    }
  }

  return out;
}

async function readText(path) {
  return readFile(path, "utf8");
}

function splitLines(text) {
  return text.split("\n");
}

function parseJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}

async function readJson(path) {
  return parseJson(await readText(path));
}

async function loadCache(home) {
  const path = join(home, ".cache", "resume", "sessions-cache-v1.json");
  const data = (await exists(path)) ? await readJson(path) : undefined;
  return {
    path,
    entries:
      data?.version === 1 && data.entries && typeof data.entries === "object" ? data.entries : {},
    used: new Set(),
    changed: false,
  };
}

async function saveCache(cache) {
  if (!cache.changed) return;
  const entries = {};
  for (const path of cache.used) {
    if (cache.entries[path]) entries[path] = cache.entries[path];
  }
  await mkdir(dirname(cache.path), { recursive: true });
  await writeFile(cache.path, JSON.stringify({ version: 1, entries }));
}

async function cachedValue(cache, path, load) {
  if (!cache) return load(path);

  const info = await stat(path);
  const entry = cache.entries[path];
  cache.used.add(path);
  if (entry && entry.mtimeMs === info.mtimeMs && entry.size === info.size) {
    return entry.value;
  }

  const value = await load(path);
  cache.entries[path] = { mtimeMs: info.mtimeMs, size: info.size, value };
  cache.changed = true;
  return value;
}

async function readJsonl(path) {
  const rows = [];

  for (const line of splitLines(await readText(path))) {
    if (line.trim() === "") continue;
    const row = parseJson(line);
    if (row) rows.push(row);
  }

  return rows;
}

function hasJsonField(line, key, value) {
  return line.includes(`"${key}":"${value}"`) || line.includes(`"${key}": "${value}"`);
}

function jsonStringField(line, key) {
  const compact = line.match(new RegExp(`"${key}":"((?:\\\\.|[^"\\\\])*)"`));
  const spaced = compact ?? line.match(new RegExp(`"${key}"\\s*:\\s*"((?:\\\\.|[^"\\\\])*)"`));
  if (!spaced) return undefined;
  return parseJson(`"${spaced[1]}"`);
}

function jsonNumberField(line, key) {
  const match = line.match(new RegExp(`"${key}"\\s*:\\s*(-?\\d+(?:\\.\\d+)?)`));
  return match ? Number(match[1]) : 0;
}

function timestampFromLine(line) {
  return toMs(jsonStringField(line, "timestamp"));
}

function lastTimestampFromLines(lines) {
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    const timestamp = timestampFromLine(lines[index]);
    if (timestamp > 0) return timestamp;
  }
  return 0;
}

function firstParsedLine(lines, predicate) {
  for (const line of lines) {
    if (!predicate(line)) continue;
    const row = parseJson(line);
    if (row) return row;
  }
  return undefined;
}

function lastParsedLine(lines, predicate) {
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    const line = lines[index];
    if (!predicate(line)) continue;
    const row = parseJson(line);
    if (row) return row;
  }
  return undefined;
}

function countLines(lines, predicate) {
  let count = 0;
  for (const line of lines) {
    if (predicate(line)) count += 1;
  }
  return count;
}

function isUserOrAssistantLine(line) {
  return hasJsonField(line, "role", "user") || hasJsonField(line, "role", "assistant");
}

function toMs(value) {
  if (typeof value === "number") return value;
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? 0 : parsed;
  }
  return 0;
}

function textFromContent(content) {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";

  return content
    .map((part) => {
      if (typeof part === "string") return part;
      if (part && typeof part.text === "string") return part.text;
      if (part && typeof part.content === "string") return part.content;
      return "";
    })
    .filter(Boolean)
    .join(" ")
    .trim();
}

function compact(text, fallback = "Untitled session") {
  const value = String(text ?? "")
    .replace(/\s+/g, " ")
    .trim();
  if (value.length === 0) return fallback;
  return value.length > 140 ? `${value.slice(0, 137)}...` : value;
}

function cwdFromFileUri(uri) {
  if (typeof uri !== "string" || !uri.startsWith("file://")) return undefined;
  try {
    return fileURLToPath(uri);
  } catch {
    return undefined;
  }
}

async function parseCodexFile(path) {
  const lines = splitLines(await readText(path));
  const meta =
    firstParsedLine(lines, (line) => hasJsonField(line, "type", "session_meta"))?.payload ?? {};
  const id =
    typeof meta.id === "string"
      ? meta.id
      : basename(path)
          .replace(/^rollout-[^-]+-/, "")
          .replace(/\.jsonl$/, "");
  const isMessageLine = (line) =>
    hasJsonField(line, "type", "response_item") && isUserOrAssistantLine(line);
  const previewRow = lastParsedLine(lines, isMessageLine)?.payload ?? {};

  return {
    id,
    messageCount: countLines(lines, isMessageLine),
    updatedAtMs: lastTimestampFromLines(lines),
    cwd: typeof meta.cwd === "string" ? meta.cwd : undefined,
    path,
    preview: compact(textFromContent(previewRow.content), ""),
  };
}

async function collectCodex(home, cache) {
  const codexDir = join(home, ".codex");
  const indexPath = join(codexDir, "session_index.jsonl");
  const index = new Map();

  if (await exists(indexPath)) {
    for (const row of await readJsonl(indexPath)) {
      if (typeof row.id === "string") {
        index.set(row.id, {
          title: compact(row.thread_name, row.id),
          updatedAtMs: toMs(row.updated_at),
        });
      }
    }
  }

  const files = [
    ...(await walkFiles(join(codexDir, "sessions"), (path) => path.endsWith(".jsonl"))),
    ...(await walkFiles(join(codexDir, "archived_sessions"), (path) => path.endsWith(".jsonl"))),
  ];
  const byId = new Map();

  for (const path of files) {
    const parsed = await cachedValue(cache, path, parseCodexFile);
    const indexed = index.get(parsed.id);

    byId.set(parsed.id, {
      id: parsed.id,
      tool: "Codex",
      title: indexed?.title ?? compact(parsed.preview, parsed.id),
      messageCount: parsed.messageCount,
      updatedAtMs: Math.max(parsed.updatedAtMs, indexed?.updatedAtMs ?? 0),
      cwd: parsed.cwd,
      path: parsed.path,
      preview: parsed.preview,
    });
  }

  for (const [id, indexed] of index) {
    if (!byId.has(id)) {
      byId.set(id, {
        id,
        tool: "Codex",
        title: indexed.title,
        messageCount: 0,
        updatedAtMs: indexed.updatedAtMs,
        path: indexPath,
        preview: "",
      });
    }
  }

  return [...byId.values()];
}

async function parseClaudeFile(path) {
  const lines = splitLines(await readText(path));
  const id =
    jsonStringField(lines.find((line) => line.includes('"sessionId"')) ?? "", "sessionId") ??
    basename(path, ".jsonl");
  const titleRow =
    firstParsedLine(lines, (line) => hasJsonField(line, "type", "ai-title")) ??
    firstParsedLine(lines, (line) => hasJsonField(line, "type", "last-prompt"));
  const isMessageLine = (line) =>
    (hasJsonField(line, "type", "user") || hasJsonField(line, "type", "assistant")) &&
    !line.includes('"isMeta":true') &&
    !line.includes('"isMeta": true');
  const previewRow = lastParsedLine(lines, isMessageLine) ?? {};
  const preview = compact(textFromContent(previewRow.message?.content), "");
  const cwd =
    previewRow.cwd ?? jsonStringField(lines.find((line) => line.includes('"cwd"')) ?? "", "cwd");
  const title = titleRow?.aiTitle ?? titleRow?.lastPrompt ?? "";

  return {
    id,
    tool: "Claude",
    title: compact(title || preview, id),
    messageCount: countLines(lines, isMessageLine),
    updatedAtMs: lastTimestampFromLines(lines),
    cwd: typeof cwd === "string" ? cwd : undefined,
    path,
    preview,
  };
}

async function collectClaude(home, cache) {
  const files = (
    await walkFiles(join(home, ".claude", "projects"), (path) => path.endsWith(".jsonl"))
  ).filter((path) => !path.includes("/subagents/"));

  const sessions = [];
  for (const path of files) {
    sessions.push(await cachedValue(cache, path, parseClaudeFile));
  }

  return sessions;
}

async function parseJunieEvents(eventsPath) {
  const lines = (await exists(eventsPath)) ? splitLines(await readText(eventsPath)) : [];
  const isUserPrompt = (line) => hasJsonField(line, "kind", "UserPromptEvent");
  const isTaskState = (line) => hasJsonField(line, "kind", "TaskState");
  const previewEvent = lastParsedLine(lines, isUserPrompt);
  const fallbackPreviewEvent = previewEvent ? undefined : lastParsedLine(lines, isTaskState);
  const preview = compact(
    previewEvent?.presentablePrompt || previewEvent?.prompt || previewEvent?.text,
    "",
  );
  const fallbackPreview = compact(fallbackPreviewEvent?.text || fallbackPreviewEvent?.details, "");

  return {
    messageCount: countLines(lines, (line) => isUserPrompt(line) || isTaskState(line)),
    preview: preview || fallbackPreview,
  };
}

async function collectJunie(home, cache) {
  const sessionsDir = join(home, ".junie", "sessions");
  const indexPath = join(sessionsDir, "index.jsonl");
  if (!(await exists(indexPath))) return [];

  const sessions = [];
  for (const row of await readJsonl(indexPath)) {
    if (typeof row.sessionId !== "string") continue;

    const eventsPath = join(sessionsDir, row.sessionId, "events.jsonl");
    const parsed = (await exists(eventsPath))
      ? await cachedValue(cache, eventsPath, parseJunieEvents)
      : { messageCount: 0, preview: "" };

    sessions.push({
      id: row.sessionId,
      tool: "Junie",
      title: compact(row.taskName, row.sessionId),
      messageCount: parsed.messageCount,
      updatedAtMs: toMs(row.updatedAt),
      cwd: typeof row.projectDir === "string" ? row.projectDir : undefined,
      path: eventsPath,
      preview: parsed.preview,
    });
  }

  return sessions;
}

async function parsePiFile(path) {
  const lines = splitLines(await readText(path));
  const header = firstParsedLine(lines, (line) => hasJsonField(line, "type", "session")) ?? {};
  const id = typeof header.id === "string" ? header.id : basename(path, ".jsonl").split("_").at(-1);
  const isMessageLine = (line) =>
    hasJsonField(line, "type", "message") && isUserOrAssistantLine(line);
  const previewRow = lastParsedLine(lines, isMessageLine) ?? {};
  const preview = compact(textFromContent(previewRow.message?.content), "");

  return {
    id,
    tool: "Pi",
    title: compact(preview, id),
    messageCount: countLines(lines, isMessageLine),
    updatedAtMs: Math.max(toMs(header.timestamp), lastTimestampFromLines(lines)),
    cwd: typeof header.cwd === "string" ? header.cwd : undefined,
    path,
    preview,
  };
}

async function collectPi(home, cache) {
  const files = await walkFiles(join(home, ".pi", "agent", "sessions"), (path) =>
    path.endsWith(".jsonl"),
  );
  const sessions = [];

  for (const path of files) {
    sessions.push(await cachedValue(cache, path, parsePiFile));
  }

  return sessions;
}

async function parseAmpFile(path) {
  const lines = splitLines(await readText(path));
  const id = jsonStringField(lines.find((line) => line.includes('"id"')) ?? "", "id");
  if (typeof id !== "string") return undefined;

  const title = jsonStringField(lines.find((line) => line.includes('"title"')) ?? "", "title");
  const treeUri = jsonStringField(
    lines.find((line) => line.includes('"uri": "file://')) ?? "",
    "uri",
  );
  const created = jsonNumberField(
    lines.find((line) => line.includes('"created"')) ?? "",
    "created",
  );
  const preview = compact(
    jsonStringField(lines.findLast((line) => line.includes('"text"')) ?? "", "text"),
    "",
  );
  const sentAt = jsonNumberField(
    lines.findLast((line) => line.includes('"sentAt"')) ?? "",
    "sentAt",
  );

  return {
    id,
    tool: "Amp",
    title: compact(title || preview, id),
    messageCount: countLines(lines, isUserOrAssistantLine),
    updatedAtMs: Math.max(sentAt, created, await fileMtimeMs(path)),
    cwd: cwdFromFileUri(treeUri),
    path,
    preview,
  };
}

async function collectAmp(home, cache) {
  const files = await walkFiles(
    join(home, ".local", "share", "amp", "threads"),
    (path) => basename(path).startsWith("T-") && path.endsWith(".json"),
  );
  const sessions = [];

  for (const path of files) {
    const session = await cachedValue(cache, path, parseAmpFile);
    if (session) sessions.push(session);
  }

  return sessions;
}

async function collectOpenCode(home) {
  const root = join(home, ".local", "share", "opencode", "storage");
  const sessionFiles = await walkFiles(
    join(root, "session"),
    (path) => basename(path).startsWith("ses_") && path.endsWith(".json"),
  );
  const sessions = [];

  for (const path of sessionFiles) {
    const session = await readJson(path);
    if (!session || typeof session.id !== "string") continue;

    const messageDir = join(root, "message", session.id);
    const messageFiles = (await exists(messageDir))
      ? await walkFiles(
          messageDir,
          (messagePath) =>
            basename(messagePath).startsWith("msg_") && messagePath.endsWith(".json"),
        )
      : [];
    let messageCount = 0;
    let updatedAtMs = toMs(session.time?.updated);
    let preview = "";

    for (const messagePath of messageFiles) {
      const message = await readJson(messagePath);
      if (!message || !(message.role === "user" || message.role === "assistant")) continue;
      messageCount += 1;
      updatedAtMs = Math.max(
        updatedAtMs,
        toMs(message.time?.completed),
        toMs(message.time?.created),
      );
      preview = compact(message.summary?.title, "") || preview;
    }

    sessions.push({
      id: session.id,
      tool: "OpenCode",
      title: compact(session.title || preview, session.id),
      messageCount,
      updatedAtMs,
      cwd: typeof session.directory === "string" ? session.directory : undefined,
      path,
      preview,
    });
  }

  return sessions;
}

export async function collectSessionsFromHome(home) {
  const cache = await loadCache(home);
  const groups = await Promise.all([
    collectCodex(home, cache),
    collectClaude(home, cache),
    collectJunie(home, cache),
    collectPi(home, cache),
    collectAmp(home, cache),
    collectOpenCode(home),
  ]);
  await saveCache(cache);

  return groups.flat();
}

export async function fileMtimeMs(path) {
  try {
    return (await stat(path)).mtimeMs;
  } catch {
    return 0;
  }
}
