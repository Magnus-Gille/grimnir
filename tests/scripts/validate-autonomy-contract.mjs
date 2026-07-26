import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"../.."); const read=n=>JSON.parse(fs.readFileSync(path.join(root,n),"utf8")); const plain=v=>v&&typeof v==="object"&&!Array.isArray(v); const canon=v=>plain(v)?"{"+Object.keys(v).sort().map(k=>JSON.stringify(k)+":"+canon(v[k])).join(",")+"}":Array.isArray(v)?"["+v.map(canon).join(",")+"]":JSON.stringify(v); const digest=(v,k)=>{const x=structuredClone(v);delete x[k];return "sha256:"+crypto.createHash("sha256").update(canon(x)).digest("hex")};
const c=read("tests/fixtures/autonomy-contract/constitution.json"); assert.equal(c.constitution_digest,digest(c,"constitution_digest")); for(const lane of ["credentials-and-auth","deployments-and-code","privacy-retention-and-erasure","firmware-and-remote-recovery","constitution-and-safety-gates"])assert.ok(c.protected_lanes.includes(lane)); assert.deepEqual([...c.autonomous_classes].sort(),["no-reboot-security-bugfix-maintenance","routing"]);
const r=read("docs/autonomy-coverage-registry-v1.json"); assert.equal(r.state,"disarmed");assert.equal(r.registry_digest,digest(r,"registry_digest")); const states=new Set(["out-of-scope","protected","shadow","armed-canary","armed-fleet"]);for(const d of r.domains){assert.ok(states.has(d.coverage));if(d.coverage==="protected")assert.equal(d.recovery_class,"none")};assert.ok(r.domains.some(d=>d.level==="L4"));assert.ok(r.domains.some(d=>d.level==="L5"));
for(const n of ["autonomy-constitution-v1.schema.json","autonomous-mutation-journal-v1.schema.json"]){const s=read(`docs/${n}`);assert.equal(s.additionalProperties,false)}
for(const [n,recovery] of [["journal-r-exact.json","R-exact"],["journal-r-forward.json","R-forward"]]){const j=read(`tests/fixtures/autonomy-contract/${n}`);assert.equal(j[0].recovery.class,recovery);assert.equal(j[0].outcome==="unknown",recovery==="R-forward");assert.equal(j.at(-1).outcome,"disarmed");assert.ok(j.every(e=>e.recovery.disarms_after_action));}
console.log("autonomy-contract validation passed");
