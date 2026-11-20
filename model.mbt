///|
pub(all) struct Record {
  id : String
  time_ms : Int64
  line : Int
}

///|
pub(all) struct ClockPoint {
  device_ms : Int64
  reference_ms : Int64
  line : Int
}

///|
pub(all) enum InputCode {
  BadHeader
  // All line numbers refer to the input table including its header. Line 0
  // indicates an error that applies to the table or option as a whole.
  BadRow
  BadId
  DuplicateId
  BadTime
  TimeReversed
  TableLimit
  RowLimit
} derive(Eq, @debug.Debug)

///|
pub extend InputCode with Eq::{equal, not_equal}

///|
pub extend InputCode with @debug.Debug::{to_repr}

///|
pub fn InputCode::tag(self : InputCode) -> String {
  match self {
    BadHeader => "BAD_HEADER"
    BadRow => "BAD_ROW"
    BadId => "BAD_ID"
    DuplicateId => "DUPLICATE_ID"
    BadTime => "BAD_TIME"
    TimeReversed => "TIME_REVERSED"
    TableLimit => "TABLE_LIMIT"
    RowLimit => "ROW_LIMIT"
  }
}

///|
pub suberror InputError {
  InvalidInput(InputCode, Int)
} derive(@debug.Debug)

///|
pub extend InputError with @debug.Debug::{to_repr}

///|
pub fn InputError::code(self : InputError) -> InputCode {
  let InvalidInput(code, _) = self
  code
}

///|
pub fn InputError::line(self : InputError) -> Int {
  let InvalidInput(_, line) = self
  line
}

///|
pub const TABLE_LIMIT_BYTES : Int = 8_388_608

///|
pub const MAX_RECORDS : Int = 100_000

///|
pub const MAX_CLOCK_POINTS : Int = 10_000

///|
pub const MAX_TIME_MS : Int64 = 9_223_372_036_854_775_807L

///|
/// Parse a nonnegative decimal millisecond timestamp without float conversion.
pub fn parse_timestamp_ms(
  text : StringView,
  line? : Int = 0,
) -> Int64 raise InputError {
  guard text.length() > 0 && text.length() <= 19 else {
    raise InvalidInput(BadTime, line)
  }
  let mut value = 0L
  for ch in text {
    let digit = (ch.to_int() - '0'.to_int()).to_int64()
    guard digit >= 0L && digit <= 9L && value <= (MAX_TIME_MS - digit) / 10L else {
      raise InvalidInput(BadTime, line)
    }
    value = value * 10L + digit
  }
  value
}
