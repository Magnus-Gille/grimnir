import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const fixtures = path.join(root, "tests/fixtures/portability-acceptance");
const read = (name) => JSON.parse(fs.readFileSync(path.join(fixtures, name), "utf8"));
const positive = read("positive.json");
const negative = read("negative.json");
const claims = new Set(["transport", "configuration", "health", "copy_integrity", "restore"]);
const requiredFixtureRepos = new Set(["grimnir"]);
const nodeFixtures = JSON.parse(fs.readFileSync(path.join(root, "tests/fixtures/node-substrate-contract/positive.json"), "utf8")).records;
const date = (value) => typeof value === "string" && !Number.isNaN(Date.parse(value));
const fail = (message) => { throw new Error(message); };
const canonical = (value) => Array.isArray(value) ? `[${value.map(canonical).join(",")}]` : value && typeof value === "object" ? `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}` : JSON.stringify(value);
const digest = (value) => `sha256:${crypto.createHash("sha256").update(canonical(value)).digest("hex")}`;
const fixtureDigestByKind = new Map(nodeFixtures.map((record) => [record.kind, digest(record)]));

function validateScenario(scenario) {
  if (!scenario || typeof scenario !== "object") fail("scenario must be an object");
  if (!/^[a-z][a-z0-9-]{2,62}$/.test(scenario.scenario_id ?? "")) fail("invalid scenario id");
  if (!['conformance', 'dry_run'].includes(scenario.mode)) fail("unsupported or live scenario mode");
  if (scenario.synthetic_public_safe !== true) fail("scenario must be explicitly synthetic and public-safe");
  const operationalEvidence = scenario.operational_evidence ?? {};
  if (!['absent', 'unverified'].includes(operationalEvidence.status) || typeof operationalEvidence.reason !== "string" || operationalEvidence.reason.length < 20) fail("operational evidence must be absent or unverified");
  if (scenario.mode === "dry_run" && scenario.lifecycle_result?.outcome !== "not_started") fail("dry run cannot claim a lifecycle result");
  if (!Array.isArray(scenario.shared_fixtures) || scenario.shared_fixtures.length < 3) fail("missing shared fixture bindings");
  const fixtureRepos = new Set(scenario.shared_fixtures.map((fixture) => fixture.repository));
  for (const repo of requiredFixtureRepos) if (!fixtureRepos.has(repo)) fail(`missing immutable shared fixture for ${repo}`);
  for (const fixture of scenario.shared_fixtures) if (!/^[a-z][a-z0-9-]*$/.test(fixture.repository ?? "") || !/^[a-z0-9/_.-]+\.json$/.test(fixture.path ?? "") || !["node-capability", "workload-requirement", "placement-intent"].includes(fixture.record_kind) || fixture.fixture_digest !== fixtureDigestByKind.get(fixture.record_kind)) fail("invalid or mutable shared fixture binding");
  const plan = scenario.plan ?? {};
  if (!plan.plan_id || !["relocate"].includes(plan.action) || !["arm64", "x86_64"].includes(plan.target_architecture) || ![true, false].includes(plan.requires_wifi_profile) || !["adequate", "poor"].includes(plan.transfer_window) || typeof plan.reversal_recipe !== "string" || plan.reversal_recipe.length < 20) fail("invalid or unsafe plan");
  if (plan.transfer_window !== "adequate") fail("poor transfer window");
  const observations = scenario.fresh_observations ?? [];
  if (scenario.mode === "conformance" && observations.length === 0) fail("missing synthetic conformance observation");
  if (scenario.mode === "dry_run" && observations.length !== 0) fail("dry run must not claim fresh operational observations");
  const evidenceIds = new Set();
  for (const observation of observations) {
    if (!/^[a-z][a-z0-9-]{2,62}$/.test(observation.evidence_id ?? "") || !date(observation.observed_at) || !date(observation.valid_until) || Date.parse(observation.valid_until) <= Date.parse(observation.observed_at)) fail("stale evidence");
    if (observation.architecture !== plan.target_architecture) fail("wrong architecture");
    if (plan.requires_wifi_profile && observation.wifi_profile !== "present") fail("missing Wi-Fi profile");
    if (observation.mount !== "present") fail("absent mount");
    if (observation.monitoring !== "available") fail("monitoring outage");
    evidenceIds.add(observation.evidence_id);
  }
  if (!Array.isArray(scenario.operator_checkpoints) || scenario.operator_checkpoints.length === 0) fail("missing operator checkpoint");
  for (const checkpoint of scenario.operator_checkpoints) if ((checkpoint.evidence_id !== undefined && !evidenceIds.has(checkpoint.evidence_id)) || !["completed", "pending"].includes(checkpoint.status)) fail("invalid operator checkpoint");
  const lifecycle = scenario.lifecycle_result ?? {};
  if (!/^[a-z][a-z0-9-]{2,62}$/.test(lifecycle.attempt_id ?? "") || !["preflight", "verify"].includes(lifecycle.phase) || !["historical_completed", "not_started"].includes(lifecycle.outcome) || lifecycle.interrupted_apply !== false) fail("interrupted or invalid lifecycle result");
  if (!Array.isArray(scenario.service_verification) || scenario.service_verification.length === 0) fail("missing service verification");
  for (const verification of scenario.service_verification) if (!/^[a-z][a-z0-9-]*$/.test(verification.service ?? "") || !["verified", "not_run"].includes(verification.health) || !["verified", "not_run"].includes(verification.hook)) fail("failed health or hook");
  if (!Array.isArray(scenario.claims) || scenario.claims.length !== claims.size) fail("claims must separate every evidence category");
  const claimKinds = new Set();
  for (const claim of scenario.claims) { if (!claims.has(claim.kind) || claimKinds.has(claim.kind) || !["recorded", "not_run"].includes(claim.status) || (claim.evidence_id !== undefined && !evidenceIds.has(claim.evidence_id))) fail("invalid evidence claim"); claimKinds.add(claim.kind); }
  if (operationalEvidence.status !== "complete") {
    if (lifecycle.outcome !== "not_started" || lifecycle.phase !== "preflight" || scenario.service_verification.some((verification) => verification.health !== "not_run" || verification.hook !== "not_run") || scenario.claims.some((claim) => claim.status !== "not_run")) fail("incomplete pilot evidence cannot promote");
  }
}

