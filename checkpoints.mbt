///|
pub(all) enum CheckpointStatus {
  WithinTolerance
  ResidualTooHigh
  OutsideAnchors
} derive(Eq, @debug.Debug)

///|
pub extend CheckpointStatus with Eq::{equal, not_equal}

///|
pub extend CheckpointStatus with @debug.Debug::{to_repr}

///|
pub fn CheckpointStatus::tag(self : CheckpointStatus) -> String {
  match self {
    WithinTolerance => "WITHIN_TOLERANCE"
    ResidualTooHigh => "RESIDUAL_TOO_HIGH"
    OutsideAnchors => "OUTSIDE_ANCHORS"
  }
}

///|
pub(all) struct CheckpointResult {
  line : Int
  status : CheckpointStatus
  residual_ms : Int64?
}

///|
/// Extra observations check the model without becoming calibration anchors.
/// The signed residual is observed reference time minus projected time.
pub fn ClockModel::check_points(
  self : ClockModel,
  points : ArrayView[ClockPoint],
  tolerance_ms~ : Int64,
) -> Array[CheckpointResult] raise InputError {
  guard tolerance_ms >= 0L else { raise InvalidInput(NegativeTolerance, 0) }
  guard points.length() > 0 else { raise InvalidInput(CheckpointsMissing, 0) }
  guard points.length() <= MAX_CLOCK_POINTS else {
    raise InvalidInput(RowLimit, 0)
  }
  let checks = []
  for index, point in points {
    guard point.line > 0 else { raise InvalidInput(BadRow, 0) }
    guard point.device_ms >= 0L && point.reference_ms >= 0L else {
      raise InvalidInput(BadTime, point.line)
    }
    if index > 0 {
      let previous = points[index - 1]
      guard point.line > previous.line else {
        raise InvalidInput(BadRow, point.line)
      }
      guard point.device_ms > previous.device_ms &&
        point.reference_ms > previous.reference_ms else {
        raise InvalidInput(CheckpointOrder, point.line)
      }
    }
    guard self.project(point.device_ms) is Some(projected) else {
      checks.push({
        line: point.line,
        status: OutsideAnchors,
        residual_ms: None,
      })
      continue
    }
    let segment = self.segment_index(point.device_ms)
    guard point.device_ms != self.anchors[segment].device_ms &&
      point.device_ms != self.anchors[segment + 1].device_ms else {
      raise InvalidInput(CheckpointOnAnchor, point.line)
    }
    if !self.covers_reference(point.reference_ms) {
      checks.push({
        line: point.line,
        status: OutsideAnchors,
        residual_ms: None,
      })
      continue
    }
    let residual = point.reference_ms - projected
    checks.push({
      line: point.line,
      status: if residual.abs() <= tolerance_ms {
        WithinTolerance
      } else {
        ResidualTooHigh
      },
      residual_ms: Some(residual),
    })
  }
  checks
}
