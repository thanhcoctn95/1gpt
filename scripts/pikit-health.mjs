#!/usr/bin/env node
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { execFileSync } from "node:child_process";

const root = process.cwd();
const checks = [];
const warnings = [];

const CORE_VISIBLE_SKILLS = new Set([
  "using-skills",
  "pikit-workflow",
  "verification-before-completion",
]);

const OPTIONAL_HIDDEN_SKILLS = [
  "task-workflow",
  "scope-discipline",
  "subagent-distrust",
  "permission-safety",
];

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
  return readdirSync(base, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => `.pi/skills/${entry.name}/SKILL.md`)
    .filter((path) => existsSync(join(root, path)))
    .sort();
}

function checkSettings() {
  try {
    const settings = JSON.parse(read(".pi/settings.json"));
    addCheck("settings-json", true, ".pi/settings.json parses as JSON");
    addCheck("settings-skills-path", Array.isArray(settings.skills) && settings.skills.includes("skills"), "settings.skills includes skills");
    addCheck("settings-prompts-path", Array.isArray(settings.prompts) && settings.prompts.includes("prompts"), "settings.prompts includes prompts");
    addCheck("settings-agents-path", Array.isArray(settings.agents) && settings.agents.includes("agents"), "settings.agents includes agents");
    addCheck("settings-extensions-path", Array.isArray(settings.extensions) && settings.extensions.includes("extensions"), "settings.extensions includes extensions");
    addCheck("settings-token-speed-package", Array.isArray(settings.packages) && settings.packages.includes("npm:pi-token-speed"), "settings.packages includes npm:pi-token-speed", "Add npm:pi-token-speed to .pi/settings.json packages");
  } catch (error) {
    addCheck("settings-json", false, error instanceof Error ? error.message : String(error), "Fix .pi/settings.json syntax");
  }
}

function checkNpmPackageConfig() {
  try {
    const pkg = JSON.parse(read(".pi/npm/package.json"));
    const lock = JSON.parse(read(".pi/npm/package-lock.json"));
    const dep = pkg.dependencies?.["pi-token-speed"] ?? "";
    const lockDep = lock.packages?.[""]?.dependencies?.["pi-token-speed"] ?? "";
    const lockVersion = lock.packages?.["node_modules/pi-token-speed"]?.version ?? "";
    addCheck("npm-token-speed-dependency", dep === "^0.6.0", `package.json pi-token-speed=${dep || "missing"}`, "Run cd .pi/npm && npm install pi-token-speed@0.6.0");
    addCheck("npm-token-speed-lock", lockDep === "^0.6.0" && lockVersion === "0.6.0", `lock dep=${lockDep || "missing"}; installed=${lockVersion || "missing"}`, "Regenerate .pi/npm/package-lock.json from .pi/npm/package.json");
  } catch (error) {
    addCheck("npm-package-config", false, error instanceof Error ? error.message : String(error), "Fix .pi/npm package JSON/lockfile");
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
      if (value && !/^['"[{]/.test(value) && /:\s/.test(value)) frontmatterConflicts.push(`${path}: ${line.trim()}`);
    }
    return {
      path,
      name: frontmatter.name || path.split("/").at(-2),
      description: frontmatter.description || "",
      disabled: frontmatter["disable-model-invocation"] === "true",
    };
  });
  const visible = skills.filter((skill) => !skill.disabled).map((skill) => skill.name).sort();
  const hidden = skills.filter((skill) => skill.disabled).map((skill) => skill.name).sort();
  const expectedVisible = [...CORE_VISIBLE_SKILLS].sort();
  const visibleOk = visible.join("\0") === expectedVisible.join("\0");
  const descChars = skills.filter((skill) => !skill.disabled).reduce((sum, skill) => sum + skill.description.length, 0);
  const approxPromptChars = skills
    .filter((skill) => !skill.disabled)
    .reduce((sum, skill) => sum + skill.name.length + skill.description.length + skill.path.length + 75, 260);

  addCheck("skills-discovered", skills.length > 0, `${skills.length} skill files discovered`);
  addCheck("skill-frontmatter-compact-mapping", frontmatterConflicts.length === 0, `${skillFiles.length} skill frontmatters checked; conflicts=${frontmatterConflicts.length}`, frontmatterConflicts.slice(0, 3).join(", ") || "Quote YAML scalar values that contain ':'");
  addCheck("visible-skill-budget", visibleOk, `visible=${visible.length}: ${visible.join(", ")}`, `Expected only: ${expectedVisible.join(", ")}`);
  addCheck("visible-skill-desc-budget", descChars <= 320, `visible description chars=${descChars}`, "Keep core skill descriptions concise");
  addCheck("visible-skill-token-budget", Math.floor(approxPromptChars / 4) <= 260, `approx skill prompt tokens=${Math.floor(approxPromptChars / 4)}`, "Reduce visible skill count/descriptions");
  for (const name of OPTIONAL_HIDDEN_SKILLS) {
    addCheck(`hidden-${name}`, hidden.includes(name), `${name} hidden/load-on-demand`, `Add disable-model-invocation: true to ${name}`);
  }
}

