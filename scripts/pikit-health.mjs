#!/usr/bin/env node
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { execFileSync } from "node:child_process";

const root = process.cwd();
const checks = [];
const warnings = [];

// Pi still exposes the project skill catalog to the lead session, while Pikit
// workflow specialists receive full static preloads from `.pi/agents/*.md`
// through @tintinweb/pi-subagents. Track lead catalog cost independently from
// validating agent preload ownership below.
const SKILL_SURFACE_TOKEN_WARN = 9000;

function addCheck(name, ok, evidence, next = "") {
  checks.push({ name, ok, evidence, next });
}

function addWarning(name, evidence, next = "") {
  warnings.push({ name, evidence, next });
}

function read(path) {
  return readFileSync(join(root, path), "utf8");
}

function parseFrontmatter(text) {
  if (!text.startsWith("---")) return {};
  const end = text.indexOf("\n---", 3);
  if (end === -1) return {};
  const body = text.slice(3, end);
  const data = {};
  for (const line of body.split(/\r?\n/)) {
    const match = /^([A-Za-z0-9_-]+):\s*(.*)$/.exec(line);
    if (match) data[match[1]] = match[2].trim();
  }
  return data;
}

function parseContractMarker(text, name) {
  const match = text.match(new RegExp(`<!--\\s*pikit-contract:${name}\\s+([^>]+?)\\s*-->`));
  if (!match) return null;
  return Object.fromEntries(
    [...match[1].matchAll(/([a-z-]+)=([^\s]+)/g)].map((entry) => [entry[1], entry[2]]),
  );
}

function workflowDeclarations(text) {
  return [...text.matchAll(/<!--\s*pikit-workflow:\s*([A-Za-z0-9._-]+)\s*-->/g)].map(
    (match) => match[1],
  );
}

function section(text, heading) {
  const match = new RegExp(`^##+\\s+${heading}\\s*$`, "im").exec(text);
  if (!match) return "";
  const start = match.index + match[0].length;
  const next = /^##+\s+/m.exec(text.slice(start));
  return text.slice(start, next ? start + next.index : undefined);
}

