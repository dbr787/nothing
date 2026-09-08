#!/usr/bin/env python3
"""Cross-platform Buildkite Cache benchmark.

One implementation for Linux, macOS and Windows so the numbers are comparable.
Generates a fixture of a given shape and size, times `cache save`, deletes the
target, times `cache restore`, and verifies the tree came back intact.

Shapes:
  blob  few large incompressible files   - raw transfer throughput
  many  thousands of tiny files          - per-file and per-entry overhead
  text  highly compressible text         - compression throughput and ratio

Emits human-readable RESULT lines plus one BENCHJSON line for aggregation.
"""
import json
import os
import platform
import shutil
import subprocess
import sys
import time

SHAPES = {
    # shape: {size: (file_count, file_bytes)}
    "blob": {"s": (50, 1 << 20), "m": (200, 1 << 20), "l": (500, 1 << 20)},
    "many": {"s": (1000, 4096), "m": (5000, 4096), "l": (20000, 4096)},
    "text": {"s": (50, 1 << 20), "m": (200, 1 << 20), "l": (500, 1 << 20)},
}

TEXT_UNIT = (b"the quick brown fox jumps over the lazy dog 0123456789\n" * 32)


def log(msg):
    print(msg, flush=True)


def result(test, status, detail):
    log("RESULT: %s | %s | %s" % (test, status, detail))


def build_fixture(path, shape, count, size):
    if os.path.exists(path):
        shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path, exist_ok=True)
    start = time.time()
    if shape == "text":
        reps = (size // len(TEXT_UNIT)) + 1
        payload = TEXT_UNIT * reps
        payload = payload[:size]
    else:
        payload = bytearray(os.urandom(size))
    total = 0
    # Nest so the tree is not one flat directory, which flatters some archivers.
    for i in range(count):
        sub = os.path.join(path, "d%02d" % (i % 32))
        if i % 32 == 0 or not os.path.isdir(sub):
            os.makedirs(sub, exist_ok=True)
        if shape != "text":
            # Vary each file so nothing dedupes across entries.
            payload[0:8] = i.to_bytes(8, "little")
        fp = os.path.join(sub, "f%06d.bin" % i)
        with open(fp, "wb") as fh:
            fh.write(payload)
        total += size
    return total, time.time() - start


def tree_stats(path):
    files = 0
    total = 0
    for root, _dirs, names in os.walk(path):
        for n in names:
            files += 1
            total += os.path.getsize(os.path.join(root, n))
    return files, total


def cache_cmd(action, name, config):
    cmd = ["buildkite-agent", "cache", action, "--cache-config-file", config, "--name", name]
    log("> " + " ".join(cmd))
    start = time.time()
    proc = subprocess.run(cmd, capture_output=True, text=True)
    elapsed = time.time() - start
    for line in (proc.stdout + proc.stderr).splitlines():
        log("  " + line)
    log("  exit %d in %.2fs" % (proc.returncode, elapsed))
    return proc.returncode, elapsed


def main():
    shape = os.environ.get("BENCH_SHAPE", "blob")
    size = os.environ.get("BENCH_SIZE", "s")
    config = os.path.join(".buildkite", "cache-bench.yml")
    if shape not in SHAPES or size not in SHAPES[shape]:
        log("unknown shape/size %s/%s" % (shape, size))
        return 1

    count, fbytes = SHAPES[shape][size]
    name = "bench_%s_%s" % (shape, size)
    target = "bk-bench-%s-%s" % (shape, size)
    osname = platform.system().lower()
    arch = platform.machine().lower()

    log("--- %s on %s/%s: %d files x %d bytes" % (name, osname, arch, count, fbytes))
    nominal, gen_s = build_fixture(target, shape, count, fbytes)
    files, disk = tree_stats(target)
    log("fixture: %d files, %.1f MB on disk, generated in %.1fs" % (files, disk / 1e6, gen_s))

    save_code, save_s = cache_cmd("save", name, config)
    if save_code != 0:
        result("%s.save" % name, "FAIL", "exit %d" % save_code)
        log("BENCHJSON: " + json.dumps({"os": osname, "arch": arch, "shape": shape,
                                        "size": size, "error": "save exit %d" % save_code}))
        return 1

    shutil.rmtree(target, ignore_errors=True)
    restore_code, restore_s = cache_cmd("restore", name, config)
    if restore_code != 0:
        result("%s.restore" % name, "FAIL", "exit %d" % restore_code)
        log("BENCHJSON: " + json.dumps({"os": osname, "arch": arch, "shape": shape,
                                        "size": size, "error": "restore exit %d" % restore_code}))
        return 1

    rfiles, rdisk = tree_stats(target)
    intact = (rfiles == files and rdisk == disk)
    result("%s.integrity" % name, "PASS" if intact else "FAIL",
           "%d/%d files, %d/%d bytes" % (rfiles, files, rdisk, disk))

    mb = disk / 1e6
    row = {
        "os": osname, "arch": arch, "shape": shape, "size": size,
        "files": files, "mb": round(mb, 1),
        "save_s": round(save_s, 2), "restore_s": round(restore_s, 2),
        "save_mbps": round(mb / max(save_s, 0.01), 1),
        "restore_mbps": round(mb / max(restore_s, 0.01), 1),
        "save_fps": round(files / max(save_s, 0.01)),
        "restore_fps": round(files / max(restore_s, 0.01)),
        "intact": intact,
        "queue": os.environ.get("BUILDKITE_AGENT_META_DATA_QUEUE", ""),
    }
    result("%s.save" % name, "PASS", "%.1f MB in %.2fs = %.1f MB/s" % (mb, save_s, row["save_mbps"]))
    result("%s.restore" % name, "PASS", "%.1f MB in %.2fs = %.1f MB/s" % (mb, restore_s, row["restore_mbps"]))
    log("BENCHJSON: " + json.dumps(row))
    return 0 if intact else 1


if __name__ == "__main__":
    sys.exit(main())
