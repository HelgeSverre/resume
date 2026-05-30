#!/usr/bin/env node
import { homedir } from "node:os";
import clipboard from "clipboardy";
import { collectSessionsFromHome } from "../src/adapters.mjs";
import { runPicker } from "../src/tui.mjs";
import * as Session from "../lib/es6/src/Session.mjs";
import * as SessionList from "../lib/es6/src/SessionList.mjs";

function help() {
  console.log(`resume

Usage:
  resume              Open searchable session picker
  resume --json       Print normalized sessions as JSON
  resume --copy <id>  Copy the resume command for a matching session id

Keys:
  type search text    Filter by tool, title, cwd, id, or preview
  up/down             Move selection
  t                   Toggle exact timestamp column
  enter               Print resume command and exit
  esc or ctrl-c       Exit
`);
}

function findSession(sessions, id) {
  return (
    sessions.find((session) => session.id === id) ??
    sessions.find((session) => session.id.startsWith(id))
  );
}

async function main() {
  const args = process.argv.slice(2);
  if (args.includes("--help") || args.includes("-h")) {
    help();
    return;
  }

  const sessions = SessionList.mergeAndSort(
    await collectSessionsFromHome(process.env.HOME || homedir()),
  );

  if (args.includes("--json")) {
    console.log(JSON.stringify(sessions, null, 2));
    return;
  }

  const copyIndex = args.findIndex((arg) => arg === "--copy");
  if (copyIndex >= 0) {
    const id = args[copyIndex + 1];
    if (!id) {
      console.error("Missing session id after --copy");
      process.exitCode = 2;
      return;
    }

    const session = findSession(sessions, id);
    if (!session) {
      console.error(`No session found matching ${id}`);
      process.exitCode = 1;
      return;
    }

    const command = Session.copyCommand(session);
    await clipboard.write(command);
    console.log(command);
    return;
  }

  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    for (const session of sessions.slice(0, 50)) {
      console.log(
        `${session.tool}\t${session.id}\t${session.title}\t${Session.copyCommand(session)}`,
      );
    }
    return;
  }

  await runPicker(sessions);
}

main().catch((error) => {
  console.error(error?.stack || String(error));
  process.exitCode = 1;
});
