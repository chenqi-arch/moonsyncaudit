///|
pub const MAX_SEGMENT_MS : Int64 = 86_400_000L

///|
/// A monotone piecewise-linear translation to the reference clock.
pub struct ClockModel {
  priv anchors : Array[ClockPoint]
}

///|
/// Each adjacent anchor pair must move forward on both clocks and be at most
/// 24 hours apart on either side.
pub fn ClockModel::new(
  anchors : ArrayView[ClockPoint],
) -> ClockModel raise InputError {
  guard anchors.length() >= 2 else { raise InvalidInput(AnchorsMissing, 0) }
  guard anchors.length() <= MAX_CLOCK_POINTS else {
    raise InvalidInput(RowLimit, 0)
  }
  for index, point in anchors {
    guard point.line > 0 else { raise InvalidInput(BadRow, 0) }
    guard point.device_ms >= 0L && point.reference_ms >= 0L else {
      raise InvalidInput(BadTime, point.line)
    }
    if index == 0 {
      continue
    }
    let previous = anchors[index - 1]
    guard point.line > previous.line else {
      raise InvalidInput(BadRow, point.line)
    }
    guard point.device_ms > previous.device_ms &&
      point.reference_ms > previous.reference_ms else {
      raise InvalidInput(AnchorOrder, point.line)
    }
    guard point.device_ms - previous.device_ms <= MAX_SEGMENT_MS &&
      point.reference_ms - previous.reference_ms <= MAX_SEGMENT_MS else {
      raise InvalidInput(SegmentTooLong, point.line)
    }
  }
  { anchors: anchors.to_owned(), }
}

///|
fn ClockModel::segment_index(self : ClockModel, device_ms : Int64) -> Int {
  let mut start = 0
  let mut end = self.anchors.length() - 1
  while end - start > 1 {
    let mid = start + (end - start) / 2
    if self.anchors[mid].device_ms <= device_ms {
      start = mid
    } else {
      end = mid
    }
  }
  start
}

///|
/// A timestamp outside the supplied anchor interval has no calibration.
/// Integer division rounds the interpolated reference millisecond down.
pub fn ClockModel::project(self : ClockModel, device_ms : Int64) -> Int64? {
  if device_ms < self.anchors[0].device_ms ||
    device_ms > self.anchors[self.anchors.length() - 1].device_ms {
    return None
  }
  let index = self.segment_index(device_ms)
  let left = self.anchors[index]
  let right = self.anchors[index + 1]
  let offset = device_ms - left.device_ms
  let device_span = right.device_ms - left.device_ms
  let reference_span = right.reference_ms - left.reference_ms
  // Product is <= 86400000^2; projection is between the reference anchors.
  Some(left.reference_ms + offset * reference_span / device_span)
}

///|
pub fn ClockModel::covers_reference(
  self : ClockModel,
  reference_ms : Int64,
) -> Bool {
  reference_ms >= self.anchors[0].reference_ms &&
  reference_ms <= self.anchors[self.anchors.length() - 1].reference_ms
}
