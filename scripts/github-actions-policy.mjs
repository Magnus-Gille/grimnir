#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const FULL_SHA = /^[0-9a-f]{40}$/i;
const RELEASE_TAG = /^v\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/;
const APPROVED_RUNTIMES = new Set(["node24", "composite", "docker", "reusable-workflow"]);

class EvidenceError extends Error {
  constructor(reason, message = "evidence unavailable", status = null) {
    super(message);
    this.name = "EvidenceError";
    this.reason = reason || "unknown";
    this.status = status;
  }
}

function encodePath(value) {
  return value.split("/").map(encodeURIComponent).join("/");
}

function classifyHttpFailure(status, message, headers = new Headers()) {
  const normalized = String(message || "").toLowerCase();
  if (
    status === 402 ||
    /\b(billing|payment|spending limit|included minutes|actions (?:is|are) disabled)\b/.test(normalized)
  ) {
    return "billing";
  }
  if (
    headers.get("x-ratelimit-remaining") === "0" ||
    /\b(rate limit|secondary rate)\b/.test(normalized)
  ) {
    return "rate-limit";
  }
  if (status === 401) return "authentication";
  if (status === 403) return "permission";
  if (status === 404) return "not-found";
  if (status >= 500) return "upstream";
  return "unknown";
}

function parseUsesEntries(content) {
  const entries = [];
  const lines = String(content).split(/\r?\n/);
  for (let index = 0; index < lines.length; index += 1) {
    const match = lines[index].match(/^\s*(?:-\s*)?uses\s*:\s*(.*?)\s*$/);
    if (!match) continue;

    const raw = match[1];
    let spec = "";
    let comment = "";
    const quoted = raw.match(/^(['"])(.*?)\1(?:\s+#\s*(.*))?$/);
    if (quoted) {
      spec = quoted[2];
      comment = quoted[3] || "";
    } else {
      const plain = raw.match(/^([^\s#]+)(?:\s+#\s*(.*))?$/);
      if (plain) {
        spec = plain[1];
        comment = plain[2] || "";
      }
    }

    entries.push({
      line: index + 1,
      spec,
      releaseTag: RELEASE_TAG.test(comment.trim()) ? comment.trim() : null,
    });
  }
  return entries;
}

function parseRemoteAction(spec) {
  const at = spec.lastIndexOf("@");
  if (at <= 0) return null;
  const actionPath = spec.slice(0, at);
  const ref = spec.slice(at + 1);
  const parts = actionPath.split("/");
  if (
    parts.length < 2 ||
    !parts[0] ||
    !parts[1] ||
    !/^[A-Za-z0-9_.-]+$/.test(parts[0]) ||
    !/^[A-Za-z0-9_.-]+$/.test(parts[1])
  ) {
    return null;
  }
  return {
    action: `${parts[0]}/${parts[1]}`.toLowerCase(),
    subpath: parts.slice(2).join("/"),
    ref,
  };
}

function parseRuntime(manifest) {
  const lines = String(manifest).split(/\r?\n/);
  let runsIndent = null;
  for (const line of lines) {
    if (/^\s*(?:#.*)?$/.test(line)) continue;
    const indent = line.match(/^\s*/)[0].length;
    if (runsIndent === null) {
      if (/^\s*runs\s*:\s*(?:#.*)?$/.test(line)) runsIndent = indent;
      continue;
    }
    if (indent <= runsIndent) break;
    const using = line.match(/^\s*using\s*:\s*(['"]?)([^'"\s#]+)\1\s*(?:#.*)?$/);
    if (using) return using[2].toLowerCase();
  }
  return null;
}

function normalizeLocalActionPath(spec) {
  if (!spec.startsWith("./")) return null;
  const normalized = path.posix.normalize(spec.slice(2));
  if (!normalized || normalized === "." || normalized === ".." || normalized.startsWith("../")) {
    return null;
  }
  return normalized.replace(/\/+$/, "");
}

function finding(base, category, code, message, evidenceReason = null) {
  const result = {
    owner_repo: base.owner_repo,
    repository: base.repository,
    category,
    code,
    severity: "error",
    workflow: base.workflow ?? null,
    line: base.line ?? null,
    action: base.action ?? null,
    message,
  };
  if (evidenceReason) result.evidence_reason = evidenceReason;
  return result;
}

function auditRuntime(base, runtime, findings) {
  if (!runtime || !APPROVED_RUNTIMES.has(runtime)) {
    if (runtime === "node20") {
      findings.push(
        finding(base, "policy", "action-runtime-node20", "The exact Action manifest uses the prohibited Node 20 runtime."),
      );
    } else {
      findings.push(
        finding(base, "policy", "action-runtime-unknown", "The exact Action manifest runtime is absent or not approved."),
      );
    }
  }
}

async function auditUse(client, repository, workflow, entry, findings) {
  const base = {
    owner_repo: repository.owner_repo,
    repository: repository.repository,
    workflow: workflow.path,
    line: entry.line,
    action: null,
  };

  if (entry.spec.startsWith("docker://")) {
    base.action = "docker";
    findings.push(
      finding(
        base,
        "policy",
        "floating-action-ref",
        "Container-image Action references cannot satisfy the required GitHub commit-pin provenance.",
      ),
    );
    return;
  }

  if (entry.spec.startsWith("./")) {
    const localPath = normalizeLocalActionPath(entry.spec);
    base.action = localPath ? `./${localPath}` : "<invalid-local-action>";
    if (!localPath) {
      findings.push(
        finding(base, "policy", "invalid-local-action", "The local Action path is not a safe repository-relative path."),
      );
      return;
    }
    try {
      const manifest = await client.readLocalManifest(repository, localPath);
      auditRuntime(base, parseRuntime(manifest), findings);
    } catch (error) {
      const reason = error instanceof EvidenceError ? error.reason : "unknown";
      findings.push(
        finding(
          base,
          "evidence",
          "local-action-manifest-unavailable",
          "The local Action manifest could not be verified at the audited repository snapshot.",
          reason,
        ),
      );
    }
    return;
  }

  const remote = parseRemoteAction(entry.spec);
  if (!remote) {
    base.action = "<dynamic-or-invalid>";
    findings.push(
      finding(base, "policy", "floating-action-ref", "The remote Action reference is dynamic, malformed, or not a full commit pin."),
    );
    return;
  }
  base.action = remote.action;

  if (!FULL_SHA.test(remote.ref)) {
    findings.push(
      finding(base, "policy", "floating-action-ref", "Third-party Actions must use a full 40-hex commit pin."),
    );
    return;
  }

  if (!entry.releaseTag) {
    findings.push(
      finding(
        base,
        "policy",
        "missing-release-provenance",
        "The immutable Action pin lacks a same-line machine-verifiable release tag.",
      ),
    );
  } else {
    try {
      const resolved = await client.resolveTag(remote.action, entry.releaseTag);
      if (resolved.toLowerCase() !== remote.ref.toLowerCase()) {
        findings.push(
          finding(
            base,
            "policy",
            "upstream-tag-sha-mismatch",
            "The recorded upstream release tag does not resolve to the pinned commit.",
          ),
        );
      }
    } catch (error) {
      const reason = error instanceof EvidenceError ? error.reason : "unknown";
      findings.push(
        finding(
          base,
          "evidence",
          "upstream-tag-unavailable",
          "The recorded upstream release tag could not be resolved; policy verification fails closed.",
          reason,
        ),
      );
    }
  }

  try {
    const definition = await client.readRemoteDefinition(remote.action, remote.ref, remote.subpath);
    const runtime = definition.kind === "reusable-workflow"
      ? "reusable-workflow"
      : parseRuntime(definition.content);
    auditRuntime(base, runtime, findings);
  } catch (error) {
    const reason = error instanceof EvidenceError ? error.reason : "unknown";
    findings.push(
      finding(
        base,
        "evidence",
        "action-manifest-unavailable",
        "The exact pinned Action manifest could not be verified; policy verification fails closed.",
        reason,
      ),
    );
  }
}

function sortFindings(findings) {
  return findings.sort((left, right) => {
    return left.repository.localeCompare(right.repository) ||
      String(left.workflow || "").localeCompare(String(right.workflow || "")) ||
      (left.line ?? 0) - (right.line ?? 0) ||
      left.code.localeCompare(right.code) ||
      String(left.action || "").localeCompare(String(right.action || ""));
  });
}

async function auditFleet(repositories, client) {
  const repoReports = [];
  const findings = [];

  for (const repository of [...repositories].sort((a, b) => a.repository.localeCompare(b.repository))) {
    let inventory;
    try {
      inventory = await client.listWorkflows(repository);
    } catch (error) {
      const reason = error instanceof EvidenceError ? error.reason : "unknown";
      findings.push(
        finding(
          repository,
          "evidence",
          "workflow-inventory-unavailable",
          "Workflow inventory could not be read; policy verification fails closed.",
          reason,
        ),
      );
      repoReports.push({
        owner_repo: repository.owner_repo,
        repository: repository.repository,
        workflow_count: 0,
        uses_count: 0,
        status: "evidence-unavailable",
      });
      continue;
    }

    let usesCount = 0;
    const workflows = [...inventory.workflows].sort((a, b) => a.path.localeCompare(b.path));
    for (const workflow of workflows) {
      const entries = parseUsesEntries(workflow.content);
      usesCount += entries.length;
      for (const entry of entries) {
        await auditUse(client, { ...repository, ...inventory }, workflow, entry, findings);
      }
    }

    repoReports.push({
      owner_repo: repository.owner_repo,
      repository: repository.repository,
      workflow_count: workflows.length,
      uses_count: usesCount,
      status: "audited",
    });
  }

  sortFindings(findings);
  return {
    schema_version: 1,
    repositories: repoReports,
    findings,
    summary: {
      repositories: repoReports.length,
      workflows: repoReports.reduce((total, repo) => total + repo.workflow_count, 0),
      uses: repoReports.reduce((total, repo) => total + repo.uses_count, 0),
      policy_errors: findings.filter((item) => item.category === "policy").length,
      evidence_errors: findings.filter((item) => item.category === "evidence").length,
    },
  };
}

class FixtureClient {
  constructor(data) {
    this.data = data;
    this.repositories = new Map(data.repositories.map((repo) => [repo.repository, repo]));
  }

  listRepositories() {
    return this.data.repositories.map((repo) => ({
      repository: repo.repository,
      owner_repo: repo.owner_repo || repo.repository,
      visibility: repo.visibility || "unknown",
    }));
  }

  async listWorkflows(repository) {
    const fixture = this.repositories.get(repository.repository);
    if (!fixture) throw new EvidenceError("not-found");
    if (fixture.inventory_error) throw new EvidenceError(fixture.inventory_error.reason);
    return {
      visibility: fixture.visibility || "unknown",
      snapshot_sha: fixture.snapshot_sha,
      workflows: fixture.workflows || [],
      fixture,
    };
  }

  async readLocalManifest(repository, localPath) {
    const fixture = this.repositories.get(repository.repository);
    const candidates = [`${localPath}/action.yml`, `${localPath}/action.yaml`];
    for (const candidate of candidates) {
      if (Object.hasOwn(fixture.local_manifests || {}, candidate)) {
        return fixture.local_manifests[candidate];
      }
    }
    throw new EvidenceError("not-found");
  }

  async resolveTag(action, tag) {
    const upstream = this.data.upstream[action];
    if (!upstream) throw new EvidenceError("not-found");
    if (upstream.tag_errors?.[tag]) throw new EvidenceError(upstream.tag_errors[tag].reason);
    if (!upstream.tags?.[tag]) throw new EvidenceError("not-found");
    return upstream.tags[tag];
  }

  async readRemoteDefinition(action, sha, subpath) {
    const upstream = this.data.upstream[action];
    if (!upstream) throw new EvidenceError("not-found");
    if (upstream.manifest_errors?.[sha]) {
      throw new EvidenceError(upstream.manifest_errors[sha].reason);
    }
    const content = upstream.manifests?.[sha];
    if (!content) throw new EvidenceError("not-found");
    if (subpath.startsWith(".github/workflows/")) {
      return { kind: "reusable-workflow", content };
    }
    return { kind: "action", content };
  }
}

class GitHubClient {
  constructor(token) {
    this.token = token;
  }

  async requestJson(apiPath) {
    let response;
    try {
      response = await fetch(`https://api.github.com${apiPath}`, {
        headers: {
          Accept: "application/vnd.github+json",
          Authorization: `Bearer ${this.token}`,
          "X-GitHub-Api-Version": "2022-11-28",
          "User-Agent": "grimnir-actions-policy",
        },
        signal: AbortSignal.timeout(15_000),
      });
    } catch (error) {
      throw new EvidenceError("transport", "GitHub transport failed");
    }
    if (!response.ok) {
      let message = "";
      try {
        const body = await response.json();
        message = body.message || "";
      } catch {
        message = "";
      }
      throw new EvidenceError(
        classifyHttpFailure(response.status, message, response.headers),
        "GitHub API evidence unavailable",
        response.status,
      );
    }
    return response.json();
  }

  async readContent(repository, contentPath, ref) {
    const body = await this.requestJson(
      `/repos/${repository}/contents/${encodePath(contentPath)}?ref=${encodeURIComponent(ref)}`,
    );
    if (!body || body.type !== "file" || body.encoding !== "base64" || typeof body.content !== "string") {
      throw new EvidenceError("unknown");
    }
    return Buffer.from(body.content.replace(/\s/g, ""), "base64").toString("utf8");
  }

  async listWorkflows(repository) {
    const metadata = await this.requestJson(`/repos/${repository.repository}`);
    const commit = await this.requestJson(
      `/repos/${repository.repository}/commits/${encodeURIComponent(metadata.default_branch)}`,
    );
    const tree = await this.requestJson(
      `/repos/${repository.repository}/git/trees/${encodeURIComponent(commit.sha)}?recursive=1`,
    );
    if (tree.truncated || !Array.isArray(tree.tree)) {
      throw new EvidenceError("unknown", "GitHub did not return a complete workflow tree");
    }
    const workflows = [];
    const content = [];
    for (const workflow of tree.tree) {
      if (
        workflow?.type !== "blob" ||
        typeof workflow.path !== "string" ||
        !workflow.path.startsWith(".github/workflows/") ||
        !/\.ya?ml$/i.test(workflow.path)
      ) continue;
      content.push({
        path: workflow.path,
        content: await this.readContent(repository.repository, workflow.path, commit.sha),
      });
    }
    return {
      visibility: metadata.private ? "private" : "public",
      snapshot_sha: commit.sha,
      workflows: content,
    };
  }

  async readLocalManifest(repository, localPath) {
    let lastError = null;
    for (const filename of ["action.yml", "action.yaml"]) {
      try {
        return await this.readContent(
          repository.repository,
          `${localPath}/${filename}`,
          repository.snapshot_sha,
        );
      } catch (error) {
        lastError = error;
        if (!(error instanceof EvidenceError) || error.reason !== "not-found") throw error;
      }
    }
    throw lastError || new EvidenceError("not-found");
  }

  async resolveTag(action, tag) {
    const tagRef = await this.requestJson(`/repos/${action}/git/ref/tags/${encodeURIComponent(tag)}`);
    let object = tagRef.object;
    for (let depth = 0; depth < 5 && object?.type === "tag"; depth += 1) {
      const annotated = await this.requestJson(`/repos/${action}/git/tags/${object.sha}`);
      object = annotated.object;
    }
    if (object?.type !== "commit" || !FULL_SHA.test(object.sha || "")) {
      throw new EvidenceError("unknown");
    }
    return object.sha;
  }

  async readRemoteDefinition(action, sha, subpath) {
    if (subpath.startsWith(".github/workflows/")) {
      return {
        kind: "reusable-workflow",
        content: await this.readContent(action, subpath, sha),
      };
    }
    const root = subpath ? `${subpath.replace(/\/+$/, "")}/` : "";
    let lastError = null;
    for (const filename of ["action.yml", "action.yaml"]) {
      try {
        return {
          kind: "action",
          content: await this.readContent(action, `${root}${filename}`, sha),
        };
      } catch (error) {
        lastError = error;
        if (!(error instanceof EvidenceError) || error.reason !== "not-found") throw error;
      }
    }
    throw lastError || new EvidenceError("not-found");
  }
}

async function loadRegisteredRepositories(registryPath) {
  const data = JSON.parse(await fs.readFile(registryPath, "utf8"));
  const authority = data.repository_authority;
  if (!authority || typeof authority.default_owner !== "string" || !Array.isArray(data.components)) {
    throw new Error("services.json lacks valid repository authority");
  }
  const overrides =
    authority.owner_overrides &&
    typeof authority.owner_overrides === "object" &&
    !Array.isArray(authority.owner_overrides)
      ? authority.owner_overrides
      : {};
  const rows = data.components.map((component) => ({
    repo: component.repo,
    checkout: component.repo,
  }));
  if (Array.isArray(authority.additional_repositories)) rows.push(...authority.additional_repositories);

  const seen = new Set();
  const repositories = [];
  for (const row of rows) {
    if (!row || typeof row.repo !== "string" || typeof row.checkout !== "string" || seen.has(row.checkout)) {
      continue;
    }
    seen.add(row.checkout);
    const owner = overrides[row.repo] || authority.default_owner;
    repositories.push({
      repository: `${owner}/${row.repo}`,
      owner_repo: `${owner}/${row.repo}`,
      visibility: "unknown",
    });
  }
  return repositories;
}

function renderText(report) {
  const lines = [
    "GitHub Actions fleet policy",
    `Repositories: ${report.summary.repositories}; workflows: ${report.summary.workflows}; uses: ${report.summary.uses}`,
    `Policy errors: ${report.summary.policy_errors}; evidence errors: ${report.summary.evidence_errors}`,
  ];
  for (const item of report.findings) {
    const location = item.workflow ? `${item.workflow}:${item.line}` : "<repository>";
    const reason = item.evidence_reason ? ` evidence=${item.evidence_reason}` : "";
    lines.push(
      `${item.owner_repo} | ${item.category} | ${item.code} | ${location} | ${item.action || "-"}${reason}`,
    );
  }
  return `${lines.join("\n")}\n`;
}

function usage() {
  return `Usage:
  scripts/github-actions-policy.mjs [--services-json PATH] [--format json|text]
  scripts/github-actions-policy.mjs --fixture PATH [--format json|text]

Read-only fleet audit. It emits inventory counts and owner-routed findings, never workflow content.
Exit 0 means policy and evidence are complete; exit 1 means policy or evidence findings; exit 2 is usage/configuration failure.
`;
}

function parseArgs(argv) {
  const options = {
    servicesJson: path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../services.json"),
    fixture: null,
    format: "text",
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--services-json") options.servicesJson = path.resolve(argv[++index] || "");
    else if (arg === "--fixture") options.fixture = path.resolve(argv[++index] || "");
    else if (arg === "--format") options.format = argv[++index] || "";
    else if (arg === "--help" || arg === "-h") options.help = true;
    else throw new Error(`unknown argument: ${arg}`);
  }
  if (!["json", "text"].includes(options.format)) throw new Error("format must be json or text");
  return options;
}

function githubToken() {
  const envToken = process.env.GH_TOKEN || process.env.GITHUB_TOKEN;
  if (envToken) return envToken;
  try {
    return execFileSync("gh", ["auth", "token", "--hostname", "github.com"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    throw new Error("GitHub authentication unavailable; set GH_TOKEN/GITHUB_TOKEN or run gh auth login");
  }
}

async function main() {
  let options;
  try {
    options = parseArgs(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${error.message}\n${usage()}`);
    process.exitCode = 2;
    return;
  }
  if (options.help) {
    process.stdout.write(usage());
    return;
  }

  let client;
  let repositories;
  try {
    if (options.fixture) {
      const fixture = JSON.parse(await fs.readFile(options.fixture, "utf8"));
      client = new FixtureClient(fixture);
      repositories = client.listRepositories();
    } else {
      repositories = await loadRegisteredRepositories(options.servicesJson);
      client = new GitHubClient(githubToken());
    }
    const report = await auditFleet(repositories, client);
    process.stdout.write(
      options.format === "json" ? `${JSON.stringify(report, null, 2)}\n` : renderText(report),
    );
    if (report.findings.length > 0) process.exitCode = 1;
  } catch (error) {
    process.stderr.write(`github-actions-policy: ${error.message}\n`);
    process.exitCode = 2;
  }
}

main();
