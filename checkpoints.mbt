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
/// Measured coverage between two consecutive anchors. An unchecked segment
/// has count zero and no maximum residual. Lines include the table header.
pub(all) struct SegmentCheck {
  start_anchor_line : Int
  end_anchor_line : Int
  checkpoint_count : Int
  max_abs_residual_ms : Int64?
}

///|
priv struct CheckpointEvaluation {
  rows : Array[CheckpointResult]
  segments : Array[SegmentCheck]
}

///|
fn ClockModel::unchecked_segments(self : ClockModel) -> Array[SegmentCheck] {
  let segments = []
  for index = 1; index < self.anchors.length(); index = index + 1 {
    segments.push({
      start_anchor_line: self.anchors[index - 1].line,
      end_anchor_line: self.anchors[index].line,
      checkpoint_count: 0,
      max_abs_residual_ms: None,
    })
  }
  segments
}

///|
fn ClockModel::evaluate_points(
  self : ClockModel,
  points : ArrayView[ClockPoint],
  tolerance_ms~ : Int64,
) -> CheckpointEvaluation raise InputError {
  guard tolerance_ms >= 0L else { raise InvalidInput(NegativeTolerance, 0) }
  guard points.length() <= MAX_CLOCK_POINTS else {
    raise InvalidInput(RowLimit, 0)
  }
  let rows = []
  let segments = self.unchecked_segments()
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
      rows.push({ line: point.line, status: OutsideAnchors, residual_ms: None, })
      continue
    }
    let segment = self.segment_index(point.device_ms)
    guard point.device_ms != self.anchors[segment].device_ms &&
      point.device_ms != self.anchors[segment + 1].device_ms else {
      raise InvalidInput(CheckpointOnAnchor, point.line)
    }
    if !self.covers_reference(point.reference_ms) {
      rows.push({ line: point.line, status: OutsideAnchors, residual_ms: None, })
      continue
    }
    let residual = point.reference_ms - projected
    let magnitude = residual.abs()
    let summary = segments[segment]
    let previous_max = summary.max_abs_residual_ms.unwrap_or(0L)
    segments[segment] = {
      ..summary,
      checkpoint_count: summary.checkpoint_count + 1,
      max_abs_residual_ms: Some(
        if magnitude > previous_max {
          magnitude
        } else {
          previous_max
        },
      ),
    }
    rows.push({
      line: point.line,
      status: if magnitude <= tolerance_ms {
        WithinTolerance
      } else {
        ResidualTooHigh
      },
      residual_ms: Some(residual),
    })
  }
  { rows, segments, }
}

///|
/// Extra observations check the model without becoming calibration anchors.
/// The signed residual is observed reference time minus projected time. With
/// no observations, the returned result array is empty.
pub fn ClockModel::check_points(
  self : ClockModel,
  points : ArrayView[ClockPoint],
  tolerance_ms~ : Int64,
) -> Array[CheckpointResult] raise InputError {
  self.evaluate_points(points, tolerance_ms~).rows
}
