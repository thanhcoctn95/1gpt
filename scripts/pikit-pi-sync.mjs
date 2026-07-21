#!/usr/bin/env node
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  statSync,
  writeFileSync,
  copyFileSync,
  rmSync,
} from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join, resolve, sep } from "node:path";

const SHARED_DIRS = [
  ".pi/agents",
  ".pi/prompts",
  ".pi/workflows",
  ".pi/skills",
  ".pi/themes",
  ".pi/extensions",
  ".pi/vendor",
  ".pi/profiles",
  ".pi/docs",
];

const SHARED_FILES = [
  "AGENTS.md",
  "scripts/pikit-health.mjs",
  "scripts/pikit-pi-sync.mjs",
  "scripts/pikit-skill-lint.mjs",
  "scripts/pikit-vendor-lock.mjs",
  ".pi/README.md",
  ".pi/version.json",
  ".pi/settings.json",
  ".pi/subagents.json",
  ".pi/catalog.json",
  ".pi/vendor-lock.json",
  ".pi/package.example.json",
  ".pi/dcp.json",
  ".pi/npm/package.json",
  ".pi/npm/package-lock.json",
  ".pi/npm/.gitignore",
];

const GITIGNORE_ENTRIES = [
  ".pi/npm/node_modules/",
  ".pi/git/",
  ".pi/tasks/",
  ".pi/docs/tasks/",
  ".pi/verify-cache.json",
  ".pi/task-registry.json",
  ".pi/task-session-history.json",
  ".pikit-backup/",
];

const EXCLUDED_PARTS = new Set(["node_modules", ".git", ".pikit-backup"]);
const EXCLUDED_RELATIVE = new Set([
  ".pi/git",
  ".pi/tasks",
  ".pi/docs/tasks",
  ".pi/verify-cache.json",
  ".pi/task-registry.json",
  ".pi/task-session-history.json",
  ".pikit-backup",
]);

function usage(exitCode = 0) {
  console.log(
    `Usage: node scripts/pikit-pi-sync.mjs --target <project-dir> [options]\n\nSync the reusable Pikit .pi pack into another project. Default mode is dry-run.\n\nOptions:\n  --target <dir>     Target project directory to receive .pi resources\n  --source <dir>     Source Pikit repo directory (default: current working directory)\n  --apply            Perform writes (without this, dry-run only)\n  --dry-run          Show planned changes without writing (default)\n  --no-backup        Do not backup changed destination files before overwrite\n  --reinstall-deps   Reinstall Pikit-owned npm dependencies after applying\n  -h, --help         Show this help\n\nExamples:\n  node scripts/pikit-pi-sync.mjs --target ../other-project\n  node scripts/pikit-pi-sync.mjs --target ../other-project --apply\n`,
  );
  process.exit(exitCode);
}

function parseArgs(argv) {
  const opts = { source: process.cwd(), target: undefined, apply: false, backup: true };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "-h" || arg === "--help") usage(0);
    if (arg === "--target") opts.target = argv[++i];
    else if (arg === "--source") opts.source = argv[++i];
    else if (arg === "--apply") opts.apply = true;
    else if (arg === "--dry-run") opts.apply = false;
    else if (arg === "--reinstall-deps") opts.reinstallDeps = true;
    else if (arg === "--no-backup") opts.backup = false;
    else if (arg === "--yes") opts.yes = true;
    else throw new Error(`Unknown argument: ${arg}`);
  }
  if (!opts.target) usage(1);
  opts.source = resolve(opts.source);
  opts.target = resolve(opts.target);
  return opts;
}

function isExcludedRel(rel) {
  const normalized = rel.split(sep).join("/");
  if (EXCLUDED_RELATIVE.has(normalized)) return true;
  const parts = normalized.split("/");
  if (parts.some((p) => EXCLUDED_PARTS.has(p))) return true;
  if (normalized.includes("/.pi/git/") || normalized.endsWith("/.pi/git")) return true;
  if (normalized.includes("/.pi/tasks/") || normalized.endsWith("/.pi/tasks")) return true;
  if (normalized.includes("/.pi/docs/tasks/") || normalized.endsWith("/.pi/docs/tasks"))
    return true;
  if (normalized.endsWith("/.pi/verify-cache.json")) return true;
  if (normalized.endsWith("/.DS_Store") || normalized === ".DS_Store") return true;
  if (/(^|\/)\.env(?:\.|\/|$)/.test(normalized)) return true;
  return false;
}

function walkFiles(absRoot, relRoot) {
  if (!existsSync(absRoot)) return [];
  const out = [];
  for (const entry of readdirSync(absRoot)) {
    const abs = join(absRoot, entry);
    const rel = join(relRoot, entry);
    if (isExcludedRel(rel)) continue;
    const st = statSync(abs);
    if (st.isDirectory()) out.push(...walkFiles(abs, rel));
    else if (st.isFile()) out.push(rel);
  }
  return out;
}

