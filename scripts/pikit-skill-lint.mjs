#!/usr/bin/env node
// Pikit skill linter. Validates SKILL.md frontmatter and structure.
// Usage: node scripts/pikit-skill-lint.mjs [--check]
//   --check : exit 1 on any error (for CI/governance)
import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join } from "node:path";

const SKILL_DIR = ".pi/skills";
const MAX_LINES = 500;
const MAX_LINES_WARN = 400;
const MIN_TAGS = 1;
const MAX_TAGS = 5;
const MAX_DESC = 1024;

// Whitelist derived from the current pack vocabulary. Extend deliberately.
const ALLOWED_TAGS = new Set([
  "agent-coordination",
  "ai-workflow",
  "anti-slop",
  "apple",
  "architecture",
  "audit",
  "automation",
  "behavior",
  "browser",
  "code-quality",
  "context",
  "debugging",
  "decision",
  "design",
  "devops",
  "documentation",
  "domain-driven-design",
  "git",
  "integration",
  "mcp",
  "meta",
  "performance",
  "planning",
  "product",
  "refactor",
  "release",
  "research",
  "review",
  "security",
  "shipping",
  "testing",
  "ui",
  "verification",
  "workflow",
]);

const REQUIRED = ["name", "description", "version", "tags", "dependencies"];
const NAME_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const VERSION_RE = /^\d+\.\d+\.\d+$/;

function parseFront(text) {
  const m = text.match(/^---\n([\s\S]*?)\n---/);
  if (!m) return null;
  const fields = {};
  for (const line of m[1].split("\n")) {
    const kv = line.match(/^([\w-]+):\s*(.*)$/);
    if (!kv) continue;
    const [, k, vRaw] = kv;
    const arr = vRaw.match(/^\[(.*)\]$/);
    if (arr) {
      fields[k] = arr[1]
        .split(",")
        .map((s) => s.trim().replace(/^['"]|['"]$/g, ""))
        .filter(Boolean);
    } else {
      fields[k] = vRaw.replace(/^['"]|['"]$/g, "").trim();
    }
  }
  return fields;
}

const issues = [];
let total = 0,
  passed = 0;

// Skills live either flat (`.pi/skills/<name>/SKILL.md`) or grouped under a
// category folder (`.pi/skills/<category>/<name>/SKILL.md`). Collect the skill
// name (directory directly containing SKILL.md) plus its file path.
function collectSkillFiles() {
  const found = [];
  for (const entry of readdirSync(SKILL_DIR)) {
    const direct = join(SKILL_DIR, entry, "SKILL.md");
    if (existsSync(direct)) {
      found.push({ name: entry, file: direct });
      continue;
    }
    const categoryDir = join(SKILL_DIR, entry);
    let stat;
    try {
      stat = statSync(categoryDir);
    } catch {
      continue;
    }
    if (!stat.isDirectory()) continue;
    for (const sub of readdirSync(categoryDir)) {
      const nested = join(categoryDir, sub, "SKILL.md");
      if (existsSync(nested)) found.push({ name: sub, file: nested });
    }
  }
  return found;
}

for (const { name, file } of collectSkillFiles()) {
  total++;
  const text = readFileSync(file, "utf-8");
  const lineCount = text.split("\n").length;
  const fm = parseFront(text);
  const local = [];

  if (!fm) {
    local.push(["error", "no-frontmatter", "missing YAML frontmatter block"]);
  } else {
    for (const f of REQUIRED) {
      if (!(f in fm)) local.push(["error", "missing-field", `frontmatter missing '${f}'`]);
    }
    if (fm.name && !NAME_RE.test(fm.name))
      local.push(["error", "bad-name", `name '${fm.name}' must be lowercase-hyphen`]);
    if (fm.version && !VERSION_RE.test(fm.version))
      local.push(["error", "bad-version", `version '${fm.version}' must be semver x.y.z`]);
    if (fm.description && fm.description.length > MAX_DESC)
      local.push(["error", "long-desc", `description ${fm.description.length} > ${MAX_DESC}`]);
    if (Array.isArray(fm.tags)) {
      if (fm.tags.length < MIN_TAGS) local.push(["error", "few-tags", `needs >= ${MIN_TAGS} tag`]);
      if (fm.tags.length > MAX_TAGS)
        local.push(["error", "many-tags", `${fm.tags.length} tags > ${MAX_TAGS}`]);
      for (const t of fm.tags)
        if (!ALLOWED_TAGS.has(t)) local.push(["error", "bad-tag", `tag '${t}' not in whitelist`]);
    } else if ("tags" in fm) {
      local.push(["error", "tags-not-array", "tags must be [a, b] array"]);
    }
  }

  if (lineCount > MAX_LINES) local.push(["error", "too-long", `${lineCount} lines > ${MAX_LINES}`]);
  else if (lineCount > MAX_LINES_WARN)
    local.push(["warning", "long", `${lineCount} lines > ${MAX_LINES_WARN}`]);

  if (local.length === 0) passed++;
  for (const [sev, rule, msg] of local) issues.push({ skill: name, sev, rule, msg });
}

const errors = issues.filter((i) => i.sev === "error");
const warnings = issues.filter((i) => i.sev === "warning");

console.log("# Pikit Skill Lint\n");
if (issues.length === 0) {
  console.log(`All ${total} skills pass.\n`);
} else {
  for (const i of issues) console.log(`- [${i.sev}] ${i.skill}: ${i.rule} — ${i.msg}`);
  console.log("");
}
console.log(`total=${total} passed=${passed} errors=${errors.length} warnings=${warnings.length}`);

if (process.argv.includes("--check") && errors.length > 0) process.exit(1);
