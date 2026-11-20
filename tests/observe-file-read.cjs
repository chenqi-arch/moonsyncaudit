// Used by the CLI acceptance script to measure real reads from one fixture.
const fs = require("node:fs");

const pathToTrace = process.env.MOONSYNC_TEST_TRACE_FILE;
const originalOpen = fs.openSync;
const originalRead = fs.readSync;
const originalClose = fs.closeSync;
let trackedHandle;
let opens = 0;
let closes = 0;
let consumed = 0;
let maxRequest = 0;

fs.openSync = function (path, ...rest) {
  const handle = originalOpen(path, ...rest);
  if (path === pathToTrace) {
    trackedHandle = handle;
    opens += 1;
  }
  return handle;
};

fs.readSync = function (handle, ...rest) {
  if (handle !== trackedHandle) return originalRead(handle, ...rest);
  const [buffer, offset, length, position] = rest;
  maxRequest = Math.max(maxRequest, length);
  // Shorten each read but keep its underlying file and current position.
  const count = originalRead(handle, buffer, offset, Math.min(length, 4093), position);
  consumed += count;
  return count;
};

fs.closeSync = function (handle) {
  originalClose(handle);
  if (handle === trackedHandle) {
    closes += 1;
    trackedHandle = undefined;
  }
};

process.on("exit", () => {
  fs.writeSync(2, "FILE_READ_TRACE " +
    JSON.stringify({ opens, closes, consumed, maxRequest }) + "\n");
});
