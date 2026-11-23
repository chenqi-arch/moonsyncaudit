import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readdirSync, rmdirSync, unlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const cli = resolve(root, process.argv[2] ?? "_build/js/debug/build/cmd/main/main.js");
const probe = join(root, "tests", "observe-file-read.cjs");
const scratch = mkdtempSync(join(tmpdir(), "moonsyncaudit-accept-"));
let checks = 0;

function run(name, args, expectedCode, traceFile) {
  const lead = traceFile ? ["--require", probe] : [];
  const env = traceFile ? { ...process.env, MOONSYNC_TEST_TRACE_FILE: traceFile } : process.env;
  const result = spawnSync(process.execPath, [...lead, cli, ...args], {
    cwd: root, encoding: "utf8", timeout: 15_000, maxBuffer: 8 * 1024 * 1024, env,
  });
  assert.ifError(result.error);
  assert.equal(result.status, expectedCode, name + "\n" + result.stdout + result.stderr);
  assert.doesNotMatch(result.stdout + result.stderr, /synthetic-private/, name);
  checks += 1;
  return result;
}

function args(scenario, tolerance, {
  reference = "reference.tsv", anchors = "anchors.tsv", checkpoints,
  device = "device.tsv", format = "json", strict = false,
} = {}) {
  const example = "examples/" + scenario + "/";
  const devicePath = resolve(root, device) === device ? device : example + device;
  return ["audit", devicePath, example + reference, example + anchors, "--tolerance-ms",
    String(tolerance), ...(checkpoints ? ["--checkpoints", example + checkpoints] : []),
    ...(strict ? ["--strict"] : []), "--format", format];
}

function jsonReport(name, argv, code) {
  const result = run(name, argv, code);
  assert.equal(result.stderr, "", name);
  const summary = JSON.parse(result.stdout);
  assert.equal(summary.schema, "moonsyncaudit.audit.v1");
  assert.equal(summary.status, code === 0 ? "PASS" : "REVIEW", name);
  assert.equal(summary.counts.device + summary.counts.reference,
    summary.pairs.length * 2 + summary.issues.length, name);
  return summary;
}

function checkError(name, argv, code, label) {
  const result = run(name, argv, 2);
  assert.equal(result.stdout, "", name);
  assert.match(result.stderr, new RegExp("ERROR input=" + label + " code=" + code + " line="), name);
  return result;
}

function fixture(name, bytes) {
  const location = join(scratch, name);
  writeFileSync(location, bytes);
  return location;
}

function measuredRead(name, path, code, consumed) {
  const result = run(name, args("bench", 2, { device: path }), 2, path);
  assert.equal(result.stdout, "");
  assert.match(result.stderr, new RegExp("code=" + code + " line="));
  const trace = /^FILE_READ_TRACE (.+)$/m.exec(result.stderr);
  assert.ok(trace, name);
  const read = JSON.parse(trace[1]);
  assert.equal(read.opens, 1);
  assert.equal(read.closes, 1);
  assert.equal(read.consumed, consumed);
  assert.ok(read.maxRequest > 0 && read.maxRequest <= 65_536);
}