function normalized(text) {
  return text
    .replace(/<!--.*?-->/gs, " ")
    .replace(/[*_`]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function ordered(text, tokens) {
  let cursor = 0;
  const value = normalized(text).toLowerCase();
  return tokens.every((token) => {
    const index = value.indexOf(token.toLowerCase(), cursor);
    if (index === -1) return false;
    cursor = index + token.length;
    return true;
  });
}

function hasAll(text, tokens) {
  const value = normalized(text).toLowerCase();
  return tokens.every((token) => value.includes(token.toLowerCase()));
}

function satisfiesCanonicalClause(text, required, forbidden = []) {
  const value = normalized(text);
  return (
    required.every((pattern) => pattern.test(value)) &&
    !forbidden.some((pattern) => pattern.test(value))
  );
}

function table(headers, rows) {
  const escape = (value) => String(value).replace(/\n/g, " ").replace(/\|/g, "\\|");
  const out = [];
  out.push(`| ${headers.join(" | ")} |`);
  out.push(`| ${headers.map(() => "---").join(" | ")} |`);
  for (const row of rows) out.push(`| ${row.map(escape).join(" | ")} |`);
  return out.join("\n");
}

function listSkillFiles() {
  const base = join(root, ".pi/skills");
  if (!existsSync(base)) return [];
  // Skills live either flat (`.pi/skills/<name>/SKILL.md`) or grouped under a
  // category folder (`.pi/skills/<category>/<name>/SKILL.md`). Walk one level
  // deep: a directory is a skill if it has its own SKILL.md, otherwise treat it
  // as a category and look one level below.
  const out = [];
  for (const entry of readdirSync(base, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const direct = `.pi/skills/${entry.name}/SKILL.md`;
    if (existsSync(join(root, direct))) {
      out.push(direct);
      continue;
    }
    const categoryDir = join(base, entry.name);
    for (const sub of readdirSync(categoryDir, { withFileTypes: true })) {
      if (!sub.isDirectory()) continue;
      const nested = `.pi/skills/${entry.name}/${sub.name}/SKILL.md`;
      if (existsSync(join(root, nested))) out.push(nested);
    }
  }
  return out.sort();
}

function checkSettings() {
  try {
    const settings = JSON.parse(read(".pi/settings.json"));
    addCheck("settings-json", true, ".pi/settings.json parses as JSON");
    addCheck(
      "settings-skills-path",
      Array.isArray(settings.skills) && settings.skills.includes("skills"),
      "settings.skills includes skills",
    );
    addCheck(
      "settings-prompts-path",
      Array.isArray(settings.prompts) && settings.prompts.includes("prompts"),
      "settings.prompts includes prompts",
    );
    addCheck(
      "settings-agents-path",
      Array.isArray(settings.agents) && settings.agents.includes("agents"),
      "settings.agents includes agents",
    );
    addCheck(
      "settings-extensions-path",
      Array.isArray(settings.extensions) && settings.extensions.includes("extensions"),
      "settings.extensions includes extensions",
    );
    addCheck(
      "settings-token-speed-vendor-package",
      Array.isArray(settings.packages) &&
        settings.packages.includes("./vendor/extensions/pi-token-speed"),
      "settings.packages includes ./vendor/extensions/pi-token-speed",
      "Add ./vendor/extensions/pi-token-speed to .pi/settings.json packages",
    );
    addCheck(
      "settings-dcp-package",
      Array.isArray(settings.packages) &&
        settings.packages.includes("./vendor/extensions/@davecodes/pi-dcp"),
      "settings.packages includes ./vendor/extensions/@davecodes/pi-dcp",
      "Add ./vendor/extensions/@davecodes/pi-dcp to .pi/settings.json packages",
    );
  } catch (error) {
    addCheck(
      "settings-json",
      false,
      error instanceof Error ? error.message : String(error),
      "Fix .pi/settings.json syntax",
    );
  }
}

function checkVendorExtensions() {
  try {
    const pkg = JSON.parse(read(".pi/vendor/extensions/pi-token-speed/package.json"));
    const extensions = pkg.pi?.extensions ?? [];
    addCheck(
      "vendor-token-speed-package",
      pkg.name === "pi-token-speed" && pkg.version === "0.6.0",
      `vendor pi-token-speed ${pkg.version || "missing"}`,
      "Restore .pi/vendor/extensions/pi-token-speed",
    );
    addCheck(
      "vendor-token-speed-entry",
      existsSync(join(root, ".pi/vendor/extensions/pi-token-speed/index.ts")) &&
        extensions.includes("./index.ts"),
      "vendor token-speed package exposes ./index.ts",
      "Restore vendor token-speed package manifest",
    );
  } catch (error) {
    addCheck(
      "vendor-token-speed",
      false,
      error instanceof Error ? error.message : String(error),
      "Restore vendored pi-token-speed extension",
    );
  }
}

function checkNpmPackageConfig() {
  try {
    const pkg = JSON.parse(read(".pi/npm/package.json"));
    const lock = JSON.parse(read(".pi/npm/package-lock.json"));
    addCheck(
      "npm-package-json",
      pkg.private === true,
      ".pi/npm/package.json parses",
      "Fix .pi/npm/package.json",
    );
    addCheck(
      "npm-package-lock",
      Boolean(lock.packages?.[""]),
      ".pi/npm/package-lock.json parses",
      "Regenerate .pi/npm/package-lock.json",
    );
    addCheck(
      "npm-dcp-tokenizer-dep",
      typeof pkg.dependencies?.["@anthropic-ai/tokenizer"] === "string",
      `.pi/npm/package.json declares @anthropic-ai/tokenizer (${pkg.dependencies?.["@anthropic-ai/tokenizer"] || "missing"})`,
      "Add @anthropic-ai/tokenizer to .pi/npm/package.json dependencies (runtime dep of vendored pi-dcp)",
    );
  } catch (error) {
    addCheck(
      "npm-package-config",
      false,
      error instanceof Error ? error.message : String(error),
      "Fix .pi/npm package JSON/lockfile",
    );
  }
}

function checkVendorDcp() {
  try {
    const pkg = JSON.parse(read(".pi/vendor/extensions/@davecodes/pi-dcp/package.json"));
    const extensions = pkg.pi?.extensions ?? [];
    addCheck(
      "vendor-dcp-package",
      pkg.name === "@davecodes/pi-dcp" && typeof pkg.version === "string",
      `vendor @davecodes/pi-dcp ${pkg.version || "missing"}`,
      "Restore .pi/vendor/extensions/@davecodes/pi-dcp",
    );
    addCheck(
      "vendor-dcp-entry",
      existsSync(join(root, ".pi/vendor/extensions/@davecodes/pi-dcp/index.ts")) &&
        extensions.includes("./index.ts"),
      "vendor pi-dcp exposes ./index.ts",
      "Restore vendored pi-dcp package manifest/entry",
    );
    addCheck(
      "vendor-dcp-tokens",
      existsSync(join(root, ".pi/vendor/extensions/@davecodes/pi-dcp/lib/tokens.ts")),
      "vendor pi-dcp lib/tokens.ts present",
      "Restore vendored pi-dcp lib",
    );
  } catch (error) {
    addCheck(
      "vendor-dcp-package",
      false,
      error instanceof Error ? error.message : String(error),
      "Restore vendored pi-dcp extension",
    );
  }
}

function checkDcpConfig() {
  try {
    const raw = read(".pi/dcp.json");
    const cfg = JSON.parse(raw);
    addCheck("dcp-config-parses", true, ".pi/dcp.json parses as JSON");
    addCheck(
      "dcp-enabled",
      cfg.enabled === true,
      ".pi/dcp.json enabled=true",
      "Set enabled=true or remove .pi/dcp.json to fall back to defaults",
    );
    const compress = cfg.compress || {};
    addCheck(
      "dcp-compress-permission",
      compress.permission === "allow",
      `compress.permission=${compress.permission || "missing"}`,
      'Set compress.permission="allow" so DCP can call compress without prompting',
    );
    const protectedTools = Array.isArray(compress.protectedTools) ? compress.protectedTools : [];
    const requiredProtected = [
      "memory_search",
      "memory_check",
      "memory_sync",
      "tape_handoff",
      "tape_info",
      "tape_read",
      "tape_search",
      "tape_reset",
      "task",
    ];
    const missingProtected = requiredProtected.filter((name) => !protectedTools.includes(name));
    addCheck(
      "dcp-protected-task-tools",
      missingProtected.length === 0,
      missingProtected.length === 0
        ? "compress.protectedTools covers memory/tape/pi-task tools"
        : `missing protectedTools: ${missingProtected.join(", ")}`,
      "Add the pi-task `task` tool to compress.protectedTools so DCP does not prune delegation/memory state",
    );
    const catalog = JSON.parse(read(".pi/catalog.json"));
    const dcpCatalog = (catalog.integrations || []).some(
      (entry) => entry.install === "./vendor/extensions/@davecodes/pi-dcp",
    );
    const tokenSpeedCatalog = (catalog.integrations || []).some(
      (entry) => entry.install === "npm:pi-token-speed",
    );
    addCheck(
      "catalog-dcp-entry",
      dcpCatalog,
      "catalog.integrations includes ./vendor/extensions/@davecodes/pi-dcp",
      "Add vendored @davecodes/pi-dcp to .pi/catalog.json integrations",
    );
    addCheck(
      "catalog-token-speed-entry",
      tokenSpeedCatalog,
      "catalog.integrations includes npm:pi-token-speed",
      "Add pi-token-speed to .pi/catalog.json integrations so profiles match catalog",
    );
  } catch (error) {
    addCheck(
      "dcp-config-parses",
      false,
      error instanceof Error ? error.message : String(error),
      "Fix .pi/dcp.json syntax or restore file",
    );
  }
}

function checkSkills() {
  const skillFiles = listSkillFiles();
  const frontmatterConflicts = [];
  const skills = skillFiles.map((path) => {
    const text = read(path);
    const frontmatter = parseFrontmatter(text);
    const frontmatterEnd = text.indexOf("\n---", 3);
    const frontmatterBody = frontmatterEnd === -1 ? "" : text.slice(3, frontmatterEnd);
    for (const line of frontmatterBody.split(/\r?\n/)) {
      const match = /^([A-Za-z0-9_-]+):\s*(.*)$/.exec(line);
      if (!match) continue;
      const value = match[2].trimStart();
      if (value && !/^['"[{]/.test(value) && /:\s/.test(value))
        frontmatterConflicts.push(`${path}: ${line.trim()}`);
    }
    return {
      path,
      name: frontmatter.name || path.split("/").at(-2),
      description: frontmatter.description || "",
    };
  });
  // pi-native flow: every skill surfaces name+description into the system
  // prompt. Approximate the surface cost the way pi renders each <skill> block
  // (name + description + location path + XML tag overhead).
  const approxSurfaceChars = skills.reduce(
    (sum, skill) => sum + skill.name.length + skill.description.length + skill.path.length + 75,
    0,
  );
  const approxSurfaceTokens = Math.floor(approxSurfaceChars / 4);

  addCheck("skills-discovered", skills.length > 0, `${skills.length} skill files discovered`);
  addCheck(
    "skill-frontmatter-compact-mapping",
    frontmatterConflicts.length === 0,
    `${skillFiles.length} skill frontmatters checked; conflicts=${frontmatterConflicts.length}`,
    frontmatterConflicts.slice(0, 3).join(", ") || "Quote YAML scalar values that contain ':'",
  );
  if (approxSurfaceTokens > SKILL_SURFACE_TOKEN_WARN) {
    addWarning(
      "skill-surface-budget",
      `approx skill surface tokens=${approxSurfaceTokens} across ${skills.length} skills (warn>${SKILL_SURFACE_TOKEN_WARN})`,
      "Tighten skill descriptions or move rarely used skills out of .pi/skills",
    );
  }
}

function checkVendorLock() {
  try {
    const out = execFileSync("node", [join(root, "scripts/pikit-vendor-lock.mjs"), "--check"], {
      cwd: root,
      encoding: "utf8",
    });
    addCheck(
      "vendor-lock",
      true,
      out.trim().split(/\r?\n/).at(-1) || "vendor-lock OK",
      "Regenerate with node scripts/pikit-vendor-lock.mjs",
    );
  } catch (error) {
    const out = ((error.stdout || "") + (error.stderr || "")).toString().trim();
    const detail = out
      .split(/\r?\n/)
      .filter((l) => l.startsWith("- "))
      .slice(0, 5)
      .join("; ");
    addCheck(
      "vendor-lock",
      false,
      detail || (error instanceof Error ? error.message : String(error)),
      "If change is intentional, run node scripts/pikit-vendor-lock.mjs to update the lock",
    );
  }
}

function checkSkillLint() {
  try {
    const out = execFileSync("node", [join(root, "scripts/pikit-skill-lint.mjs"), "--check"], {
      cwd: root,
      encoding: "utf8",
    });
    const summary = out.trim().split(/\r?\n/).at(-1) || "";
    addCheck("skill-lint", true, summary, "Run node scripts/pikit-skill-lint.mjs");
  } catch (error) {
    const out = (error.stdout || "").toString();
    const errLines = out
      .split(/\r?\n/)
      .filter((l) => l.includes("[error]"))
      .slice(0, 5)
      .join("; ");
    const summary =
      out.trim().split(/\r?\n/).at(-1) || (error instanceof Error ? error.message : String(error));
    addCheck(
      "skill-lint",
      false,
      `${summary}${errLines ? ` | ${errLines}` : ""}`,
      "Fix skill frontmatter/structure; see node scripts/pikit-skill-lint.mjs",
    );
  }
}

function checkPrompts() {
  const dir = join(root, ".pi/prompts");
  const prompts = existsSync(dir)
    ? readdirSync(dir)
        .filter((name) => name.endsWith(".md"))
        .sort()
    : [];
  const contracts = {
    "audit.md": ["Audit codebase for a specific pattern", 'subagent_type: "Explore"'],
    "commit-push.md": [
      "Commit and push changes following Conventional Commits",
      'subagent_type: "Build"',
    ],
    "create.md": [
      "Create a specification with PRD, tasks, and workspace setup",
      'subagent_type: "Build"',
    ],
    "fix.md": ["Debug and fix a bug or failing test", 'subagent_type: "Build"'],
    "gc.md": [
      "Run garbage collection — Fallow analysis, quality grading, and cleanup PRs",
      'subagent_type: "Build"',
    ],
    "init.md": [
      "Initialize project setup — AGENTS.md, planning context, user profile, and tech stack",
      'subagent_type: "Build"',
    ],
    "plan.md": ["Create detailed implementation plan with TDD steps", 'subagent_type: "Plan"'],
    "release.md": [
      "Cut a Pikit pack release — bump version, verify, commit, and push",
      'subagent_type: "Build"',
    ],
    "research.md": ["Research a topic before implementation", 'subagent_type: "Scout"'],
    "ship.md": ["Ship a plan - implement specs, verify, review, close", 'subagent_type: "Build"'],
    "verify.md": [
      "Verify implementation completeness, correctness, and coherence",
      'subagent_type: "Review"',
    ],
  };
  const requiredSkillContracts = {
    "audit.md": [
      "code-navigation",
      "code-review-and-quality",
      ".pi/skills/workflow/scope-discipline/SKILL.md",
    ],
    "commit-push.md": [
      ".pi/skills/infra/git-workflow-and-versioning/SKILL.md",
      ".pi/skills/infra/github-ci/SKILL.md",
    ],
    "create.md": [
      ".pi/skills/workflow/spec-driven-development/SKILL.md",
      ".pi/skills/workflow/planning-and-task-breakdown/SKILL.md",
      ".pi/skills/context/documentation-and-adrs/SKILL.md",
      ".pi/skills/workflow/scope-discipline/SKILL.md",
    ],
    "fix.md": [
      ".pi/skills/code-quality/root-cause-tracing/SKILL.md",
      ".pi/skills/code-quality/verification-before-completion/SKILL.md",
    ],
    "gc.md": [
      ".pi/skills/code-quality/fallow/SKILL.md",
      ".pi/skills/code-quality/verification-before-completion/SKILL.md",
    ],
    "init.md": [
      ".pi/skills/workflow/brainstorming/SKILL.md",
      ".pi/skills/code-quality/verification-before-completion/SKILL.md",
    ],
    "release.md": [
      ".pi/skills/infra/git-workflow-and-versioning/SKILL.md",
      ".pi/skills/infra/github-ci/SKILL.md",
    ],
    "research.md": [
      ".pi/skills/context/research-tools/SKILL.md",
      ".pi/skills/context/external-facts/SKILL.md",
    ],
    "ship.md": [
      ".pi/skills/workflow/incremental-implementation/SKILL.md",
      ".pi/skills/workflow/scope-discipline/SKILL.md",
      ".pi/skills/code-quality/agent-code-quality-gate/SKILL.md",
      ".pi/skills/code-quality/verification-before-completion/SKILL.md",
      ".pi/skills/context/subagent-distrust/SKILL.md",
    ],
  };
  const expected = Object.keys(contracts).sort();
  const problems = [];
  if (JSON.stringify(prompts) !== JSON.stringify(expected)) {
    problems.push(`expected ${expected.join(", ")}; found ${prompts.join(", ")}`);
  }
  for (const [name, needles] of Object.entries(contracts)) {
    const path = `.pi/prompts/${name}`;
    if (!existsSync(join(root, path))) continue;
    const text = read(path);
    for (const needle of needles) {
      if (!text.includes(needle)) problems.push(`${path}: missing ${needle}`);
    }
    for (const skill of requiredSkillContracts[name] ?? []) {
      if (!text.includes(skill)) problems.push(`${path}: missing required skill contract ${skill}`);
    }
    if (!text.includes("Agent")) problems.push(`${path}: missing pi-subagents phase contract`);
    if (text.includes("Required skills:")) {
      problems.push(`${path}: legacy Required skills header present`);
    }
  }
  const expectedArgumentPrompts = [
    "audit.md",
    "commit-push.md",
    "create.md",
    "fix.md",
    "init.md",
    "release.md",
    "research.md",
    "verify.md",
  ];
  for (const name of expectedArgumentPrompts) {
    const text = existsSync(join(dir, name)) ? read(`.pi/prompts/${name}`) : "";
    if (!new RegExp(`^# .+: \\$ARGUMENTS$`, "m").test(text))
      problems.push(`.pi/prompts/${name}: heading must propagate $ARGUMENTS`);
  }

  addCheck(
    "prompt-agent-phase-routing",
    problems.length === 0,
    `${prompts.length} command contracts and ${Object.keys(requiredSkillContracts).length} required-skill mappings checked; problems=${problems.length}`,
    problems.slice(0, 5).join("; "),
  );

  const semanticContracts = {
    "create.md": {
      marker: "create",
      values: { discovery: "2..5", reviews: "1..5", synthesis: "all" },
    },
    "research.md": {
      marker: "research",
      values: {
        taskless: "true",
        "fanout-scout": "3..10",
        "fanout-explore": "0..3",
        "fanout-review": "2..10",
        "retrieval-total": "3..13",
      },
    },
    "ship.md": {
      marker: "ship",
      values: {
        aspects: "correctness,code-quality,performance-security",
        repeat: "after-fixes",
        blocking: "P0,P1,P2",
        "batch-implementers": "2..10",
        "batch-chunking": "true",
      },
    },
    "init.md": {
      marker: "init",
      values: { standalone: "true", "lifecycle-claim": "false" },
    },
    "plan.md": {
      marker: "plan",
      values: {
        split: "subsystem,file-ownership,files-over-5,discovery-checkpoint,half-context",
        "hard-cap": "none",
        "cohesion-exception": "true",
      },
    },
  };
  for (const [name, contract] of Object.entries(semanticContracts)) {
    const text = existsSync(join(dir, name)) ? read(`.pi/prompts/${name}`) : "";
    const marker = parseContractMarker(text, contract.marker);
    const invalid = Object.entries(contract.values)
      .filter(([key, value]) => marker?.[key] !== value)
      .map(([key, value]) => `${key}=${value} (found ${marker?.[key] ?? "missing"})`);
    addCheck(
      `prompt-${name.slice(0, -3)}-semantics`,
      marker !== null && invalid.length === 0,
      `pikit-contract:${contract.marker}; invalid=${invalid.length}`,
      marker === null
        ? `Missing pikit-contract:${contract.marker} marker`
        : `Restore approved values: ${invalid.join("; ")}`,
    );
  }

  const operativeProblems = [];
  const promptText = (name) => read(`.pi/prompts/${name}`);
  const createDiscovery = section(promptText("create.md"), "Phase 1: Choose Discovery Angles");
  const createGather = section(promptText("create.md"), "Phase 2: Gather Context");
  const createSynthesis = section(promptText("create.md"), "Phase 3: Build the Specification");
  if (
    !satisfiesCanonicalClause(
      createDiscovery,
      [/\b(?:must|required(?:ment)?)\b.{0,80}\b2[–-]5\b.{0,80}\bdiscovery angles?\b/i],
      [
        /(?:\bno requirement\b|\boptional\b|\bnot required\b).{0,80}\b(?:use\s+)?2[–-]5\b|\b2[–-]5\b.{0,80}(?:\bno requirement\b|\boptional\b|\bnot required\b)/i,
      ],
    )
  )
    operativeProblems.push("create.md: discovery prose must require 2–5 angles before synthesis");
  if (
    !ordered(createGather, [
      "Collect all discovery results",
      "1–5",
      "Review",
      "before synthesis",
      "Collect every review result",
    ])
  )
    operativeProblems.push(
      "create.md: discovery, 1–5 reviews, collection, and synthesis order missing",
    );
  if (!hasAll(createSynthesis, ["all 2–5 discovery results", "all 1–5 requirement-review results"]))
    operativeProblems.push("create.md: synthesis inputs do not include all bounded results");

  const researchContext = section(promptText("research.md"), "Phase 1: Context");
  const researchComplex = section(promptText("research.md"), "Complex Workflow");
  const researchContextText = normalized(researchContext);
  if (
    !satisfiesCanonicalClause(
      researchContext,
      [
        /\b(?:require|required|must)\b.{0,200}\bspec\.md\b|\bspec\.md\b.{0,200}\b(?:require|required|must)\b/i,
        /\b(?:treat|consider)\b.{0,100}\bprogress\.md\b.{0,100}\boptional\b|\bprogress\.md\b.{0,100}\b(?:is|remains?)\b.{0,40}\boptional\b/i,
      ],
      [
        /\b(?:allow|treat|consider|make)\b.{0,160}\bspec\.md\b.{0,80}\b(?:optional|not required)\b|\bspec\.md\b.{0,80}\b(?:is|remains?|be|becomes?)\b.{0,40}\b(?:optional|not required)\b|\b(?:optional|not required)\b.{0,80}\bspec\.md\b/i,
        /\brequire\b.{0,80}\bprogress\.md\b.{0,40}\b(?:exist|required|mandatory)\b|\b(?:mandatory|must-have)\b.{0,40}\bprogress\.md\b|\bprogress\.md\b.{0,120}\b(?:required|mandatory|must\s+exist)\b/i,
      ],
    ) ||
    !hasAll(researchContext, [
      "explicit existing",
      "taskless",
      "do not resolve",
      "original supplied string",
      "byte-for-byte equal",
      "decoded string",
      "task directory",
      "realpath",
      "TaskList",
      "state lookup",
      "not a filesystem artifact",
    ]) ||
    !/progress\.md.{0,80}only when|only when.{0,80}progress\.md/i.test(researchContextText)
  )
    operativeProblems.push(
      "research.md: taskless/slug/required spec/optional progress/realpath prose incomplete",
    );
  if (!hasAll(researchComplex, ["3–10", "Scout", "0–3", "Explore", "3 and 13", "2–10", "Review"]))
    operativeProblems.push("research.md: complex Scout/Explore/Review/total bounds missing");

  const shipBatch = section(promptText("ship.md"), "Phase 1: Route Execution");
  const shipReviews = section(promptText("ship.md"), "Phase 4: Final Reviews");
  if (
    !hasAll(shipBatch, ["2–10", "General", "more than 10", "waves of at most 10", "Between waves"])
  )
    operativeProblems.push("ship.md: batch cap and chunking prose missing");
  if (
    !hasAll(shipReviews, [
      "exactly three",
      "Correctness",
      "Code quality",
      "Performance/security",
      "P0/P1/P2",
    ]) ||
    !satisfiesCanonicalClause(
      shipReviews,
      [/\b(?:must|require\w*|then)\b.{0,120}\brepeat exactly the same three\b/i],
      [/\b(?:do not|must not|should not|never)\b.{0,80}\brepeat exactly the same three\b/i],
    )
  )
    operativeProblems.push("ship.md: final aspects/repeat/blocking prose missing");

  const initContract = section(promptText("init.md"), "Standalone Command Contract");
  if (
    !hasAll(initContract, ["standalone", "does not claim or require", "development-lifecycle.md"])
  )
    operativeProblems.push("init.md: standalone prose missing");
  const planPolicy = section(promptText("plan.md"), "Task Splitting Policy");
  if (
    !hasAll(planPolicy, [
      "subsystem boundaries",
      "file-ownership boundaries",
      "more than five files",
      "strong cohesion",
      "discovery or human checkpoints",
      "half an agent context window",
    ]) ||
    !satisfiesCanonicalClause(
      planPolicy,
      [/\b(?:there is|has|set)\b.{0,30}\bno hard cap\b/i],
      [/\b(?:must|shall|required?\w*|set|enforce\w*)\b.{0,50}\b(?:a|the) hard cap\b/i],
    )
  )
    operativeProblems.push("plan.md: boundary splitting/no-cap prose missing");

  addCheck(
    "prompt-operative-semantics",
    operativeProblems.length === 0,
    `bounded operative sections checked; problems=${operativeProblems.length}`,
    operativeProblems.slice(0, 8).join("; "),
  );

  const researchSlug = parseContractMarker(read(".pi/prompts/research.md"), "research-task-slug");
  addCheck(
    "research-task-slug-safety",
    researchSlug?.grammar === "^[a-z0-9]+(?:-[a-z0-9]+)*$" &&
      researchSlug?.containment === ".pi/docs/tasks" &&
      researchSlug?.["decode-before-validate"] === "true" &&
      researchSlug?.["original-equals-decoded"] === "true" &&
      researchSlug?.realpath === "true",
    "stable research slug marker requires canonical grammar, original-equals-decoded validation, and realpath task-root containment",
    "Restore the research-task-slug marker and validation/containment procedure",
  );
}

function checkWorkflows() {
  const requiredPacketFields = [
    "Objective",
    "Inputs and prior outputs",
    "Repository/file scope",
    "Non-goals",
    "Allowed actions",
    "Dependencies",
    "Output schema",
    "Acceptance",
    "Verification",
    "Stop/escalation",
  ];
  const semanticNeedles = {
    "audit-pattern": ["2 and 15", "taskless audit", "Never invent a slug"],
    "batch-implement": [
      "type definitions",
      "error handling",
      "unit tests",
      "Dependent/sequential branch",
      "Fan-in and merge",
    ],
    "deep-research": {
      needles: ["five consecutive retrievals", "answered", "partial", "unanswered"],
      marker: "deep-research",
      values: {
        "fanout-scout": "3..10",
        "fanout-explore": "0..3",
        "retrieval-total": "3..13",
        "fanout-review": "2..10",
      },
    },
    "development-lifecycle": [
      "Description, Pros, Cons, Complexity, Risks",
      "Direct/dependent path",
      "Correctness:",
      "Code quality:",
      "Performance/security:",
    ],
    "garbage-collection": ["Final report", "Trend: N/A", "PR status"],
  };
  const problems = [];
  try {
    const manifest = JSON.parse(read(".pi/workflows/manifest.json"));
    const expectedIds = Object.keys(semanticNeedles).sort();
    const actualIds = (manifest.workflows || []).map((item) => item.id).sort();
    if (JSON.stringify(expectedIds) !== JSON.stringify(actualIds))
      problems.push(
        `workflow IDs expected ${expectedIds.join(", ")}; found ${actualIds.join(", ")}`,
      );
    const routesByWorkflow = new Map();
    const workflowByFile = new Map();
    for (const item of manifest.workflows || []) {
      workflowByFile.set(item.file, item);
      for (const command of item.commands || []) {
        const routes = routesByWorkflow.get(command) || [];
        routes.push(item.file);
        routesByWorkflow.set(command, routes);
      }
    }
    for (const item of manifest.workflows || []) {
      const path = `.pi/workflows/${item.file}`;
      if (!existsSync(join(root, path))) {
        problems.push(`${path}: missing`);
        continue;
      }
      const text = read(path);
      if (!text.includes(`Workflow ID: \`${item.id}\``))
        problems.push(`${path}: workflow identity mismatch`);
      for (const field of requiredPacketFields)
        if (!text.includes(field)) problems.push(`${path}: missing phase packet field ${field}`);
      const semantics = semanticNeedles[item.id] || [];
      const needles = Array.isArray(semantics) ? semantics : semantics.needles;
      for (const needle of needles)
        if (!text.includes(needle)) problems.push(`${path}: missing semantic contract ${needle}`);
      if (!Array.isArray(semantics) && semantics.marker) {
        const marker = parseContractMarker(text, semantics.marker);
        const invalid = Object.entries(semantics.values)
          .filter(([key, value]) => marker?.[key] !== value)
          .map(([key, value]) => `${key}=${value} (found ${marker?.[key] ?? "missing"})`);
        if (marker === null)
          problems.push(`${path}: missing pikit-contract:${semantics.marker} marker`);
        else if (invalid.length > 0)
          problems.push(`${path}: restore approved values ${invalid.join("; ")}`);
        const phases = section(text, "Phases");
        if (
          !hasAll(phases, ["3–10", "Scout", "0–3", "Explore", "3–13", "2–10", "Review"]) ||
          !satisfiesCanonicalClause(
            phases,
            [/\b(?:must|required?\w*)\b.{0,80}\b3[–-]13\b/i],
            [/\b(?:do not|must not|should not|never|no requirement)\b.{0,80}\b(?:cap|3[–-]13)\b/i],
          )
        )
          problems.push(`${path}: operative phases must require the Scout/Explore total cap`);
      }
    }

    const expectedDeclarations = Object.fromEntries(
      (manifest.workflows || []).flatMap((item) =>
        (item.commands || []).map((command) => [command, []]),
      ),
    );
    for (const item of manifest.workflows || []) {
      for (const command of item.commands || []) expectedDeclarations[command].push(item.file);
    }
    const standalone = ["commit-push", "fix", "init", "release"];
    for (const command of standalone) expectedDeclarations[command] = ["standalone"];

    const promptNames = readdirSync(join(root, ".pi/prompts")).filter((entry) =>
      entry.endsWith(".md"),
    );
    for (const name of promptNames) {
      const command = name.slice(0, -3);
      const promptPath = `.pi/prompts/${name}`;
      const declarations = workflowDeclarations(read(promptPath));
      const expected = expectedDeclarations[command];
      if (!expected) {
        problems.push(`${promptPath}: no workflow declaration contract`);
        continue;
      }
      if (
        declarations.length !== expected.length ||
        [...declarations].sort().join("|") !== [...expected].sort().join("|")
      )
        problems.push(
          `${promptPath}: expected workflow markers ${expected.join(", ")}; found ${declarations.join(", ") || "none"}`,
        );
      if (declarations.includes("standalone") && declarations.length > 1)
        problems.push(`${promptPath}: standalone conflicts with workflow declaration`);
      for (const declaration of declarations) {
        if (declaration !== "standalone" && !workflowByFile.has(declaration))
          problems.push(`${promptPath}: unknown workflow marker ${declaration}`);
      }
      const registered = routesByWorkflow.get(command) || [];
      if (declarations.includes("standalone") && registered.length > 0)
        problems.push(`${promptPath}: standalone command is registered in manifest`);
      for (const file of registered)
        if (!declarations.includes(file))
          problems.push(`${promptPath}: manifest registers ${file} without matching marker`);
      for (const file of declarations.filter((value) => value !== "standalone"))
        if (!registered.includes(file))
          problems.push(`${promptPath}: marker ${file} has no manifest registration`);
    }
    for (const command of routesByWorkflow.keys()) {
      if (!promptNames.includes(`${command}.md`))
        problems.push(`manifest route ${command}: missing prompt`);
    }
  } catch (error) {
    problems.push(error instanceof Error ? error.message : String(error));
  }
  addCheck(
    "workflow-contract-parity",
    problems.length === 0,
    `manifest routes, phase packets, and workflow-specific semantics checked; problems=${problems.length}`,
    problems.slice(0, 8).join("; "),
  );
}

function agentSkills(path) {
  const frontmatter = parseFrontmatter(read(path));
  const raw = frontmatter.skills || "";
  if (raw === "true" || raw === "false") return raw;
  return raw
    .split(",")
    .map((name) => name.trim())
    .filter(Boolean);
}

function checkDocsLifecycle() {
  const workflow = read(".pi/skills/workflow/pikit-workflow/SKILL.md");
  const docsSkill = read(".pi/skills/context/documentation-and-adrs/SKILL.md");
  const lifecyclePrompts = ["create.md", "plan.md", "ship.md", "verify.md"];
  const missingPromptContracts = lifecyclePrompts.filter((name) => {
    const text = read(`.pi/prompts/${name}`);
    return !text.toLowerCase().includes("documentation") && !text.includes("docsRefs");
  });
  const stableOwners = ["Plan.md", "Review.md"];
  const missingOwners = stableOwners.filter((name) => {
    const skills = agentSkills(`.pi/agents/${name}`);
    return !Array.isArray(skills) || !skills.includes("documentation-and-adrs");
  });
  addCheck(
    "pikit-docs-lifecycle-skill",
    workflow.includes("Documentation Lifecycle") && workflow.includes("docs impact"),
    "pikit-workflow carries documentation lifecycle",
    "Restore docs lifecycle guidance in pikit-workflow",
  );
  const docsNeedles = [
    "Source-of-Truth Decision Table",
    "Task Metadata Convention",
    "docsRefs",
    "noDocsReason",
    "Verification Checklist",
  ];
  addCheck(
    "documentation-and-adrs-contract",
    docsNeedles.every((needle) => docsSkill.includes(needle)),
    docsNeedles.join(", "),
    "Restore documentation-and-adrs contract",
  );
  addCheck(
    "command-docs-lifecycle-contract",
    missingPromptContracts.length === 0 && missingOwners.length === 0,
    `command contracts=${lifecyclePrompts.join(", ")}; stable preloads=${stableOwners.join(", ")}`,
    [...missingPromptContracts, ...missingOwners].join(", "),
  );
}

function checkAgents() {
  const dir = join(root, ".pi/agents");
  const agentFiles = readdirSync(dir)
    .filter((name) => name.endsWith(".md"))
    .sort();
  const expectedAgents = [
    "Build.md",
    "Compaction.md",
    "Explore.md",
    "General.md",
    "Painter.md",
    "Plan.md",
    "Review.md",
    "Scout.md",
    "Vision.md",
  ];
  const forbiddenAgents = ["audit.md", "create.md", "fix.md", "gc.md", "init.md", "ship.md"];
  const problems = [];
  if (JSON.stringify(agentFiles) !== JSON.stringify(expectedAgents)) {
    problems.push(`expected ${expectedAgents.join(", ")}; found ${agentFiles.join(", ")}`);
  }
  for (const name of forbiddenAgents) {
    if (existsSync(join(dir, name))) problems.push(`forbidden command-specific agent: ${name}`);
  }
  const knownSkills = new Set(listSkillFiles().map((path) => path.split("/").at(-2)));
  for (const name of expectedAgents) {
    const path = `.pi/agents/${name}`;
    if (!existsSync(join(root, path))) continue;
    const skills = agentSkills(path);
    if (name === "Build.md") {
      if (skills !== "true") problems.push(`${path}: build must use skills: true`);
      continue;
    }
    if (skills === "false") continue;
    if (!Array.isArray(skills) || skills.length === 0) {
      problems.push(`${path}: skills mode missing`);
      continue;
    }
    for (const skill of skills) {
      if (!knownSkills.has(skill)) problems.push(`${path}: unknown skill ${skill}`);
    }
  }
  addCheck(
    "agent-role-and-skill-contract",
    problems.length === 0,
    `${agentFiles.length} reusable agents; forbidden command agents absent; problems=${problems.length}`,
    problems.slice(0, 5).join("; "),
  );
  const build = read(".pi/agents/Build.md");
  const general = read(".pi/agents/General.md");
  addCheck(
    "agent-delegation-contract",
    build.includes("Runtime Boundary") &&
      build.includes("Never promise nested delegation") &&
      general.includes("Run requested verification commands") &&
      !build.includes("REQUIRED SKILLS") &&
      !general.includes("REQUIRED SKILLS"),
    "lead owns fan-out; children execute one phase; no legacy Required skills packet",
    "Restore the non-recursive pi-subagents delegation contract",
  );
}

function checkExtensions() {
  const path = ".pi/extensions/pikit-routing.ts";
  const text = read(path);
  const needles = [
    "before_agent_start",
    "pikit_prompt_leverage",
    'subagent_type: "Vision"',
    "pikit-routing",
  ];
  const legacyPath = join(root, ".pi/extensions/pikit-skill-flow.ts");
  addCheck(
    "pikit-routing-contract",
    needles.every((needle) => text.includes(needle)) && !existsSync(legacyPath),
    `${path} owns prompt framing/image routing; legacy skill-flow absent`,
    "Restore pi-subagents routing extension and remove legacy skill-flow",
  );
}

function checkSyncScript() {
  const text = read("scripts/pikit-pi-sync.mjs");
  const needles = [
    "scripts/pikit-health.mjs",
    "scripts/pikit-pi-sync.mjs",
    '".pi/subagents.json"',
    ".pi/tasks/",
    ".pi/verify-cache.json",
    ".pi/task-registry.json",
    ".pi/task-session-history.json",
    ".pikit-backup",
  ];
  addCheck(
    "sync-script-shared-tools",
    needles.every((needle) => text.includes(needle)),
    needles.join(", "),
    "Keep downstream update/health tools synced and runtime state excluded",
  );
}

function checkGitAwareness() {
  try {
    const dirty = execFileSync("git", ["status", "--porcelain=v1", "--untracked-files=all"], {
      cwd: root,
      encoding: "utf8",
    })
      .trim()
      .split(/\r?\n/)
      .filter(Boolean);
    if (dirty.length > 0)
      addWarning(
        "git-dirty",
        `${dirty.length} dirty path(s): ${dirty.slice(0, 8).join(", ")}`,
        "Review before committing",
      );
    else addCheck("git-clean", true, "working tree clean");
  } catch (error) {
    addWarning("git-status", error instanceof Error ? error.message : String(error));
  }
}

checkSettings();
checkVendorExtensions();
checkVendorDcp();
checkNpmPackageConfig();
checkDcpConfig();
checkSkills();
checkSkillLint();
checkVendorLock();
checkPrompts();
checkWorkflows();
checkDocsLifecycle();
checkAgents();
checkExtensions();
checkSyncScript();
checkGitAwareness();

const failed = checks.filter((check) => !check.ok);
console.log("# Pikit Health Check\n");
console.log(
  table(
    ["Check", "Status", "Evidence", "Next action"],
    checks.map((check) => [
      check.name,
      check.ok ? "PASS" : "FAIL",
      check.evidence,
      check.ok ? "N/A" : check.next || "Fix required",
    ]),
  ),
);
if (warnings.length > 0) {
  console.log("\n## Warnings\n");
  console.log(
    table(
      ["Warning", "Evidence", "Next action"],
      warnings.map((warning) => [warning.name, warning.evidence, warning.next || "Review"]),
    ),
  );
}
console.log(
  "\n" +
    table(
      ["Summary", "Value"],
      [
        ["Status", failed.length === 0 ? "PASS" : "FAIL"],
        ["Checks", `${checks.length}`],
        ["Failures", `${failed.length}`],
        ["Warnings", `${warnings.length}`],
      ],
    ),
);
process.exitCode = failed.length === 0 ? 0 : 1;
