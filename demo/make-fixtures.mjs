// Generates a clean, synthetic HOME tree of coding-agent sessions so the VHS
// demo can showcase `resume` across all nine supported tools without exposing
// any real session data. Timestamps are computed relative to "now" at run
// time, so the picker always shows fresh, natural-looking ages in the GIF.
//
//   node demo/make-fixtures.mjs <home-dir>
//
// Each session's `cwd` is a fake `/Users/dev/code/<project>` path (independent
// of where the fixture files live) so the printed resume commands stay short
// and clean. Search-demo keywords avoid the letter "t" on purpose: the picker
// binds `t` to the timestamp-column toggle, so a typed query can never contain
// it (see src/tui.mjs).

import { mkdir, rm, utimes, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

const home = process.argv[2];
if (!home) {
  console.error("usage: node demo/make-fixtures.mjs <home-dir>");
  process.exit(1);
}

const now = Date.now();
const MIN = 60_000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;
const iso = (ms) => new Date(ms).toISOString();

// One spec per session. `age` is how long ago it was last touched.
// `cwd` becomes /Users/dev/code/<project>.
const SESSIONS = [
  {
    tool: "Claude",
    id: "7f3a9c21-2b4d-4e6f-8a01-aaaa00000001",
    title: "Add login and signup flow",
    project: "acme-api",
    preview: "Wired the /login route and refreshed session cookies for signed-in users.",
    age: 4 * MIN,
    msgs: 14,
  },
  {
    tool: "Codex",
    id: "c0de2222-1111-4222-8333-aaaa00000002",
    title: "Fix billing webhook retries",
    project: "billing-svc",
    preview: "Idempotency keys now dedupe duplicate webhook deliveries.",
    age: 18 * MIN,
    msgs: 9,
  },
  {
    tool: "Amp",
    id: "T-a1b2c3d4-0003",
    title: "Refactor login middleware",
    project: "acme-api",
    preview: "Extracted a requireUser guard and added clean 401 handling.",
    age: 42 * MIN,
    msgs: 22,
  },
  {
    tool: "OpenCode",
    id: "ses_4a1b2c3d40004aaaa00000004",
    title: "Build search index",
    project: "docs-site",
    preview: "Generated a lunr search index across all markdown pages.",
    age: 66 * MIN,
    msgs: 7,
  },
  {
    tool: "Kimi",
    id: "ses_k1a2b3c4-0015-4abc-8def-aaaa00000015",
    title: "Add session resume command",
    project: "acme-cli",
    preview: "Resume now restores the working dir for a chosen kimi session.",
    age: 30 * MIN,
    msgs: 12,
  },
  {
    tool: "Copilot",
    id: "cp00000a-1111-4222-8333-aaaa0000000a",
    title: "Wire up OAuth device flow",
    project: "acme-api",
    preview: "Added device-code polling and stored the refresh token securely.",
    age: 50 * MIN,
    msgs: 9,
  },
  {
    tool: "Antigravity",
    id: "ag00000b-2222-4333-8444-aaaa0000000b",
    title: "Refactor rendering pipeline",
    project: "acme-web",
    preview: "Split the renderer into layout and paint passes for clarity.",
    age: 90 * MIN,
    msgs: 0,
  },
  {
    tool: "Claude",
    id: "5e000005-2b4d-4e6f-8a01-aaaa00000005",
    title: "Dashboard skeleton loaders",
    project: "acme-web",
    preview: "Replaced layout shift with skeleton placeholders.",
    age: 2 * HOUR,
    msgs: 11,
  },
  {
    tool: "Pi",
    id: "p1a2b3c4-0006-4abc-8def-aaaa00000006",
    title: "(derived from preview)",
    project: "login-proxy",
    preview: "Cache login sessions in redis instead of in memory.",
    age: 3 * HOUR,
    msgs: 8,
  },
  {
    tool: "Junie",
    id: "ju000007-1111-4222-8333-aaaa00000007",
    title: "Migrate schema to v3",
    project: "billing-svc",
    preview: "Added invoices and credits, backfilled in small batches.",
    age: 5 * HOUR,
    msgs: 6,
  },
  {
    tool: "Amp",
    id: "T-a1b2c3d4-0008",
    title: "Login rate limiting",
    project: "login-proxy",
    preview: "Added a sliding window limiter keyed by ip and user.",
    age: 8 * HOUR,
    msgs: 16,
  },
  {
    tool: "Codex",
    id: "c0de9999-1111-4222-8333-aaaa00000009",
    title: "Compress blog images",
    project: "blog",
    preview: "Converted hero images to avif with a webp fallback.",
    age: 14 * HOUR,
    msgs: 5,
  },
  {
    tool: "Claude",
    id: "a0000010-2b4d-4e6f-8a01-aaaa00000010",
    title: "API pagination cursors",
    project: "acme-api",
    preview: "Switched offset paging over to keyset cursors.",
    age: DAY + 2 * HOUR,
    msgs: 19,
  },
  {
    tool: "OpenCode",
    id: "ses_b1c2d3e40011aaaa00000011",
    title: "Docs nav redesign",
    project: "docs-site",
    preview: "Collapsible sidebar plus on-page anchor links.",
    age: 2 * DAY,
    msgs: 10,
  },
  {
    tool: "Pi",
    id: "p9a8b7c6-0012-4abc-8def-aaaa00000012",
    title: "(derived from preview)",
    project: "infra",
    preview: "Infra dns cleanup: removed dangling records and renewed certs.",
    age: 3 * DAY,
    msgs: 13,
  },
  {
    tool: "Junie",
    id: "ju000013-1111-4222-8333-aaaa00000013",
    title: "Review login scopes",
    project: "acme-api",
    preview: "Mapped roles onto scopes and removed unused grants.",
    age: 4 * DAY,
    msgs: 7,
  },
  {
    tool: "Amp",
    id: "T-a1b2c3d4-0014",
    title: "Avatar upload crash",
    project: "acme-web",
    preview: "Guarded against a missing mime on empty uploads.",
    age: 6 * DAY,
    msgs: 9,
  },
];

const cwdOf = (s) => `/Users/dev/code/${s.project}`;
const updatedOf = (s) => now - s.age;

async function writeFileEnsured(path, contents) {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, contents);
}

