#!/usr/bin/env node

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import path from "node:path";

const testDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(testDir, "../..");
const script = path.join(repoRoot, "scripts/github-actions-policy.mjs");
const fixture = path.join(repoRoot, "tests/fixtures/github-actions-policy/fleet.json");
const grimnirUpstream = path.join(
  repoRoot,
  "tests/fixtures/github-actions-policy/grimnir-upstream.json",
);

function runFixture() {
  return spawnSync(process.execPath, [script, "--fixture", fixture, "--format", "json"], {
    cwd: repoRoot,
    encoding: "utf8",
  });
}

const first = runFixture();
assert.equal(first.status, 1, first.stderr);
assert.equal(first.stderr, "");
assert.ok(!first.stdout.includes("SECRET_MARKER"), "private workflow content leaked");
assert.ok(!first.stdout.includes("do-not-expose"), "private workflow command leaked");

const report = JSON.parse(first.stdout);
assert.equal(report.schema_version, 1);
assert.deepEqual(
  report.repositories.map(({ repository, workflow_count, uses_count, status }) => ({
    repository,
    workflow_count,
    uses_count,
    status,
  })),
  [
    { repository: "Magnus-Gille/alpha", workflow_count: 1, uses_count: 10, status: "audited" },
    { repository: "Magnus-Gille/billing-repo", workflow_count: 0, uses_count: 0, status: "evidence-unavailable" },
    { repository: "Magnus-Gille/transport-repo", workflow_count: 0, uses_count: 0, status: "evidence-unavailable" },
  ],
);

const compact = report.findings.map(({ owner_repo, category, code, evidence_reason }) => ({
  owner_repo,
  category,
  code,
  evidence_reason: evidence_reason ?? null,
}));
assert.deepEqual(compact, [
  {
    owner_repo: "Magnus-Gille/alpha",
    category: "policy",
    code: "floating-action-ref",
    evidence_reason: null,
  },
  {
    owner_repo: "Magnus-Gille/alpha",
    category: "policy",
    code: "missing-release-provenance",
    evidence_reason: null,
  },
  {
    owner_repo: "Magnus-Gille/alpha",
    category: "policy",
    code: "upstream-tag-sha-mismatch",
    evidence_reason: null,
  },
  {
    owner_repo: "Magnus-Gille/alpha",
    category: "policy",
    code: "action-runtime-node20",
    evidence_reason: null,
  },
  {
    owner_repo: "Magnus-Gille/alpha",
    category: "evidence",
    code: "action-manifest-unavailable",
    evidence_reason: "billing",
  },
  {
    owner_repo: "Magnus-Gille/alpha",
    category: "evidence",
    code: "upstream-tag-unavailable",
    evidence_reason: "transport",
  },
  {
    owner_repo: "Magnus-Gille/alpha",
    category: "policy",
    code: "action-runtime-unknown",
    evidence_reason: null,
  },
  {
    owner_repo: "Magnus-Gille/alpha",
    category: "policy",
    code: "floating-action-ref",
    evidence_reason: null,
  },
  {
    owner_repo: "Magnus-Gille/billing-repo",
    category: "evidence",
    code: "workflow-inventory-unavailable",
    evidence_reason: "billing",
  },
  {
    owner_repo: "Magnus-Gille/transport-repo",
    category: "evidence",
    code: "workflow-inventory-unavailable",
    evidence_reason: "transport",
  },
]);

assert.equal(
  report.findings.some((finding) => finding.action === "vendor/node24"),
  false,
  "approved Node 24 action produced a finding",
);
assert.equal(
  report.findings.some((finding) => finding.action === "./local-action"),
  false,
  "approved local Node 24 action produced a finding",
);
assert.deepEqual(report.summary, {
  repositories: 3,
  workflows: 1,
  uses: 10,
  policy_errors: 6,
  evidence_errors: 4,
});

const second = runFixture();
assert.equal(second.status, 1, second.stderr);
assert.equal(second.stdout, first.stdout, "report is not deterministic");

const fixtureDir = mkdtempSync(path.join(tmpdir(), "grimnir-actions-policy-"));
try {
  const workflowDir = path.join(repoRoot, ".github/workflows");
  const workflows = readdirSync(workflowDir)
    .filter((name) => /\.ya?ml$/.test(name))
    .sort()
    .map((name) => ({
      path: `.github/workflows/${name}`,
      content: readFileSync(path.join(workflowDir, name), "utf8"),
    }));
  const selfFixture = {
    repositories: [
      {
        repository: "Magnus-Gille/grimnir",
        owner_repo: "Magnus-Gille/grimnir",
        visibility: "private",
        snapshot_sha: "working-tree",
        workflows,
      },
    ],
    upstream: JSON.parse(readFileSync(grimnirUpstream, "utf8")),
  };
  const selfFixturePath = path.join(fixtureDir, "self.json");
  writeFileSync(selfFixturePath, `${JSON.stringify(selfFixture)}\n`);
  const self = spawnSync(
    process.execPath,
    [script, "--fixture", selfFixturePath, "--format", "json"],
    { cwd: repoRoot, encoding: "utf8" },
  );
  assert.equal(self.status, 0, self.stderr || self.stdout);
  const selfReport = JSON.parse(self.stdout);
  assert.deepEqual(selfReport.findings, []);
  assert.equal(selfReport.repositories[0].workflow_count, workflows.length);
} finally {
  rmSync(fixtureDir, { recursive: true, force: true });
}

process.stdout.write("github-actions-policy fixture tests: PASS\n");
