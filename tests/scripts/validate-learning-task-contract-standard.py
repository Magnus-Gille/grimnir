#!/usr/bin/env python3
"""Validate the normative contract with a standards-compliant Draft 2020-12 engine."""

import copy
import json
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker


ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "tests" / "fixtures" / "learning-task-contract"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def mutate(record, mutation):
    tokens = [token.replace("~1", "/").replace("~0", "~") for token in mutation["path"][1:].split("/")]
    parent = record
    for token in tokens[:-1]:
        parent = parent[int(token)] if isinstance(parent, list) else parent[token]
    key = int(tokens[-1]) if isinstance(parent, list) else tokens[-1]
    if mutation["op"] == "set":
        parent[key] = copy.deepcopy(mutation["value"])
    elif mutation["op"] == "delete":
        del parent[key]
    elif mutation["op"] == "delete-array-item":
        parent[key].pop(mutation["index"])
    else:
        raise AssertionError(f"unknown fixture mutation: {mutation['op']}")


schema = load(ROOT / "docs" / "learning-task-contract-v1.schema.json")
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema, format_checker=FormatChecker())
positive = load(FIXTURES / "positive.json")
positive_derived = load(FIXTURES / "positive-derived.json")
tombstone = load(FIXTURES / "positive-erased.json")
negative = load(FIXTURES / "negative.json")

for index, record in enumerate([*positive, tombstone]):
    errors = list(validator.iter_errors(record))
    assert not errors, f"standard validator rejected positive record {index}: {errors[0].message if errors else ''}"

for definition in positive_derived:
    record = copy.deepcopy(positive[definition["from_positive"]])
    for mutation in definition["mutations"]:
        mutate(record, mutation)
    errors = list(validator.iter_errors(record))
    assert not errors, f"standard validator rejected derived positive {definition['name']}: {errors[0].message if errors else ''}"

schema_negative_names = {
    "unknown contract major",
    "missing gateway canonical prompt identity",
    "legacy joint rendered prompt is rejected",
    "capability evidence cannot be produced by Hugin",
    "task type vocabulary is closed",
    "raw fingerprint canonicalization is fixed",
    "invalid timestamp fails closed",
    "invalid raw hash fails closed",
    "repository commit ids are 40 to 64 lowercase hex",
    "task outcome cannot contain late product quality scalar",
    "experiment observation cannot contain late product outcome scalar",
    "policy unavailable projection cannot fabricate policies",
    "training export is closed in v1",
    "observed exposure version matches raw canonicalization",
    "negative coverage contains exact six lanes",
    "raw loopback is not an authenticated exposure lane",
    "experiment rating binds immutable observation id",
    "tombstone cannot retain task projection",
    "pending store readback cannot produce tombstone",
    "backup expiry must be confirmed before erasure",
}

by_name = {case["name"]: case for case in negative}
assert schema_negative_names <= by_name.keys(), "standard-validator case list drifted from adversarial fixtures"
for name in sorted(schema_negative_names):
    case = by_name[name]
    record = copy.deepcopy(tombstone if case.get("from_erased") else positive[case["from_positive"]])
    for mutation in case.get("mutations", []):
        mutate(record, mutation)
    assert list(validator.iter_errors(record)), f"standard validator unexpectedly accepted schema-negative case: {name}"

print(f"Draft 2020-12 validation passed: {len(positive) + len(positive_derived) + 1} positives and {len(schema_negative_names)} schema-negative cases.")