const jsonl = (rows) => rows.map((row) => JSON.stringify(row)).join("\n") + "\n";

// Build `count` alternating user/assistant turns. The final turn is an
// assistant message carrying `preview`, stamped at `updated` so the adapters
// pick it up as both the preview text and the last-updated time.
function turns(count, preview, updated, makeRow) {
  const rows = [];
  for (let i = 0; i < count; i += 1) {
    const isLast = i === count - 1;
    const role = isLast ? "assistant" : i % 2 === 0 ? "user" : "assistant";
    const text = isLast ? preview : role === "user" ? "Can you take a look at this?" : "Done.";
    const ts = updated - (count - 1 - i) * 1000;
    rows.push(makeRow(role, text, ts));
  }
  return rows;
}

async function writeClaude(s) {
  const cwd = cwdOf(s);
  const updated = updatedOf(s);
  const dir = `-Users-dev-code-${s.project}`;
  const rows = [
    { type: "ai-title", aiTitle: s.title },
    ...turns(s.msgs, s.preview, updated, (role, text, ts) => ({
      type: role,
      message: { role, content: [{ type: "text", text }] },
      cwd,
      timestamp: iso(ts),
    })),
  ];
  await writeFileEnsured(join(home, ".claude", "projects", dir, `${s.id}.jsonl`), jsonl(rows));
}

async function writeCodex(s, indexRows) {
  const cwd = cwdOf(s);
  const updated = updatedOf(s);
  const rows = [
    { type: "session_meta", payload: { id: s.id, cwd, timestamp: iso(updated - s.msgs * 1000) } },
    ...turns(s.msgs, s.preview, updated, (role, text, ts) => ({
      type: "response_item",
      payload: {
        role,
        content: [{ type: role === "user" ? "input_text" : "output_text", text }],
      },
      timestamp: iso(ts),
    })),
  ];
  await writeFileEnsured(
    join(home, ".codex", "sessions", "2026", "05", `rollout-2026-05-31-${s.id}.jsonl`),
    jsonl(rows),
  );
  indexRows.push({ id: s.id, thread_name: s.title, updated_at: iso(updated) });
}

