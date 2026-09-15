#!/usr/bin/env python3
"""Emit topology.json for the public snapshot (cloud layer).

Runs against the ALREADY-SANITIZED tree (sanitize-public.sh calls this after
every substitution, before the verification gate), so everything it can read
is already fictional — and the gate re-scans its output like any other file.

Extraction is line-regex over live/*.tf, not HCL parsing: the three resource
families the architecture view needs (the EC2 instance, Lambda functions,
S3 buckets) all declare their identifying attribute as a literal on one
line. Fail-closed: anything other than exactly one aws_instance, or zero
lambdas/buckets, kills the run — those shapes changing means this parser
and the contract need to change with them.

Contract: labodeludo.dev scripts/topology/README.md (topologyVersion 1).
"""
import glob
import json
import os
import re
import sys

def die(msg):
    print(f"emit-topology: {msg}", file=sys.stderr)
    sys.exit(1)

if len(sys.argv) != 2:
    die("usage: emit-topology.py <sanitized-tree>")
ROOT = sys.argv[1]

tf_files = sorted(glob.glob(os.path.join(ROOT, "live", "*.tf")))
if not tf_files:
    die("no live/*.tf found")

# resource blocks, with the file and the raw text up to the next resource —
# good enough to pull one-line literal attributes out of
blocks = []
for path in tf_files:
    rel = os.path.relpath(path, ROOT)
    text = open(path, encoding="utf-8").read()
    starts = [(m.start(), m.group(1), m.group(2))
              for m in re.finditer(r'^resource\s+"([\w]+)"\s+"([\w-]+)"',
                                   text, re.M)]
    for i, (pos, rtype, rname) in enumerate(starts):
        end = starts[i + 1][0] if i + 1 < len(starts) else len(text)
        blocks.append((rel, rtype, rname, text[pos:end]))

def attr(body, name):
    m = re.search(rf'^\s*{name}\s*=\s*"([^"]+)"', body, re.M)
    return m.group(1) if m else None

nodes, edges = [], []

instances = [(f, n, b) for f, t, n, b in blocks if t == "aws_instance"]
if len(instances) != 1:
    die(f"expected exactly one aws_instance, found {len(instances)} — "
        "update the emitter and the topology contract together")
f, n, body = instances[0]
nodes.append({"id": f"instance:{n}", "kind": "instance", "label": n,
              "layer": "cloud", "source": f,
              "meta": {"instanceType": attr(body, "instance_type"),
                       "availabilityZone": attr(body, "availability_zone")}})
# the one instance IS the cluster's cloud node (nixos-iac hosts/cloud-01);
# a second instance would have failed above, forcing this link to be rethought
edges.append({"from": f"instance:{n}", "to": "host:cloud-01", "kind": "is"})

for f, t, n, body in blocks:
    if t == "aws_lambda_function":
        fn = attr(body, "function_name")
        if not fn:
            continue  # aws_lambda_permission-style references, not literals
        nodes.append({"id": f"lambda:{fn}", "kind": "lambda", "label": fn,
                      "layer": "cloud", "source": f,
                      "meta": {"runtime": attr(body, "runtime")}})
    elif t == "aws_s3_bucket":
        bucket = attr(body, "bucket")
        if not bucket:
            die(f"{f}: aws_s3_bucket.{n} has no literal bucket name")
        nodes.append({"id": f"bucket:{bucket}", "kind": "bucket",
                      "label": bucket, "layer": "cloud", "source": f,
                      "meta": {}})

n_lambda = sum(1 for x in nodes if x["kind"] == "lambda")
n_bucket = sum(1 for x in nodes if x["kind"] == "bucket")
if n_lambda == 0 or n_bucket == 0:
    die(f"extracted {n_lambda} lambdas / {n_bucket} buckets — parser broken")

out = {"topologyVersion": 1, "repo": "aws-iac-public", "layer": "cloud",
       "nodes": nodes, "edges": edges}
with open(os.path.join(ROOT, "topology.json"), "w", encoding="utf-8") as fh:
    json.dump(out, fh, indent=2, sort_keys=True)
    fh.write("\n")
print(f"emit-topology: {len(nodes)} nodes (1 instance, {n_lambda} lambdas, "
      f"{n_bucket} buckets), {len(edges)} edges")
