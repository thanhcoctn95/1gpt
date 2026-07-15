#!/usr/bin/env node
// Pikit vendor integrity lock. Pins version + content hash for each vendored package.
// The vendor tree stays on disk (pi loads it at startup); this lock detects drift/tamper.
//
// Usage:
//   node scripts/pikit-vendor-lock.mjs            # regenerate .pi/vendor-lock.json
//   node scripts/pikit-vendor-lock.mjs --check     # verify on-disk vendor vs lock (exit 1 on mismatch)
import { readFileSync, writeFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { createHash } from "node:crypto";
import { join, relative } from "node:path";

const ROOT = process.cwd();
const CATALOG = join(ROOT, ".pi/catalog.json");
const LOCK = join(ROOT, ".pi/vendor-lock.json");
const VENDOR_BASE = ".pi/vendor/extensions";

const SKIP_DIRS = new Set(["node_modules", ".git", "media", "demo"]);
const SKIP_EXT = new Set([".gif", ".mp4", ".mov", ".png", ".jpg", ".jpeg", ".webp"]);

function walk(dir, base, acc) {
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    const st = statSync(full);
    if (st.isDirectory()) {
      if (SKIP_DIRS.has(name)) continue;
      walk(full, base, acc);
    } else {
      const ext = name.slice(name.lastIndexOf(".")).toLowerCase();
      if (SKIP_EXT.has(ext)) continue;
      acc.push(relative(base, full));
    }
  }
  return acc;
}

function dirHash(absDir) {
  const files = walk(absDir, absDir, []).sort();
  const h = createHash("sha256");
  for (const rel of files) {
    h.update(rel);
    h.update(
      createHash("sha256")
        .update(readFileSync(join(absDir, rel)))
        .digest(),
    );
  }
  return { hash: "sha256:" + h.digest("hex"), fileCount: files.length };
}

function build() {
  const catalog = JSON.parse(readFileSync(CATALOG, "utf-8"));
  const lock = {
    version: 1,
    note: "Vendor package integrity lock. Hash excludes media/node_modules/.git. Regenerate with scripts/pikit-vendor-lock.mjs",
    packages: {},
  };
  for (const it of catalog.integrations) {
    const dir = join(VENDOR_BASE, it.name);
    const abs = join(ROOT, dir);
    const entry = { source: it.source, install: it.install };
    if (existsSync(abs)) {
      let version = null;
      const pj = join(abs, "package.json");
      if (existsSync(pj)) {
        try {
          version = JSON.parse(readFileSync(pj, "utf-8")).version ?? null;
        } catch {
          /* ignore */
        }
      }
      const { hash, fileCount } = dirHash(abs);
      entry.vendorPath = "./" + dir;
      entry.version = version;
      entry.contentHash = hash;
      entry.fileCount = fileCount;
    } else {
      entry.vendorPath = null;
    }
    lock.packages[it.name] = entry;
  }
  return lock;
}

const isCheck = process.argv.includes("--check");
const fresh = build();

if (!isCheck) {
  writeFileSync(LOCK, JSON.stringify(fresh, null, 2) + "\n");
  const n = Object.keys(fresh.packages).length;
  console.log(`Wrote ${LOCK} (${n} packages).`);
  process.exit(0);
}

// --check mode
if (!existsSync(LOCK)) {
  console.error("vendor-lock.json missing. Run: node scripts/pikit-vendor-lock.mjs");
  process.exit(1);
}
const stored = JSON.parse(readFileSync(LOCK, "utf-8"));
const problems = [];
for (const [name, want] of Object.entries(stored.packages)) {
  const got = fresh.packages[name];
  if (!got) {
    problems.push(`${name}: in lock but missing from catalog`);
    continue;
  }
  if (want.vendorPath && !got.vendorPath) {
    problems.push(`${name}: vendor dir missing on disk`);
    continue;
  }
  if (want.contentHash && want.contentHash !== got.contentHash) {
    problems.push(
      `${name}: content hash mismatch (lock ${want.contentHash?.slice(0, 16)} vs disk ${got.contentHash?.slice(0, 16)})`,
    );
  }
  if (want.version && want.version !== got.version) {
    problems.push(`${name}: version mismatch (lock ${want.version} vs disk ${got.version})`);
  }
}
for (const name of Object.keys(fresh.packages)) {
  if (!stored.packages[name]) problems.push(`${name}: in catalog but not in lock (run regen)`);
}

if (problems.length === 0) {
  console.log(`vendor-lock OK: ${Object.keys(stored.packages).length} packages verified.`);
  process.exit(0);
}
console.error("vendor-lock MISMATCH:");
for (const p of problems) console.error("- " + p);
process.exit(1);
