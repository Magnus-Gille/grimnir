#!/usr/bin/env node
import { readFileSync } from "node:fs";
const file = process.argv[2];
if (!file) throw new Error("usage: validate-system-roi-ledger.mjs FILE.json");
const ledger = JSON.parse(readFileSync(file, "utf8"));
const fail = (message) => { throw new Error(`${file}: ${message}`); };
const provenanceKinds = new Set(["measurement", "estimate_method", "owner_statement", "owner_input_required", "incident_record"]);
const statuses = new Set(["unknown", "estimate", "measured"]);
if (ledger.version !== "system-roi-ledger-v1") fail("version must be system-roi-ledger-v1");
if (!/^([0-9]{4}-(0[1-9]|1[0-2])|YYYY-MM)$/.test(ledger.period)) fail("period must be YYYY-MM (or the untouched template placeholder)");
if (!new Set(["not_reviewed", "reviewed"]).has(ledger.review_status)) fail("invalid review_status");
if (!Array.isArray(ledger.metrics) || !Array.isArray(ledger.service_decisions)) fail("metrics and service_decisions must be arrays");
const checkProvenance = (provenance, label) => {
  if (!provenance || !provenanceKinds.has(provenance.kind) || typeof provenance.reference !== "string" || !provenance.reference.trim()) fail(`${label} requires explicit provenance kind and reference`);
};
for (const metric of ledger.metrics) {
  if (typeof metric.name !== "string" || typeof metric.unit !== "string" || !statuses.has(metric.evidence_status)) fail("invalid metric identity or evidence_status");
  checkProvenance(metric.provenance, `metric ${metric.name}`);
  if (metric.evidence_status === "unknown" && metric.value !== null) fail(`metric ${metric.name}: unknown evidence must use null value`);
  if (metric.evidence_status !== "unknown" && (metric.value === null || metric.value === undefined)) fail(`metric ${metric.name}: estimate/measured evidence needs a value`);
  if (metric.evidence_status === "estimate" && metric.provenance.kind !== "estimate_method") fail(`metric ${metric.name}: estimate requires estimate_method provenance`);
  if (metric.evidence_status === "measured" && !new Set(["measurement", "incident_record"]).has(metric.provenance.kind)) fail(`metric ${metric.name}: measured requires measurement or incident_record provenance`);
}
for (const service of ledger.service_decisions) {
  if (typeof service.service !== "string" || !new Set(["keep", "fix", "cut", "revisit"]).has(service.decision)) fail("service decisions must be keep, fix, cut, or revisit");
  if (!new Set(["estimate", "measured"]).has(service.evidence_status) || typeof service.evidence !== "string" || !service.evidence.trim()) fail(`service ${service.service}: decision requires non-unknown evidence`);
  checkProvenance(service.provenance, `service ${service.service}`);
}
const system = ledger.system_decision;
if (!system || !statuses.has(system.evidence_status) || !Object.hasOwn(system, "value")) fail("system_decision is invalid");
checkProvenance(system.provenance, "system decision");
if (system.evidence_status === "unknown" && system.value !== null) fail("unknown system decision must use null value");
if (system.evidence_status !== "unknown" && !new Set(["keep", "fix", "cut", "revisit"]).has(system.value)) fail("reviewed system decision must be keep, fix, cut, or revisit");
console.log(`PASS: ${file}`);