function checkPrompts() {
  const dir = join(root, ".pi/prompts");
  const prompts = existsSync(dir) ? readdirSync(dir).filter((name) => name.endsWith(".md")).sort() : [];
  const missing = [];
  for (const name of prompts) {
    const path = `.pi/prompts/${name}`;
    const text = read(path);
    if (!text.includes("Required skills:") || !text.includes("using-skills") || !text.includes("Phase 0: Intent and Skill Routing")) missing.push(path);
    if (!text.includes("Do not use fenced code blocks of any language in the final report")) missing.push(`${path} (final-report rule)`);
  }
  addCheck("prompt-routing", missing.length === 0, `${prompts.length} prompts checked; missing=${missing.length}`, missing.slice(0, 5).join(", "));
}


function checkDocsLifecycle() {
  const files = {
    routing: read(".pi/docs/intent-and-skill-routing.md"),
    workflow: read(".pi/skills/pikit-workflow/SKILL.md"),
    docsSkill: read(".pi/skills/documentation-and-adrs/SKILL.md"),
    create: read(".pi/prompts/create.md"),
    plan: read(".pi/prompts/plan.md"),
    ship: read(".pi/prompts/ship.md"),
    update: read(".pi/prompts/update.md"),
    review: read(".pi/prompts/review.md"),
    reviewCodebase: read(".pi/prompts/review-codebase.md"),
    verify: read(".pi/prompts/verify.md"),
    curate: read(".pi/prompts/curate.md"),
    apply: read(".pi/docs/apply-pikit-to-project.md"),
    upgrade: read(".pi/docs/upgrade-acceptance-checklist.md"),
  };
  const contractNeedles = [
    ["docs-lifecycle-contract", files.routing, ["Documentation Lifecycle", "Documentation Storage Decision"]],
    ["pikit-docs-lifecycle-skill", files.workflow, ["Documentation Lifecycle", "docs impact"]],
    ["documentation-and-adrs-contract", files.docsSkill, ["Source-of-Truth Decision Table", "Task Metadata Convention", "docsRefs", "noDocsReason", "Verification Checklist"]],
    ["create-docs-impact", files.create, ["Docs impact", "Docs acceptance", "Decision/ADR need"]],
    ["create-docs-refs", files.create, ["Docs refs", "Decision refs", "No docs reason", "docsRefs", "decisionRefs", "noDocsReason"]],
    ["plan-docs-impact", files.plan, ["source-of-truth docs", "Documentation impact", "ADR/decision need"]],
    ["plan-docs-refs", files.plan, ["docsRefs", "decisionRefs", "noDocsReason"]],
    ["ship-docs-impact", files.ship, ["documentation impact check", "Documentation impact"]],
    ["ship-docs-refs", files.ship, ["docsRefs", "noDocsReason"]],
    ["update-docs-skill", files.update, ["documentation-and-adrs", "source-of-truth hierarchy"]],
    ["review-docs-mismatch", files.review, ["behavior-doc mismatch", "Docs / contract mismatches"]],
    ["review-docs-refs", files.review, ["docsRefs", "noDocsReason"]],
    ["review-codebase-docs-mismatch", files.reviewCodebase, ["behavior-doc mismatch", "Docs / contract mismatches"]],
    ["review-codebase-docs-refs", files.reviewCodebase, ["docsRefs", "noDocsReason"]],
    ["verify-docs-coherence", files.verify, ["package/config/implementation behavior", "docs-impact reason"]],
    ["curate-docs-storage", files.curate, ["Docs/ADR decision", "source-of-truth guidance"]],
    ["apply-docs-lifecycle", files.apply, ["Docs lifecycle contract is present", "behavior-doc mismatch"]],
    ["upgrade-docs-lifecycle", files.upgrade, ["Docs lifecycle", "documentation-and-adrs", "behavior-doc mismatch"]],
  ];
  for (const [name, text, needles] of contractNeedles) {
    const missing = needles.filter((needle) => !text.includes(needle));
    addCheck(name, missing.length === 0, missing.length === 0 ? needles.join(", ") : `missing: ${missing.join(", ")}`, "Restore docs lifecycle contract text");
  }
}

