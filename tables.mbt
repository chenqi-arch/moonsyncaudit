///|
/// Parse records from a UTF-8 table decoded to text. IDs are case-sensitive and
/// timestamps must be nondecreasing. Equal timestamps retain their row order.
pub fn parse_records(text : String) -> Array[Record] raise InputError {
  let records : Array[Record] = []
  let seen : Map[String, Unit] = Map([])
  let mut previous_ms = 0L
  read_tsv(text, "id\tt_ms", MAX_RECORDS, (id, time, line) => {
    let id = id.to_owned()
    guard valid_record_id(id) else { raise InvalidInput(BadId, line) }
    guard !seen.contains(id) else { raise InvalidInput(DuplicateId, line) }
    let time_ms = parse_timestamp_ms(time, line~)
    guard time_ms >= previous_ms else { raise InvalidInput(TimeReversed, line) }
    records.push({ id, time_ms, line, })
    seen[id] = ()
    previous_ms = time_ms
  })
  records
}

///|
/// Parse either calibration anchors or independent check points.
pub fn parse_clock_points(text : String) -> Array[ClockPoint] raise InputError {
  let points : Array[ClockPoint] = []
  read_tsv(text, "device_ms\treference_ms", MAX_CLOCK_POINTS, (
    device,
    reference,
    line,
  ) => {
    let device_ms = parse_timestamp_ms(device, line~)
    let reference_ms = parse_timestamp_ms(reference, line~)
    points.push({ device_ms, reference_ms, line, })
  })
  points
}

///|
fn valid_record_id(id : String) -> Bool {
  guard id.length() <= 128 && !id.trim().is_empty() else { return false }
  for ch in id {
    let c = ch.to_int()
    if c < 32 || c == 127 || c == 0xfeff {
      return false
    }
  }
  true
}

///|
fn read_tsv(
  text : String,
  header : String,
  max_rows : Int,
  on_row : (StringView, StringView, Int) -> Unit raise InputError,
) -> Unit raise InputError {
  guard text.length() <= TABLE_LIMIT_BYTES else {
    raise InvalidInput(TableLimit, 0)
  }
  let mut line = 0
  let mut offset = 0
  for raw in text.split("\n") {
    line += 1
    offset += raw.length()
    let ended_with_lf = offset < text.length()
    if ended_with_lf {
      offset += 1
    } else if raw.is_empty() && line > 1 {
      // A trailing newline ends the previous row.
      break
    }
    let row = if ended_with_lf && raw.has_suffix("\r") {
      raw[:raw.length() - 1]
    } else {
      raw
    }
    if line == 1 {
      let header_row = if row.has_prefix("\uFEFF") { row[1:] } else { row }
      guard header_row == header[:] else { raise InvalidInput(BadHeader, 1) }
      continue
    }
    guard line - 1 <= max_rows else { raise InvalidInput(RowLimit, line) }
    guard !row.contains("\r") else { raise InvalidInput(BadRow, line) }
    guard row.split_once("\t") is Some((first, second)) &&
      !second.contains("\t") else {
      raise InvalidInput(BadRow, line)
    }
    on_row(first, second, line)
  }
  guard line > 0 else { raise InvalidInput(BadHeader, 1) }
}
