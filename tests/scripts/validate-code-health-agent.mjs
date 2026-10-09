import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { aggregateRecords, schema, validateRecord, validateRecords } from '../../scripts/lib/code-health-agent.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const fixtureDir = path.join(root, 'tests/fixtures/code-health');
const readFixture = (name) => JSON.parse(fs.readFileSync(path.join(fixtureDir, name), 'utf8'));
const positive = readFixture('agent-positive.json');
const adversarial = readFixture('agent-adversarial.json');
const clone = (value) => structuredClone(value);

assert.equal(schema.$id, 'https://grimnir.gille.ai/contracts/code-health-agent/v1/schema.json');
assert.doesNotThrow(() => validateRecord(positive.records[0]), 'a closed v1 observation validates');
assert.doesNotThrow(() => validateRecords(positive.records), 'synthetic observations and assessments validate as a batch');

const aggregate = aggregateRecords(positive.records, { expectedAttempts: positive.coverage_expected_attempts });
assert.equal(aggregate.replay_count, 1, 'replaying the same record ID and payload is idempotent');
const mainOccurrence = aggregate.occurrences.find((entry) => entry.occurrence_id === 'ref:occurrence-main');
assert.equal(mainOccurrence.records.length, 4, 'worker and close reports retain provenance inside one occurrence');
assert.equal(mainOccurrence.conflict, true, 'conflicting polarity is surfaced without selecting a winner');
assert.equal(mainOccurrence.variants.length, 3, 'dimension, polarity, and cause disagreement are retained as variants');
assert.ok(aggregate.occurrences.some((entry) => entry.occurrence_id === 'ref:occurrence-retry'), 'a distinct retry occurrence stays distinct');
assert.equal(aggregate.occurrences.length, 3);
const mainAssessmentAttempt = aggregate.assessment_attempts.find((entry) => entry.attempt_id === 'parent-attempt');
assert.equal(mainAssessmentAttempt.records.length, 2, 'correction appends an assessment record');
assert.equal(mainAssessmentAttempt.rating_conflict, true, 'assessment rating conflicts stay visible; no newest value is chosen');
assert.equal(aggregate.assessments.length, 8, 'all assessment records remain available');
assert.equal(aggregate.assessment_coverage.numerator, 5, 'coverage counts unique applicable attempts by full identity');
assert.equal(aggregate.assessment_coverage.denominator, 6);
assert.ok(Math.abs(aggregate.assessment_coverage.fraction - (5 / 6)) < 1e-12);
assert.equal(aggregate.assessment_coverage.expected_attempts.filter((entry) => entry.attempt_id === 'shared-attempt').length, 3,
  'same attempt IDs in separate repositories/tasks remain separate expected identities');
assert.equal(aggregate.assessment_coverage.assessed_eligible_attempts.filter((entry) => entry.attempt_id === 'shared-attempt').length, 2,
  'QA not_applicable assessments do not count as eligible coverage');
assert.equal(aggregate.assessment_attempts.filter((entry) => entry.attempt_id === 'shared-attempt').length, 3,
  'assessment participation groups use repo/task/attempt identity rather than attempt_id alone');
assert.throws(() => aggregateRecords(positive.records, { expectedAttempts: [
  { repo_owner: 'example-org', repo_name: 'sample-project', task_id: 'task-qa', attempt_id: 'qa-attempt' }
] }), /not_applicable/);
assert.throws(() => aggregateRecords(positive.records, { expectedAttempts: [
  positive.coverage_expected_attempts[0], positive.coverage_expected_attempts[0]
] }), /unique by complete repo\/task\/attempt identity/);
assert.equal(aggregate.assessments.find((entry) => entry.task_class === 'qa').applicability, 'not_applicable');
const environmentUnavailable = aggregate.assessments.find((entry) => entry.task_id === 'task-env');
assert.equal(environmentUnavailable.environment, 'unavailable');
assert.equal(environmentUnavailable.ratings.find((entry) => entry.dimension === 'understand').value, 'manageable', 'code can remain assessable when verification environment is unavailable');
assert.equal(environmentUnavailable.ratings.find((entry) => entry.dimension === 'verify').value, 'not-assessable');
assert.equal(aggregate.assessments.find((entry) => entry.task_id === 'task-partial').completeness, 'partial');
assert.equal(aggregate.assessments.find((entry) => entry.task_id === 'task-main').actual_worker.observed_model, null, 'unknown observed model remains unknown');
assert.equal(aggregate.assessments.find((entry) => entry.task_id === 'task-main').actual_worker.requested_model, 'gpt-6.1-sol', 'requested model is kept separate from observed model');
const unknownCoverage = aggregateRecords(positive.records);
assert.equal(unknownCoverage.assessment_coverage.expected_attempts, null);
assert.equal(unknownCoverage.assessment_coverage.numerator, 5, 'unknown denominator does not hide observed applicable participation');
assert.equal(unknownCoverage.assessment_coverage.denominator, null);
assert.equal(unknownCoverage.assessment_coverage.fraction, null, 'unknown coverage is not converted into a score');

