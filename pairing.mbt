///|
pub(all) struct TimestampPair {
  device_index : Int
  reference_index : Int
  delta_ms : Int64
}

///|
priv struct CandidateWindow {
  start : Int
  end : Int
}

///|
fn CandidateWindow::count(self : CandidateWindow) -> Int {
  self.end - self.start
}

///|
pub struct Pairing {
  priv pairs : Array[TimestampPair]
  priv device_windows : Array[CandidateWindow]
  priv reference_windows : Array[CandidateWindow]
}

///|
pub fn Pairing::pairs(self : Pairing) -> Array[TimestampPair] {
  self.pairs.copy()
}

///|
pub fn Pairing::device_candidate_counts(self : Pairing) -> Array[Int] {
  self.device_windows.map(window => window.count())
}

///|
pub fn Pairing::reference_candidate_counts(self : Pairing) -> Array[Int] {
  self.reference_windows.map(window => window.count())
}

///|
fn validate_times(times : ArrayView[Int64]) -> Unit raise InputError {
  guard times.length() <= MAX_RECORDS else { raise InvalidInput(RowLimit, 0) }
  let mut previous = 0L
  for time in times {
    guard time >= 0L else { raise InvalidInput(BadTime, 0) }
    guard time >= previous else { raise InvalidInput(TimeReversed, 0) }
    previous = time
  }
}

///|
fn candidate_windows(
  query : ArrayView[Int64],
  targets : ArrayView[Int64],
  tolerance_ms : Int64,
) -> Array[CandidateWindow] {
  let windows = []
  let mut start = 0
  let mut end = 0
  // Both time axes are sorted. Each cursor advances at most targets.length().
  for time in query {
    let lower = if tolerance_ms > time { 0L } else { time - tolerance_ms }
    let upper = if tolerance_ms > MAX_TIME_MS - time {
      MAX_TIME_MS
    } else {
      time + tolerance_ms
    }
    while start < targets.length() && targets[start] < lower {
      start += 1
    }
    end = if end < start { start } else { end }
    while end < targets.length() && targets[end] <= upper {
      end += 1
    }
    windows.push({ start, end, })
  }
  windows
}

///|
/// Match sorted nonnegative timestamps with an inclusive tolerance. A pair
/// must be the sole candidate of each endpoint. Indices are zero-based and
/// the delta is reference time minus device time.
pub fn pair_timestamps(
  device_times : ArrayView[Int64],
  reference_times : ArrayView[Int64],
  tolerance_ms~ : Int64,
) -> Pairing raise InputError {
  guard tolerance_ms >= 0L else { raise InvalidInput(NegativeTolerance, 0) }
  validate_times(device_times)
  validate_times(reference_times)
  let device_windows = candidate_windows(
    device_times, reference_times, tolerance_ms,
  )
  let reference_windows = candidate_windows(
    reference_times, device_times, tolerance_ms,
  )
  let pairs = []
  for index, window in device_windows {
    if window.count() == 1 && reference_windows[window.start].count() == 1 {
      pairs.push({
        device_index: index,
        reference_index: window.start,
        delta_ms: reference_times[window.start] - device_times[index],
      })
    }
  }
  { pairs, device_windows, reference_windows, }
}