assert.equal(positive.contract, "grimnir.portability-acceptance/v1");
assert.equal(positive.fixture_set, "portability-acceptance-v1");
assert.equal(positive.fixture_scope, "synthetic_public_safe_conformance");
assert.equal(positive.scenarios.length, 2, "the harness has exactly NAS and Hugin pilot scenarios");
for (const scenario of positive.scenarios) validateScenario(scenario);
assert.equal(positive.scenarios.find((scenario) => scenario.scenario_id === "example-nas-relocate")?.mode, "conformance");
assert.equal(positive.scenarios.find((scenario) => scenario.scenario_id === "example-hugin-relocate")?.mode, "dry_run");
for (const [name, negativeCase] of Object.entries(negative)) {
  const base = positive.scenarios.find((scenario) => scenario.scenario_id === negativeCase.base_scenario_id);
  assert.ok(base, `${name} has an otherwise-valid base scenario`);
  const mutated = structuredClone(base);
  const path = negativeCase.mutation?.path;
  assert.ok(Array.isArray(path) && path.length > 0, `${name} declares a mutation path`);
  let target = mutated;
  for (const segment of path.slice(0, -1)) target = target[segment];
  target[path.at(-1)] = negativeCase.mutation.value;
  assert.throws(() => validateScenario(mutated), (error) => {
    assert.match(error.message, new RegExp(negativeCase.expected_diagnostic.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
    return true;
  }, name);
}
console.log("Portability acceptance v1 validates two synthetic public-safe conformance scenarios plus 9 named fail-closed mutations.");
