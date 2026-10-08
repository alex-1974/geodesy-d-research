#!/usr/bin/env python3
from __future__ import annotations
import os
import statistics
import subprocess
import sys

def run(binary: str, mode: str, f: str, rounds: str, runs: int):
    values=[]
    checks=[]
    for _ in range(runs):
        command=[binary,mode,f,rounds]
        cpu=os.environ.get("R69_5_CPU")
        if cpu:
            command=["taskset","-c",cpu,*command]
        p=subprocess.run(command,check=True,text=True,capture_output=True)
        data=dict(line.split("=",1) for line in p.stdout.splitlines() if "=" in line)
        values.append(float(data["ns_per_op"]))
        checks.append(float(data["checksum"]))
    return statistics.median(values), checks

if len(sys.argv)!=7:
    raise SystemExit("usage: summarize.py BINARY MODE F ROUNDS RUNS LABEL")

binary,mode,f,rounds,runs,label=sys.argv[1:]
median,checks=run(binary,mode,f,rounds,int(runs))
print(f"{label} mode={mode} f={f} median_ns={median:.6f} checksum={checks[0]:.12f}")
if max(checks)-min(checks) != 0:
    raise SystemExit(f"unstable checksum for {label} {mode} {f}")
