import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { collectSessionsFromHome } from "../src/adapters.mjs";

async function writeJsonl(path, rows) {
  await writeFile(path, rows.map((row) => JSON.stringify(row)).join("\n") + "\n");
}

test("collects normalized sessions from supported local agent stores", async () => {
  const home = await mkdtemp(join(tmpdir(), "resume-fixtures-"));

  await mkdir(join(home, ".codex", "sessions", "2026", "05", "30"), { recursive: true });
  await writeJsonl(join(home, ".codex", "session_index.jsonl"), [
    { id: "codex-1", thread_name: "Codex title", updated_at: "2026-05-30T05:00:00.000Z" },
  ]);
  await writeJsonl(join(home, ".codex", "sessions", "2026", "05", "30", "rollout-codex-1.jsonl"), [
    {
      timestamp: "2026-05-30T04:59:00.000Z",
      type: "session_meta",
      payload: { id: "codex-1", cwd: "/repo/codex" },
    },
    {
      timestamp: "2026-05-30T05:00:00.000Z",
      type: "response_item",
      payload: {
        type: "message",
        role: "user",
        content: [{ type: "input_text", text: "codex preview" }],
      },
    },
  ]);

  await mkdir(join(home, ".claude", "projects", "-repo-claude"), { recursive: true });
  await writeJsonl(join(home, ".claude", "projects", "-repo-claude", "claude-1.jsonl"), [
    { type: "ai-title", sessionId: "claude-1", aiTitle: "Claude title" },
    {
      type: "user",
      sessionId: "claude-1",
      timestamp: "2026-05-30T04:00:00.000Z",
      cwd: "/repo/claude",
      message: { role: "user", content: "claude preview" },
    },
    {
      type: "assistant",
      sessionId: "claude-1",
      timestamp: "2026-05-30T04:01:00.000Z",
      cwd: "/repo/claude",
      message: { role: "assistant", content: [{ type: "text", text: "answer" }] },
    },
  ]);

  await mkdir(join(home, ".junie", "sessions", "junie-1"), { recursive: true });
  await writeJsonl(join(home, ".junie", "sessions", "index.jsonl"), [
    {
      sessionId: "junie-1",
      taskName: "Junie title",
      projectDir: "/repo/junie",
      createdAt: 1770000000000,
      updatedAt: 1770000100000,
    },
  ]);
  await writeJsonl(join(home, ".junie", "sessions", "junie-1", "events.jsonl"), [
    { kind: "UserPromptEvent", prompt: "junie preview" },
    { kind: "TaskState", text: "working" },
  ]);

  await mkdir(join(home, ".pi", "agent", "sessions", "--repo-pi--"), { recursive: true });
  await writeJsonl(
    join(home, ".pi", "agent", "sessions", "--repo-pi--", "2026-05-30T01-00-00-000Z_pi-1.jsonl"),
    [
      { type: "session", id: "pi-1", timestamp: "2026-05-30T01:00:00.000Z", cwd: "/repo/pi" },
      {
        type: "message",
        id: "m1",
        timestamp: "2026-05-30T01:01:00.000Z",
        message: { role: "user", content: [{ type: "text", text: "pi preview" }] },
      },
    ],
  );

  await mkdir(join(home, ".local", "share", "amp", "threads"), { recursive: true });
  await writeFile(
    join(home, ".local", "share", "amp", "threads", "T-amp-1.json"),
    JSON.stringify({
      id: "T-amp-1",
      title: "Amp title",
      created: 1770000200000,
      env: { initial: { trees: [{ uri: "file:///repo/amp" }] } },
      messages: [
        {
          role: "user",
          meta: { sentAt: 1770000201000 },
          content: [{ type: "text", text: "amp preview" }],
        },
      ],
    }),
  );

  await mkdir(join(home, ".local", "share", "opencode", "storage", "session", "project-1"), {
    recursive: true,
  });
  await mkdir(join(home, ".local", "share", "opencode", "storage", "message", "ses_opencode_1"), {
    recursive: true,
  });
  await writeFile(
    join(
      home,
      ".local",
      "share",
      "opencode",
      "storage",
      "session",
      "project-1",
      "ses_opencode_1.json",
    ),
    JSON.stringify({
      id: "ses_opencode_1",
      directory: "/repo/opencode",
      title: "OpenCode title",
      time: { updated: 1770000300000 },
    }),
  );
  await writeFile(
    join(home, ".local", "share", "opencode", "storage", "message", "ses_opencode_1", "msg_1.json"),
    JSON.stringify({
      id: "msg_1",
      sessionID: "ses_opencode_1",
      role: "user",
      time: { created: 1770000301000 },
      summary: { title: "opencode preview" },
    }),
  );

  const sessions = await collectSessionsFromHome(home);
  const byTool = Object.fromEntries(sessions.map((session) => [session.tool, session]));

  assert.equal(sessions.length, 6);
  assert.equal(byTool.Codex.title, "Codex title");
  assert.equal(byTool.Claude.messageCount, 2);
  assert.equal(byTool.Junie.preview, "junie preview");
  assert.equal(byTool.Pi.cwd, "/repo/pi");
  assert.equal(byTool.Amp.preview, "amp preview");
  assert.equal(byTool.OpenCode.cwd, "/repo/opencode");
});