function verifyLargeDataset() {
  const groupsPerSegment = 1250;
  const step = 10_000;
  const device = ["id\tt_ms"];
  const reference = ["id\tt_ms"];
  const pairs = [];
  const deviceIssues = [];
  const referenceIssues = [];

  for (let group = 0; group < groupsPerSegment * 2; group += 1) {
    const time = group * step;
    const line = group * 4 + 2;
    // Corrections grow by 2 ms per group, then shrink by 3 ms per group.
    // All events fall just after a group boundary. Rounding down in the
    // second segment therefore subtracts an extra millisecond.
    const shift = group < groupsPerSegment
      ? 40 + group * 2
      : 2540 - (group - groupsPerSegment) * 3 - 1;
    const delta = (group % 5) - 2;
    device.push(
      "synthetic-private-match-" + group + "\t" + (time + 10),
      "device-gap-" + group + "\t" + (time + 20),
      "duplicate-time-a-" + group + "\t" + (time + 40),
      "duplicate-time-b-" + group + "\t" + (time + 40),
    );
    reference.push(
      "reference-match-" + group + "\t" + (time + shift + 10 + delta),
      "reference-conflict-" + group + "\t" + (time + shift + 40),
      "reference-gap-a-" + group + "\t" + (time + shift + 60),
      "reference-gap-b-" + group + "\t" + (time + shift + 70),
    );
    // Each group is isolated from all others at the 2 ms tolerance.
    // It has one mutual match, one many-to-one conflict and three gaps.
    pairs.push({ device_line: line, reference_line: line, delta_ms: String(delta) });
    deviceIssues.push(
      { side: "device", line: line + 1, code: "NO_CANDIDATE", candidates: 0, peer_candidates: null },
      { side: "device", line: line + 2, code: "CANDIDATE_CONFLICT", candidates: 1, peer_candidates: 2 },
      { side: "device", line: line + 3, code: "CANDIDATE_CONFLICT", candidates: 1, peer_candidates: 2 },
    );
    referenceIssues.push(
      { side: "reference", line: line + 1, code: "CANDIDATE_CONFLICT", candidates: 2, peer_candidates: null },
      { side: "reference", line: line + 2, code: "NO_CANDIDATE", candidates: 0, peer_candidates: null },
      { side: "reference", line: line + 3, code: "NO_CANDIDATE", candidates: 0, peer_candidates: null },
    );
  }

  const argv = [
    "audit", fixture("large-device.tsv", device.join("\n")),
    fixture("large-reference.tsv", reference.join("\n")),
    fixture("large-anchors.tsv", "device_ms\treference_ms\n0\t40\n12500000\t12502540\n25000000\t24998790\n"),
    "--tolerance-ms", "2", "--strict",
    "--checkpoints", fixture("large-checkpoints.tsv", "device_ms\treference_ms\n5000\t5043\n12505000\t12507536\n"),
  ];
  const first = run("10,000 logs per side", [...argv, "--format", "json"], 1);
  assert.equal(first.stderr, "");
  const report = JSON.parse(first.stdout);
  assert.equal(report.status, "REVIEW");
  assert.deepEqual(report.counts, {
    device: 10_000, reference: 10_000, pairs: 2500, issues: 15_000,
  });
  assert.deepEqual(report.pairs, pairs);
  assert.deepEqual(report.issues, deviceIssues.concat(referenceIssues));
  assert.deepEqual(report.checkpoints, {
    status: "PASS",
    strict: true,
    rows: [
      { line: 2, code: "WITHIN_TOLERANCE", residual_ms: "2" },
      { line: 3, code: "WITHIN_TOLERANCE", residual_ms: "-2" },
    ],
    segments: [
      { start_anchor_line: 2, end_anchor_line: 3, checkpoint_count: 1, max_abs_residual_ms: "2" },
      { start_anchor_line: 3, end_anchor_line: 4, checkpoint_count: 1, max_abs_residual_ms: "2" },
    ],
  });
  const repeat = run("repeat large dataset", [...argv, "--format", "json"], 1);
  assert.equal(repeat.stderr, "");
  assert.equal(repeat.stdout, first.stdout);
  const index = run("large merge TSV", [...argv, "--format", "pairs-tsv"], 1);
  assert.equal(index.stderr, "");
  assert.deepEqual(index.stdout.trimEnd().split(/\r?\n/), [
    "device_line\treference_line\tdelta_ms",
    ...pairs.map(pair => [pair.device_line, pair.reference_line, pair.delta_ms].join("\t")),
  ]);
}