async function writeAmp(s) {
  const cwd = cwdOf(s);
  const updated = updatedOf(s);
  const created = updated - s.msgs * MIN;
  const messages = turns(s.msgs, s.preview, updated, (role, text, ts) => ({
    role,
    text,
    sentAt: ts,
  }));
  const thread = {
    id: s.id,
    title: s.title,
    created,
    messages,
    tree: { uri: `file://${cwd}` },
  };
  const path = join(home, ".local", "share", "amp", "threads", `${s.id}.json`);
  await writeFileEnsured(path, JSON.stringify(thread, null, 2) + "\n");
  // The Amp adapter folds file mtime into updatedAtMs, so backdate it to the
  // session's intended age (otherwise every Amp thread sorts as brand new).
  const when = new Date(updated);
  await utimes(path, when, when);
}

async function writeOpenCode(s) {
  const cwd = cwdOf(s);
  const updated = updatedOf(s);
  const session = {
    id: s.id,
    title: s.title,
    directory: cwd,
    time: { created: updated - s.msgs * MIN, updated },
  };
  await writeFileEnsured(
    join(home, ".local", "share", "opencode", "storage", "session", `${s.id}.json`),
    JSON.stringify(session, null, 2),
  );
  for (let i = 0; i < s.msgs; i += 1) {
    const role = i % 2 === 0 ? "user" : "assistant";
    const ts = updated - (s.msgs - 1 - i) * 1000;
    const message = {
      id: `msg_${String(i).padStart(4, "0")}`,
      role,
      time: { created: ts, completed: ts },
      summary: { title: s.preview },
    };
    await writeFileEnsured(
      join(
        home,
        ".local",
        "share",
        "opencode",
        "storage",
        "message",
        s.id,
        `msg_${String(i).padStart(4, "0")}.json`,
      ),
      JSON.stringify(message, null, 2),
    );
  }
}

async function writeJunie(s, indexRows) {
  const cwd = cwdOf(s);
  const updated = updatedOf(s);
  const events = [];
  for (let i = 0; i < s.msgs - 1; i += 1) {
    events.push({ kind: "TaskState", text: "running step " + (i + 1) });
  }
  events.push({ kind: "UserPromptEvent", presentablePrompt: s.preview });
  await writeFileEnsured(join(home, ".junie", "sessions", s.id, "events.jsonl"), jsonl(events));
  indexRows.push({
    sessionId: s.id,
    taskName: s.title,
    updatedAt: iso(updated),
    projectDir: cwd,
  });
}

async function writePi(s) {
  const cwd = cwdOf(s);
  const updated = updatedOf(s);
  const rows = [
    { type: "session", id: s.id, cwd, timestamp: iso(updated - s.msgs * 1000) },
    ...turns(s.msgs, s.preview, updated, (role, text, ts) => ({
      type: "message",
      role,
      message: { role, content: [{ type: "text", text }] },
      timestamp: iso(ts),
    })),
  ];
  await writeFileEnsured(join(home, ".pi", "agent", "sessions", `${s.id}.jsonl`), jsonl(rows));
}

