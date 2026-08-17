#!/usr/bin/env node
//
// session-start-context.js -- SessionStart hook for .NET project detection.
//
// Checks if the current directory is a .NET project and injects context
// about target framework and project structure.
//
// Output: Codex hook JSON with additionalContext on stdout.
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

try {
  const cwd = process.cwd();

  const hasSolution = findFiles(cwd, 3, (n) => n.endsWith(".sln") || n.endsWith(".slnx")).length > 0;
  const csprojFiles = findFiles(cwd, 3, (n) => n.endsWith(".csproj"));
  const hasCsproj = csprojFiles.length > 0;
  const hasGlobalJson = fs.existsSync(path.join(cwd, "global.json"));

  // Extract TFM from first .csproj found.
  let tfm = "";
  if (csprojFiles.length > 0) {
    try {
      const content = fs.readFileSync(csprojFiles[0], "utf8");
      const match = content.match(/<TargetFrameworks?>([^<;]+)/);
      if (match) tfm = match[1];
    } catch {
      // ignore
    }
  }

  // Build context message; inject only for .NET repositories.
  let context = "";

  if (hasSolution || hasCsproj || hasGlobalJson) {
    context =
      "Mandatory first action for every task: invoke [skill:using-dotnet]. Mandatory second action: invoke [skill:dotnet-advisor]. Do not plan, reason, design, or implement until both have been invoked, then follow advisor routing to load additional skills and apply their standards.";

    let projectContext = "This is a .NET project";
    if (tfm) projectContext += ` (${tfm})`;
    if (hasCsproj) projectContext += " with project files";
    if (hasSolution) projectContext += " in solution files";
    if (hasGlobalJson) projectContext += " and global.json";
    projectContext += ".";

    context += " " + projectContext;
  }

  console.log(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: context,
    },
  }));
} catch {
  // Never block -- emit empty context on any error.
  console.log(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: "",
    },
  }));
}

process.exit(0);
