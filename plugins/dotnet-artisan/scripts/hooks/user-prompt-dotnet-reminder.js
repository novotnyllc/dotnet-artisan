#!/usr/bin/env node
//
// user-prompt-dotnet-reminder.js -- UserPromptSubmit hook (cross-platform).
//
// Silently injects XML routing reminder via additionalContext when the
// current directory is a .NET repo or the prompt mentions .NET keywords.
//
// Output: JSON with hookSpecificOutput on stdout.
// Exit code: always 0 (never blocks).

"use strict";

const fs = require("fs");
const path = require("path");

function findFiles(dir, maxDepth, test) {
  const results = [];
  function walk(current, depth) {
    if (depth > maxDepth) return;
    let entries;
    try {
      entries = fs.readdirSync(current, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const full = path.join(current, entry.name);
      if (entry.isFile() && test(entry.name)) {
        results.push(full);
        return; // first hit only
      }
      if (entry.isDirectory() && !entry.name.startsWith(".") && entry.name !== "node_modules") {
        walk(full, depth + 1);
        if (results.length > 0) return;
      }
    }
  }
  walk(dir, 0);
  return results;
}

function extractPromptText(jsonPayload) {
  if (!jsonPayload) return "";
  let payload;
  try {
    payload = JSON.parse(jsonPayload);
  } catch {
    return "";
  }
  if (typeof payload !== "object" || payload === null) return "";

  const candidates = [
    payload.prompt,
    payload.userPrompt,
    payload.message,
    payload.text,
  ];

  for (const key of ["input", "hookInput", "hookSpecificInput", "payload"]) {
    const node = payload[key];
    if (node && typeof node === "object") {
      candidates.push(node.prompt, node.userPrompt, node.message);
    }
  }

  for (const item of candidates) {
    if (typeof item === "string" && item.length > 0) return item;
  }
  return "";
}

function emit(ctx) {
  console.log(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        additionalContext: ctx,
      },
    })
  );
}

try {
  // Read optional hook payload from stdin.
  let inputJson = "";
  if (!process.stdin.isTTY) {
    try {
      inputJson = fs.readFileSync(0, "utf8");
    } catch {
      // no stdin or read failure
    }
  }

  const promptText = extractPromptText(inputJson);
  const cwd = process.cwd();

  // Check if current directory looks like a .NET repo.
  const hasSolution = findFiles(cwd, 3, (n) => n.endsWith(".sln") || n.endsWith(".slnx")).length > 0;
  const hasCsproj = findFiles(cwd, 3, (n) => n.endsWith(".csproj")).length > 0;
  const hasCs = findFiles(cwd, 4, (n) => n.endsWith(".cs")).length > 0;
  const hasGlobalJson = fs.existsSync(path.join(cwd, "global.json"));

  const isDotnetRepo = hasSolution || hasCsproj || hasCs || hasGlobalJson;

  const dotnetPattern =
    /(^|[^a-zA-Z0-9_])(dotnet|\.net|c#|csproj|slnx?|msbuild|nuget|roslyn|xunit|asp\.?net|blazor|maui|winui|wpf|winforms|entity framework|ef core|benchmarkdotnet|f#)([^a-zA-Z0-9_]|$)/i;
  const dotnetPrompt = promptText ? dotnetPattern.test(promptText) : false;

  const usingDotnetPattern =
    /(\$using-dotnet|\[skill:using-dotnet\]|(^|[^a-zA-Z0-9_-])using-dotnet([^a-zA-Z0-9_-]|$))/i;
  const alreadyRequestsUsingDotnet = promptText
    ? usingDotnetPattern.test(promptText)
    : false;

  let msg = "";
  if ((isDotnetRepo || dotnetPrompt) && !alreadyRequestsUsingDotnet) {
    msg = `<system-reminder>
<dotnet-artisan-routing>
1. Mandatory first action: invoke [skill:using-dotnet].
2. Mandatory second action: invoke [skill:dotnet-advisor].
3. Do not plan, reason, design, or implement until both routing skills have been invoked.
4. Follow advisor routing and invoke the relevant downstream skills.
5. Apply standards defined by the routed skills.
</dotnet-artisan-routing>
</system-reminder>`;
  }

  emit(msg);
} catch {
  // Never block -- emit empty context on any error.
  emit("");
}

process.exit(0);
