///|
pub(all) enum SourceSide {
  Device
  Reference
}

///|
pub fn SourceSide::tag(self : SourceSide) -> String {
  match self {
    Device => "device"
    Reference => "reference"
  }
}

///|
pub(all) enum IssueKind {
  OutsideCalibration
  NoCandidate
  CandidateConflict
}

///|
pub fn IssueKind::tag(self : IssueKind) -> String {
  match self {
    OutsideCalibration => "OUTSIDE_CALIBRATION"
    NoCandidate => "NO_CANDIDATE"
    CandidateConflict => "CANDIDATE_CONFLICT"
  }
}

///|
pub(all) struct RowIssue {
  side : SourceSide
  line : Int
  kind : IssueKind
  candidates : Int?
  peer_candidates : Int?
}

///|
pub(all) struct MatchedRows {
  device_line : Int
  reference_line : Int
  delta_ms : Int64
}

///|
pub struct AuditReport {
  priv device_count : Int
  priv reference_count : Int
  priv pairs : Array[MatchedRows]
  priv issues : Array[RowIssue]
  priv checks : Array[CheckpointResult]
  priv segments : Array[SegmentCheck]
  priv strict : Bool
}

///|
fn AuditReport::checkpoints_passed(self : AuditReport) -> Bool {
  self.checks.all(check => check.status == WithinTolerance) &&
  (!self.strict || self.segments.all(segment => segment.checkpoint_count > 0))
}

///|
pub fn AuditReport::passed(self : AuditReport) -> Bool {
  self.issues.is_empty() && self.checkpoints_passed()
}

///|
pub fn AuditReport::device_count(self : AuditReport) -> Int {
  self.device_count
}

///|
pub fn AuditReport::reference_count(self : AuditReport) -> Int {
  self.reference_count
}

///|
pub fn AuditReport::pairs(self : AuditReport) -> Array[MatchedRows] {
  self.pairs.copy()
}

///|
pub fn AuditReport::issues(self : AuditReport) -> Array[RowIssue] {
  self.issues.copy()
}

///|
pub fn AuditReport::checks(self : AuditReport) -> Array[CheckpointResult] {
  self.checks.copy()
}

///|
/// Coverage and maximum observed absolute error for each anchor interval.
pub fn AuditReport::segments(self : AuditReport) -> Array[SegmentCheck] {
  self.segments.copy()
}

///|
priv struct CoveredRows {
  lines : Array[Int]
  times : Array[Int64]
  issues : Array[RowIssue]
}

///|
fn covered_rows(
  rows : ArrayView[Record],
  side : SourceSide,
  project : (Int64) -> Int64?,
) -> CoveredRows {
  let result : CoveredRows = { lines: [], times: [], issues: [], }
  for row in rows {
    match project(row.time_ms) {
      Some(time) => {
        result.lines.push(row.line)
        result.times.push(time)
      }
      None =>
        result.issues.push({
          side,
          line: row.line,
          kind: OutsideCalibration,
          candidates: None,
          peer_candidates: None,
        })
    }
  }
  result
}

///|
fn finish_issues(
  rows : CoveredRows,
  side : SourceSide,
  own : Array[CandidateWindow],
  other : Array[CandidateWindow],
) -> Unit {
  for index, window in own {
    let count = window.count()
    let peer_candidates = if count == 1 {
      Some(other[window.start].count())
    } else {
      None
    }
    if peer_candidates == Some(1) {
      continue
    }
    rows.issues.push({
      side,
      line: rows.lines[index],
      kind: if count == 0 {
        NoCandidate
      } else {
        CandidateConflict
      },
      candidates: Some(count),
      peer_candidates,
    })
  }
  rows.issues.sort_by((a, b) => a.line.compare(b.line))
}

///|
/// Audit two sides and report each source row exactly once as paired or
/// requiring review. Check point failures leave row findings visible and
/// block the pass verdict. Strict mode also requires a measured independent
/// checkpoint in every anchor interval.
/// An omitted checkpoint tolerance uses the pairing tolerance. Omitted and
/// empty observations both leave the calibration intervals unchecked.
pub fn audit(
  clock : ClockModel,
  device : ArrayView[Record],
  reference : ArrayView[Record],
  tolerance_ms~ : Int64,
  checkpoints? : ArrayView[ClockPoint],
  checkpoint_tolerance_ms? : Int64,
  strict? : Bool = false,
) -> AuditReport raise InputError {
  let point_tolerance = checkpoint_tolerance_ms.unwrap_or(tolerance_ms)
  guard tolerance_ms >= 0L && point_tolerance >= 0L else {
    raise InvalidInput(NegativeTolerance, 0)
  }
  guard device.length() > 0 || reference.length() > 0 else {
    raise InvalidInput(NoRecords, 0)
  }
  validate_records(device)
  validate_records(reference)
  let evaluation = clock.evaluate_points(
    checkpoints.unwrap_or([]),
    tolerance_ms=point_tolerance,
  )
  let a = covered_rows(device, Device, t => clock.project(t))
  let b = covered_rows(reference, Reference, t => {
    if clock.covers_reference(t) {
      Some(t)
    } else {
      None
    }
  })
  let pairing = pair_timestamps(a.times[:], b.times[:], tolerance_ms~)
  finish_issues(a, Device, pairing.device_windows, pairing.reference_windows)
  finish_issues(b, Reference, pairing.reference_windows, pairing.device_windows)
  let pairs : Array[MatchedRows] = pairing.pairs.map(pair => {
    device_line: a.lines[pair.device_index],
    reference_line: b.lines[pair.reference_index],
    delta_ms: pair.delta_ms,
  })
  {
    device_count: device.length(),
    reference_count: reference.length(),
    pairs,
    issues: a.issues + b.issues,
    checks: evaluation.rows,
    segments: evaluation.segments,
    strict,
  }
}
