#!/usr/bin/env node
import { readFileSync } from "node:fs";
const file = process.argv[2];
if (!file) throw new Error("usage: validate-system-roi-ledger.mjs FILE.json");
const ledger = JSON.parse(readFileSync(file, "utf8"));
const fail = (message) => { throw new Error(`${file}: ${message}`); };
const provenanceKinds = new Set(["measurement", "estimate_method", "owner_statement", "owner_input_required", "incident_record"]);
const statuses = new Set(["unknown", "estimate", "measured"]);
const object = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const checkKeys = (value, allowed, label) => {
  if (!object(value)) fail(`${label} must be an object`);
  for (const key of Object.keys(value)) if (!allowed.has(key)) fail(`${label} has unexpected key ${key}`);
};
checkKeys(ledger, new Set(["version", "period", "review_status", "metrics", "service_decisions", "system_decision"]), "ledger");
if (ledger.version !== "system-roi-ledger-v1") fail("version must be system-roi-ledger-v1");
if (!/^([0-9]{4}-(0[1-9]|1[0-2])|YYYY-MM)$/.test(ledger.period)) fail("period must be YYYY-MM (or the untouched template placeholder)");
if (!new Set(["not_reviewed", "reviewed"]).has(ledger.review_status)) fail("invalid review_status");
if (!Array.isArray(ledger.metrics) || !Array.isArray(ledger.service_decisions)) fail("metrics and service_decisions must be arrays");
const checkProvenance = (provenance, label) => {
  checkKeys(provenance, new Set(["kind", "reference"]), `${label} provenance`);
  if (!provenance || !provenanceKinds.has(provenance.kind) || typeof provenance.reference !== "string" || !provenance.reference.trim()) fail(`${label} requires explicit provenance kind and reference`);
};
for (const metric of ledger.metrics) {
  checkKeys(metric, new Set(["name", "unit", "evidence_status", "value", "provenance"]), "metric");
  if (typeof metric.name !== "string" || typeof metric.unit !== "string" || !statuses.has(metric.evidence_status)) fail("invalid metric identity or evidence_status");
  checkProvenance(metric.provenance, `metric ${metric.name}`);
  if (metric.evidence_status === "unknown" && metric.value !== null) fail(`metric ${metric.name}: unknown evidence must use null value`);
  if (metric.evidence_status !== "unknown" && typeof metric.value !== "number") fail(`metric ${metric.name}: estimate/measured evidence needs a numeric value`);
  if (metric.evidence_status === "estimate" && metric.provenance.kind !== "estimate_method") fail(`metric ${metric.name}: estimate requires estimate_method provenance`);
  if (metric.evidence_status === "measured" && !new Set(["measurement", "incident_record"]).has(metric.provenance.kind)) fail(`metric ${metric.name}: measured requires measurement or incident_record provenance`);
}
for (const service of ledger.service_decisions) {
  checkKeys(service, new Set(["service", "decision", "evidence_status", "evidence", "provenance"]), "service decision");
  if (typeof service.service !== "string" || !new Set(["keep", "fix", "cut", "revisit"]).has(service.decision)) fail("service decisions must be keep, fix, cut, or revisit");
  if (!new Set(["estimate", "measured"]).has(service.evidence_status) || typeof service.evidence !== "string" || !service.evidence.trim()) fail(`service ${service.service}: decision requires non-unknown evidence`);
  checkProvenance(service.provenance, `service ${service.service}`);
  if (service.evidence_status === "estimate" && service.provenance.kind !== "estimate_method") fail(`service ${service.service}: estimate requires estimate_method provenance`);
  if (service.evidence_status === "measured" && !new Set(["measurement", "incident_record"]).has(service.provenance.kind)) fail(`service ${service.service}: measured requires measurement or incident_record provenance`);
}
const system = ledger.system_decision;
checkKeys(system, new Set(["value", "evidence_status", "provenance", "rationale"]), "system decision");
if (!system || !statuses.has(system.evidence_status) || !Object.hasOwn(system, "value")) fail("system_decision is invalid");
checkProvenance(system.provenance, "system decision");
if (ledger.review_status === "not_reviewed") {
  if (ledger.service_decisions.length !== 0) fail("not_reviewed ledger cannot contain service decisions");
  if (Object.hasOwn(system, "rationale")) fail("not_reviewed ledger cannot contain a system rationale");
  if (system.evidence_status !== "unknown" || system.value !== null || system.provenance.kind !== "owner_input_required") fail("not_reviewed ledger must retain an unknown/null owner-input-required system decision");
} else {
  if (!new Set(["estimate", "measured"]).has(system.evidence_status) || !new Set(["keep", "fix", "cut", "revisit"]).has(system.value)) fail("reviewed system decision must be keep, fix, cut, or revisit with estimate/measured evidence");
  if (typeof system.rationale !== "string" || !system.rationale.trim()) fail("reviewed system decision requires a rationale");
  if (system.evidence_status === "estimate" && system.provenance.kind !== "estimate_method") fail("estimated system decision requires estimate_method provenance");
  if (system.evidence_status === "measured" && !new Set(["measurement", "incident_record"]).has(system.provenance.kind)) fail("measured system decision requires measurement or incident_record provenance");
}
console.log(`PASS: ${file}`);