async function writeKimi(s, indexRows) {
  const cwd = cwdOf(s);
  const updated = updatedOf(s);
  const sessionDir = join(home, ".kimi-code", "sessions", `wd_${s.project}`, s.id);
  await writeFileEnsured(
    join(sessionDir, "state.json"),
    JSON.stringify(
      {
        title: s.title,
        createdAt: iso(updated - s.msgs * MIN),
        updatedAt: iso(updated),
        lastPrompt: s.preview,
      },
      null,
      2,
    ),
  );
  const rows = turns(s.msgs, s.preview, updated, (role, text) => ({
    type: "context.append_message",
    message: { role, content: [{ type: "text", text }] },
  }));
  const wirePath = join(sessionDir, "agents", "main", "wire.jsonl");
  await writeFileEnsured(wirePath, jsonl(rows));
  // The Kimi adapter folds the wire-log mtime into updatedAtMs, so backdate it
  // to the session's intended age (otherwise every Kimi session sorts as new).
  const when = new Date(updated);
  await utimes(wirePath, when, when);
  indexRows.push({ sessionId: s.id, sessionDir, workDir: cwd });
}

async function writeCopilot(s) {
  const cwd = cwdOf(s);
  const updated = updatedOf(s);
  // Copilot derives the title from the first user.message and the preview from
  // the last message, so seed the first user turn with the title.
  const rows = [
    {
      type: "session.start",
      data: { sessionId: s.id, context: { cwd } },
      timestamp: iso(updated - s.msgs * 1000),
    },
  ];
  for (let i = 0; i < s.msgs; i += 1) {
    const role = i % 2 === 0 ? "user" : "assistant";
    const isLast = i === s.msgs - 1;
    const text =
      i === 0
        ? s.title
        : isLast
          ? s.preview
          : role === "user"
            ? "Can you take a look at this?"
            : "Done.";
    rows.push({
      type: `${role}.message`,
      data: { content: text },
      timestamp: iso(updated - (s.msgs - 1 - i) * 1000),
    });
  }
  await writeFileEnsured(
    join(home, ".copilot", "session-state", s.id, "events.jsonl"),
    jsonl(rows),
  );
}

async function writeAntigravity(s, cwdMap) {
  const cwd = cwdOf(s);
  const updated = updatedOf(s);
  const root = join(home, ".gemini", "antigravity-cli");
  const convPath = join(root, "conversations", `${s.id}.pb`);
  await writeFileEnsured(convPath, "synthetic-protobuf-conversation");
  await writeFileEnsured(
    join(root, "brain", s.id, "task.md.metadata.json"),
    JSON.stringify(
      { artifactType: "ARTIFACT_TYPE_TASK", summary: s.preview, updatedAt: iso(updated) },
      null,
      2,
    ),
  );
  // The Antigravity adapter folds the .pb mtime into updatedAtMs, so backdate it
  // to the session's intended age (otherwise every conversation sorts as new).
  const when = new Date(updated);
  await utimes(convPath, when, when);
  cwdMap[cwd] = s.id;
}

async function main() {
  await rm(home, { recursive: true, force: true });

  const codexIndex = [];
  const junieIndex = [];
  const kimiIndex = [];
  const antigravityCwd = {};

  for (const s of SESSIONS) {
    switch (s.tool) {
      case "Claude":
        await writeClaude(s);
        break;
      case "Codex":
        await writeCodex(s, codexIndex);
        break;
      case "Amp":
        await writeAmp(s);
        break;
      case "OpenCode":
        await writeOpenCode(s);
        break;
      case "Junie":
        await writeJunie(s, junieIndex);
        break;
      case "Pi":
        await writePi(s);
        break;
      case "Kimi":
        await writeKimi(s, kimiIndex);
        break;
      case "Copilot":
        await writeCopilot(s);
        break;
      case "Antigravity":
        await writeAntigravity(s, antigravityCwd);
        break;
      default:
        throw new Error(`unknown tool ${s.tool}`);
    }
  }

  await writeFileEnsured(join(home, ".codex", "session_index.jsonl"), jsonl(codexIndex));
  await writeFileEnsured(join(home, ".junie", "sessions", "index.jsonl"), jsonl(junieIndex));
  await writeFileEnsured(join(home, ".kimi-code", "session_index.jsonl"), jsonl(kimiIndex));
  await writeFileEnsured(
    join(home, ".gemini", "antigravity-cli", "cache", "last_conversations.json"),
    JSON.stringify(antigravityCwd, null, 2),
  );

  console.log(`wrote ${SESSIONS.length} sessions to ${home}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