try {
  const inspectionArgs = args("inspection", 5, { checkpoints: "checkpoints.tsv" });
  const inspection = jsonReport("inspection drift correction", inspectionArgs, 0);
  assert.deepEqual(inspection.pairs, [
    { device_line: 2, reference_line: 2, delta_ms: "1" },
    { device_line: 3, reference_line: 3, delta_ms: "0" },
    { device_line: 4, reference_line: 4, delta_ms: "0" },
  ]);
  assert.equal(inspection.checkpoints.status, "PASS");
  assert.deepEqual(inspection.checkpoints.rows.map(row => row.residual_ms), ["0", "0"]);
  const strict = jsonReport("strict inspection passes with both segments checked",
    [...inspectionArgs, "--strict"], 0);
  assert.equal(strict.checkpoints.strict, true);
  assert.deepEqual(strict.checkpoints.segments, [
    { start_anchor_line: 2, end_anchor_line: 3, checkpoint_count: 1, max_abs_residual_ms: "0" },
    { start_anchor_line: 3, end_anchor_line: 4, checkpoint_count: 1, max_abs_residual_ms: "0" },
  ]);

  const partialPoints = fixture("one-segment.tsv", "device_ms\treference_ms\n750000\t750250\n");
  const partialArgs = [
    ...args("inspection", 5, { strict: true }), "--checkpoints", partialPoints,
  ];
  const partial = jsonReport("strict review preserves matches when one segment has no points",
    partialArgs, 1);
  assert.deepEqual(partial.pairs, inspection.pairs);
  assert.equal(partial.checkpoints.status, "REVIEW");
  assert.deepEqual(partial.checkpoints.segments[1], {
    start_anchor_line: 3, end_anchor_line: 4, checkpoint_count: 0, max_abs_residual_ms: null,
  });
  const noPoints = jsonReport("strict mode requires independent observations",
    args("inspection", 5, { strict: true }), 1);
  assert.deepEqual(noPoints.pairs, inspection.pairs);
  assert.ok(noPoints.checkpoints.segments.every(segment => segment.checkpoint_count === 0));

  const tsv = run("strict row index for merging", args("inspection", 5, {
    checkpoints: "checkpoints.tsv", strict: true, format: "pairs-tsv",
  }), 0);
  assert.equal(tsv.stderr, "");
  assert.equal(tsv.stdout.replaceAll("\r\n", "\n"),
    "device_line\treference_line\tdelta_ms\n2\t2\t1\n3\t3\t0\n4\t4\t0\n");
  const missing = jsonReport("inspection missing frame", args("inspection", 5, {
    reference: "reference-missing.tsv",
  }), 1);
  assert.deepEqual(missing.issues.map(row => [row.side, row.line, row.code]),
    [["device", 3, "NO_CANDIDATE"]]);
  const repeatA = run("JSON deterministic run one", inspectionArgs, 0).stdout;
  const repeatB = run("JSON deterministic run two", inspectionArgs, 0).stdout;
  assert.equal(repeatA, repeatB);

  const production = jsonReport("production unique records", args("production", 3), 0);
  assert.equal(production.counts.pairs, 3);
  const collision = jsonReport("production many to one", args("production", 3, {
    reference: "reference-conflict.tsv",
  }), 1);
  assert.equal(collision.counts.pairs, 1);
  assert.deepEqual(collision.issues.map(row => [row.side, row.line, row.code, row.candidates,
    row.peer_candidates]), [
    ["device", 2, "CANDIDATE_CONFLICT", 1, 2],
    ["device", 3, "CANDIDATE_CONFLICT", 1, 2],
    ["reference", 2, "CANDIDATE_CONFLICT", 2, null],
  ]);

  const bench = jsonReport("bench at the checkpoint limit", args("bench", 2, {
    checkpoints: "checkpoints.tsv",
  }), 0);
  assert.equal(bench.checkpoints.rows[0].residual_ms, "2");
  const benchOff = jsonReport("bench independent checkpoint failure", args("bench", 2, {
    checkpoints: "checkpoints-off.tsv", strict: true,
  }), 1);
  assert.equal(benchOff.pairs.length, 2);
  assert.deepEqual(benchOff.checkpoints.rows,
    [{ line: 2, code: "RESIDUAL_TOO_HIGH", residual_ms: "3" }]);
  checkError("bench reversed anchors", args("bench", 2, {
    anchors: "anchors-reversed.tsv",
  }), "ANCHOR_ORDER", "anchors");

  const bomInput = fixture("采集数据 with spaces.tsv", "\uFEFFid\tt_ms\r\n巡检🛤\t2000\r\nrecord\t8000");
  const bom = jsonReport("UTF-8 BOM, CRLF, path spaces and Unicode, no final newline",
    args("bench", 2, { device: bomInput }), 0);
  assert.equal(bom.pairs.length, 2);

  const malformed = fixture("invalid-utf8.tsv", Buffer.concat([
    Buffer.from("id\tt_ms\n"), Buffer.from([0xc0, 0xaf]), Buffer.from("\t2\n"),
  ]));
  checkError("reject malformed UTF-8", args("bench", 2, { device: malformed }),
    "INVALID_UTF8", "device");
  const privateRow = fixture("bad-row.tsv", "id\tt_ms\nsynthetic-private\twrong");
  checkError("source values absent from errors", args("bench", 2, { device: privateRow }),
    "BAD_TIME", "device");
  checkError("missing file", args("bench", 2, { device: join(scratch, "absent.tsv") }),
    "READ_FAILED", "device");
  checkError("directory refused", args("bench", 2, { device: scratch }),
    "READ_FAILED", "device");
  checkError("negative tolerance", args("bench", "-1"), "BAD_TOLERANCE", "tolerance-ms");

  const byteLimit = 8 * 1024 * 1024;
  const atLimit = fixture("exact-size.tsv", Buffer.alloc(byteLimit, 0x61));
  measuredRead("allow parsing at exact size", atLimit, "BAD_HEADER", byteLimit);
  const tooLarge = fixture("size-and-trailing-bytes.tsv", Buffer.alloc(byteLimit + 4096, 0xff));
  measuredRead("stop at byte limit plus one before UTF-8 decoding", tooLarge, "TABLE_LIMIT", byteLimit + 1);

  const usage = run("usage error", ["audit"], 2);
  assert.equal(usage.stdout, "");
  assert.match(usage.stderr, /ERROR code=USAGE/);
  const duplicateStrict = run("reject repeated strict option",
    args("inspection", 5, { strict: true }).concat("--strict"), 2);
  assert.match(duplicateStrict.stderr, /ERROR code=USAGE/);
  const human = run("text summary", args("inspection", 5, { format: "text" }), 0);
  assert.match(human.stdout, /^status=PASS device=3 reference=3 pairs=3 issues=0/);
  assert.match(human.stdout, /PAIR device_line=3 reference_line=3 delta_ms=0/);
  assert.match(human.stdout, /SEGMENT start_anchor_line=3 end_anchor_line=4 checkpoint_count=0/);
  verifyLargeDataset();
  console.log("CLI acceptance passed checks=" + checks +
    " scenarios=3 large_rows_per_side=10000 read_budget=8388609 short_reads=checked");
} finally {
  // The directory was allocated by mkdtemp and contains only our fixture files.
  for (const name of readdirSync(scratch)) unlinkSync(join(scratch, name));
  rmdirSync(scratch);
}
