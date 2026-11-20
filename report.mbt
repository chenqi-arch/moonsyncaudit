///|
fn AuditReport::status(self : AuditReport) -> String {
  if self.passed() {
    "PASS"
  } else {
    "REVIEW"
  }
}

///|
fn AuditReport::checkpoint_status(self : AuditReport) -> String {
  if self.checks.is_empty() {
    "NOT_PROVIDED"
  } else if self.checks.all(check => check.status == WithinTolerance) {
    "PASS"
  } else {
    "REVIEW"
  }
}

///|
fn optional_count(value : Int?) -> Json {
  match value {
    Some(n) => @json.to_json(n)
    None => Json::null()
  }
}

///|
fn optional_delta(value : Int64?) -> Json {
  match value {
    Some(n) => Json::string(n.to_string())
    None => Json::null()
  }
}

///|
/// Stable report for automation. Int64 deltas are decimal strings so JSON
/// consumers (including JavaScript) retain every digit.
pub fn AuditReport::to_json(self : AuditReport) -> Json {
  let pairs : Array[Json] = self.pairs.map(pair => {
    "device_line": @json.to_json(pair.device_line),
    "reference_line": @json.to_json(pair.reference_line),
    "delta_ms": Json::string(pair.delta_ms.to_string()),
  })
  let issues : Array[Json] = self.issues.map(issue => {
    "side": Json::string(issue.side.tag()),
    "line": @json.to_json(issue.line),
    "code": Json::string(issue.kind.tag()),
    "candidates": optional_count(issue.candidates),
    "peer_candidates": optional_count(issue.peer_candidates),
  })
  let checkpoint_rows : Array[Json] = self.checks.map(check => {
    "line": @json.to_json(check.line),
    "code": Json::string(check.status.tag()),
    "residual_ms": optional_delta(check.residual_ms),
  })
  {
    "schema": "moonsyncaudit.audit.v1",
    "status": Json::string(self.status()),
    "counts": {
      "device": @json.to_json(self.device_count),
      "reference": @json.to_json(self.reference_count),
      "pairs": @json.to_json(self.pairs.length()),
      "issues": @json.to_json(self.issues.length()),
    },
    "pairs": Json::array(pairs),
    "issues": Json::array(issues),
    "checkpoints": {
      "status": Json::string(self.checkpoint_status()),
      "rows": Json::array(checkpoint_rows),
    },
  }
}

///|
/// Row-based text suitable for reviewing a report next to the input tables.
pub fn AuditReport::to_text(self : AuditReport) -> String {
  let out = StringBuilder()
  out.write_string(
    "status=\{self.status()} device=\{self.device_count} reference=\{self.reference_count} pairs=\{self.pairs.length()} issues=\{self.issues.length()} checkpoints=\{self.checkpoint_status()}",
  )
  for pair in self.pairs {
    out.write_string(
      "\nPAIR device_line=\{pair.device_line} reference_line=\{pair.reference_line} delta_ms=\{pair.delta_ms}",
    )
  }
  for issue in self.issues {
    out.write_string(
      "\nISSUE side=\{issue.side.tag()} line=\{issue.line} code=\{issue.kind.tag()}",
    )
    if issue.candidates is Some(count) {
      out.write_string(" candidates=\{count}")
    }
    if issue.peer_candidates is Some(count) {
      out.write_string(" peer_candidates=\{count}")
    }
  }
  for check in self.checks {
    out.write_string(
      "\nCHECKPOINT line=\{check.line} code=\{check.status.tag()}",
    )
    if check.residual_ms is Some(delta) {
      out.write_string(" residual_ms=\{delta}")
    }
  }
  out.to_string()
}
