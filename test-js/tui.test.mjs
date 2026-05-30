import test from "node:test";
import assert from "node:assert/strict";
import { renderDetailsLines, selectedCommandOutput } from "../src/tui.mjs";

test("renders details in a separated box with a blank line before preview", () => {
  const lines = renderDetailsLines(
    {
      id: "abc",
      tool: "Claude",
      title: "Title",
      messageCount: 1,
      updatedAtMs: 0,
      cwd: "/repo",
      path: "/tmp/session.jsonl",
      preview: "last message preview",
    },
    80,
  );

  assert.match(lines[0], /^┌/);
  assert.match(lines.at(-1), /^└/);
  assert.ok(lines.some((line) => line.includes("Command cd /repo && claude --resume abc")));
  assert.match(lines[4], /^│ +│$/);
  assert.ok(lines[5].includes("last message preview"));
});

test("always reserves two preview lines in the details box", () => {
  const lines = renderDetailsLines(
    {
      id: "abc",
      tool: "Claude",
      title: "Title",
      messageCount: 1,
      updatedAtMs: 0,
      cwd: "/repo",
      path: "/tmp/session.jsonl",
      preview: "",
    },
    80,
  );

  assert.equal(lines.length, 8);
  assert.match(lines[5], /^│ +│$/);
  assert.match(lines[6], /^│ +│$/);
});

test("selected conversation output is the plain resume command", () => {
  const output = selectedCommandOutput({
    id: "abc",
    tool: "Claude",
    title: "Title",
    messageCount: 1,
    updatedAtMs: 0,
    cwd: "/repo",
    path: "/tmp/session.jsonl",
    preview: "",
  });

  assert.equal(output, "cd /repo && claude --resume abc");
});