function checkAgents() {
  const build = read(".pi/agents/build.md");
  const general = read(".pi/agents/general-purpose.md");
  const review = read(".pi/agents/review.md");
  const buildNeedles = ["ORIGINAL USER PROMPT", "REQUIRED SKILLS", "USING-SKILLS PROTOCOL", "ACCEPTANCE CHECKS", "Post-Delegation Acceptance Gate"];
  const generalNeedles = ["If the packet lists `REQUIRED SKILLS` or `using-skills`", "Load/read required skill files", "Run requested verification commands"];
  const reviewNeedles = ["findings-first", "Severity", "Verification status"];
  addCheck("build-delegation-contract", buildNeedles.every((needle) => build.includes(needle)), buildNeedles.join(", "));
  addCheck("general-skill-load-contract", generalNeedles.every((needle) => general.includes(needle)), generalNeedles.join(", "));
  addCheck("review-agent-contract", reviewNeedles.every((needle) => review.includes(needle)), reviewNeedles.join(", "));
}

function checkExtensions() {
  const text = read(".pi/extensions/pikit-skill-flow.ts");
  const needles = [
    "before_agent_start",
    "filter((skill) => !skill.disableModelInvocation)",
    "visibleSkillCount",
    "Hidden/load-on-demand",
    "<pikit_start_of_work_guard>",
    "ORIGINAL USER PROMPT",
    "REQUIRED SKILLS",
    "USING-SKILLS PROTOCOL",
  ];
  addCheck("pikit-skill-flow-contract", needles.every((needle) => text.includes(needle)), needles.join(", "));
  try {
    execFileSync("npx", ["--no-install", "tsx", "-e", "import '../extensions/pikit-skill-flow.ts'; console.log('ok')"], {
      cwd: join(root, ".pi/npm"),
      stdio: "pipe",
      encoding: "utf8",
    });
    addCheck("pikit-skill-flow-import", true, "tsx import succeeded");
  } catch (error) {
    addCheck("pikit-skill-flow-import", false, error instanceof Error ? error.message : String(error), "Run cd .pi/npm && npm install, then retry");
  }
}

function checkGitAwareness() {
  try {
    const dirty = execFileSync("git", ["status", "--porcelain=v1", "--untracked-files=all"], { cwd: root, encoding: "utf8" })
      .trim()
      .split(/\r?\n/)
      .filter(Boolean);
    if (dirty.length > 0) addWarning("git-dirty", `${dirty.length} dirty path(s): ${dirty.slice(0, 8).join(", ")}`, "Review before committing");
    else addCheck("git-clean", true, "working tree clean");
  } catch (error) {
    addWarning("git-status", error instanceof Error ? error.message : String(error));
  }
}

checkSettings();
checkNpmPackageConfig();
checkSkills();
checkPrompts();
checkDocsLifecycle();
checkAgents();
checkExtensions();
checkGitAwareness();

const failed = checks.filter((check) => !check.ok);
console.log("# Pikit Health Check\n");
console.log(table(["Check", "Status", "Evidence", "Next action"], checks.map((check) => [check.name, check.ok ? "PASS" : "FAIL", check.evidence, check.ok ? "N/A" : check.next || "Fix required"] )));
if (warnings.length > 0) {
  console.log("\n## Warnings\n");
  console.log(table(["Warning", "Evidence", "Next action"], warnings.map((warning) => [warning.name, warning.evidence, warning.next || "Review"] )));
}
console.log("\n" + table(["Summary", "Value"], [
  ["Status", failed.length === 0 ? "PASS" : "FAIL"],
  ["Checks", `${checks.length}`],
  ["Failures", `${failed.length}`],
  ["Warnings", `${warnings.length}`],
]));
process.exitCode = failed.length === 0 ? 0 : 1;