function collectSharedFiles(source) {
  const files = new Set();
  for (const rel of SHARED_FILES) {
    if (existsSync(join(source, rel)) && !isExcludedRel(rel)) files.add(rel);
  }
  for (const dir of SHARED_DIRS) {
    for (const rel of walkFiles(join(source, dir), dir)) files.add(rel);
  }
  return [...files].sort();
}

function sameFile(a, b) {
  if (!existsSync(a) || !existsSync(b)) return false;
  return readFileSync(a).equals(readFileSync(b));
}

function backupPath(target, rel, stamp) {
  return join(target, ".pikit-backup", stamp, rel);
}

function ensureParent(path) {
  mkdirSync(dirname(path), { recursive: true });
}

function copyWithBackup(source, target, rel, opts, stamp, actions) {
  const src = join(source, rel);
  const dst = join(target, rel);
  if (!existsSync(dst)) {
    actions.push({ kind: "create", rel });
    if (opts.apply) {
      ensureParent(dst);
      copyFileSync(src, dst);
    }
    return;
  }
  if (sameFile(src, dst)) {
    actions.push({ kind: "unchanged", rel });
    return;
  }
  actions.push({ kind: "update", rel });
  if (opts.backup) actions.push({ kind: "backup", rel: `.pikit-backup/${stamp}/${rel}` });
  if (opts.apply) {
    if (opts.backup) {
      const bak = backupPath(target, rel, stamp);
      ensureParent(bak);
      copyFileSync(dst, bak);
    }
    ensureParent(dst);
    copyFileSync(src, dst);
  }
}

function dependencyInstallRoots(source, target) {
  const roots = [];
  const npmRoot = join(source, ".pi/npm");
  if (existsSync(join(npmRoot, "package-lock.json"))) roots.push(".pi/npm");
  for (const rel of walkFiles(join(source, ".pi/vendor"), ".pi/vendor")) {
    if (rel.endsWith("/package-lock.json")) roots.push(dirname(rel));
  }
  return [...new Set(roots)].sort().map((rel) => join(target, rel));
}

function reinstallDependencies(source, target, opts, actions) {
  if (!opts.reinstallDeps) return;
  for (const root of dependencyInstallRoots(source, target)) {
    const rel = root.slice(target.length + 1);
    actions.push({ kind: "reinstall-deps", rel });
    if (!opts.apply) continue;
    rmSync(join(root, "node_modules"), { recursive: true, force: true });
    execFileSync("npm", ["ci", "--ignore-scripts"], {
      cwd: root,
      stdio: "inherit",
    });
  }
}

function syncGitignore(target, opts, actions) {
  const rel = ".gitignore";
  const path = join(target, rel);
  const current = existsSync(path) ? readFileSync(path, "utf8") : "";
  const lines = current
    .split(/\r?\n/)
    .filter((line, idx, arr) => idx < arr.length - 1 || line.length > 0);
  let changed = false;
  for (const entry of GITIGNORE_ENTRIES) {
    if (!lines.includes(entry)) {
      lines.push(entry);
      changed = true;
    }
  }
  if (!changed) {
    actions.push({ kind: "unchanged", rel });
    return;
  }
  actions.push({ kind: existsSync(path) ? "update" : "create", rel });
  if (opts.apply) {
    ensureParent(path);
    writeFileSync(path, `${lines.join("\n").replace(/\n+$/g, "")}\n`);
  }
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  const sourcePi = join(opts.source, ".pi");
  if (!existsSync(sourcePi)) throw new Error(`Source does not contain .pi: ${opts.source}`);
  if (!existsSync(opts.target)) throw new Error(`Target directory does not exist: ${opts.target}`);
  if (opts.source === opts.target)
    throw new Error("Source and target must be different directories.");

  const stamp = new Date()
    .toISOString()
    .replace(/[-:]/g, "")
    .replace(/\.\d+Z$/, "Z");
  const files = collectSharedFiles(opts.source);
  const actions = [];

  for (const rel of files) copyWithBackup(opts.source, opts.target, rel, opts, stamp, actions);
  syncGitignore(opts.target, opts, actions);
  reinstallDependencies(opts.source, opts.target, opts, actions);

  const counts = actions.reduce((acc, a) => {
    acc[a.kind] = (acc[a.kind] ?? 0) + 1;
    return acc;
  }, {});

  console.log(`Pikit Pi pack sync ${opts.apply ? "APPLY" : "DRY-RUN"}`);
  console.log(`source: ${opts.source}`);
  console.log(`target: ${opts.target}`);
  console.log(`files considered: ${files.length}`);
  console.log(`summary: ${JSON.stringify(counts)}`);
  console.log("");
  for (const action of actions.filter((a) => a.kind !== "unchanged")) {
    console.log(`${action.kind.padEnd(7)} ${action.rel}`);
  }
  if (!opts.apply) {
    console.log("\nDry-run only. Re-run with --apply to write changes.");
  }
}

try {
  main();
} catch (error) {
  console.error(`pikit-pi-sync: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
}