function recordsWithMutations(mutations) {
  const records = clone(positive.records);
  for (const mutation of mutations) {
    const index = records.findIndex((record) => record.record_id === mutation.record_id);
    assert.notEqual(index, -1, `fixture target ${mutation.record_id} exists`);
    const changed = { ...records[index], ...clone(mutation.patch) };
    if (mutation.duplicate) records.push(changed);
    else records[index] = changed;
  }
  return records;
}

for (const testCase of adversarial.patch_cases) {
  assert.throws(
    () => validateRecords(recordsWithMutations([{ record_id: testCase.record_id, patch: testCase.patch }])),
    undefined,
    `${testCase.name} is rejected`
  );
}
for (const testCase of adversarial.batch_cases) {
  assert.throws(
    () => validateRecords(recordsWithMutations(testCase.mutations)),
    undefined,
    `${testCase.name} is rejected`
  );
}

const originalWorker = positive.records.find((record) => record.record_id === 'ref:rec-worker');
const correctedWorker = clone(originalWorker);
correctedWorker.record_id = 'ref:rec-worker-corrected';
correctedWorker.supersedes_record_id = originalWorker.record_id;
correctedWorker.correction_ref = 'ref:correction-worker';
correctedWorker.summary = 'A later worker report corrects this occurrence.';
assert.throws(() => validateRecords([correctedWorker]), /absent from the supplied validation context/);
assert.doesNotThrow(
  () => validateRecords([correctedWorker], { contextRecords: [originalWorker] }),
  'an explicit external context can resolve an earlier correction target'
);

const closeObservation = positive.records.find((record) => record.record_id === 'ref:rec-close');
assert.doesNotThrow(
  () => validateRecords([closeObservation], { contextRecords: [originalWorker] }),
  'incremental close reports resolve their source observation from explicit context'
);
const incrementalAggregate = aggregateRecords([closeObservation], { contextRecords: [originalWorker] });
assert.deepEqual(incrementalAggregate.occurrences[0].records.map((record) => record.record_id), ['ref:rec-close'],
  'context records validate references but are not emitted as newly aggregated observations');
const mainAssessment = positive.records.find((record) => record.record_id === 'ref:assess-main');
const contextClose = positive.records.find((record) => record.record_id === 'ref:rec-close');
assert.doesNotThrow(
  () => validateRecords([mainAssessment], { contextRecords: [originalWorker, contextClose] }),
  'assessment references and child lineage resolve over the union of batch and context'
);
const collidingContext = { ...originalWorker, summary: 'A different payload for the same record identity.' };
assert.throws(() => validateRecords([originalWorker], { contextRecords: [collidingContext] }), /different payload/);

const mixedSource = clone(originalWorker);
mixedSource.record_id = 'ref:mixed-source-a';
mixedSource.supersedes_record_id = 'ref:mixed-source-b';
mixedSource.correction_ref = 'ref:mixed-correction-a';
const mixedCorrection = clone(originalWorker);
mixedCorrection.record_id = 'ref:mixed-source-b';
mixedCorrection.reporter = { ...mixedCorrection.reporter, id: 'ref:report-mixed-b', kind: 'parent' };
mixedCorrection.source_observation_ref = 'ref:mixed-source-a';
assert.throws(
  () => validateRecords([mixedSource], { contextRecords: [mixedCorrection] }),
  /cycle/,
  'mixed source and correction lineage cycles are rejected across the union'
);

const wrongOccurrenceCorrection = clone(originalWorker);
wrongOccurrenceCorrection.record_id = 'ref:worker-wrong-occurrence';
wrongOccurrenceCorrection.occurrence_id = 'ref:another-occurrence';
wrongOccurrenceCorrection.supersedes_record_id = originalWorker.record_id;
wrongOccurrenceCorrection.correction_ref = 'ref:wrong-occurrence-correction';
assert.throws(
  () => validateRecords([wrongOccurrenceCorrection], { contextRecords: [originalWorker] }),
  /occurrence/,
  'observation corrections remain within the original occurrence'
);

console.log(`Validated ${positive.records.length} positive records and rejected ${adversarial.patch_cases.length + adversarial.batch_cases.length} adversarial batches.`);

assert.throws(() => aggregateRecords([], { expectedAttempts: [{ repo_owner: 'example', repo_name: 'repo', task_id: 12, attempt_id: 'attempt' }] }), /unsafe identity/, 'identity fields must be strings, not coercible numbers');
const missingObservationRubric = structuredClone(positive.records.find(record => record.record_kind === 'observation'));
delete missingObservationRubric.rubric_version;
assert.throws(() => validateRecord(missingObservationRubric), TypeError, 'observations bind their rubric explicitly');
const tooManyChildren = structuredClone(positive.records.find(record => record.record_kind === 'assessment'));
tooManyChildren.child_attempt_ids = Array.from({ length: 129 }, (_, n) => `child-${n}`);
assert.throws(() => validateRecord(tooManyChildren), TypeError, 'child lineage is bounded');

const externalChildren = structuredClone(positive.records);
for (const record of externalChildren) if (record.record_kind === 'assessment' && record.attempt_id === 'parent-attempt') record.child_attempt_ids.push('native-unassessed-child');
const withExternalChildren = aggregateRecords(externalChildren);
assert.equal(withExternalChildren.assessment_coverage.numerator, unknownCoverage.assessment_coverage.numerator, 'owner-resolved unassessed child lineage does not invent participation');
