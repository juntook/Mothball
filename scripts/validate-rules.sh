#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Validates every rule in rules/tools/*.json against the JSON Schema plus
# semantic checks (unique ids, safety/kind sanity, verified rules carry a date).
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import json, re, sys, glob, os
from datetime import date

SCHEMA = json.load(open("rules/schema/rule.schema.json"))

def fail(msgs):
    for m in msgs:
        print(f"FAIL {m}")
    sys.exit(1)

# Minimal draft-07 validator covering the subset of features used by rule.schema.json.
def validate(instance, schema, path="$", root=None):
    if root is None:
        root = schema
    errs = []
    if "$ref" in schema:
        ref = schema["$ref"]
        assert ref.startswith("#/")
        node = root
        for part in ref[2:].split("/"):
            node = node[part]
        return validate(instance, node, path, root)
    t = schema.get("type")
    if t == "object":
        if not isinstance(instance, dict):
            return [f"{path}: expected object"]
        for req in schema.get("required", []):
            if req not in instance:
                errs.append(f"{path}: missing required '{req}'")
        props = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            for k in instance:
                if k not in props:
                    errs.append(f"{path}: unknown property '{k}'")
        if "minProperties" in schema and len(instance) < schema["minProperties"]:
            errs.append(f"{path}: needs at least {schema['minProperties']} properties")
        for k, sub in props.items():
            if k in instance:
                errs += validate(instance[k], sub, f"{path}.{k}", root)
    elif t == "array":
        if not isinstance(instance, list):
            return [f"{path}: expected array"]
        if "minItems" in schema and len(instance) < schema["minItems"]:
            errs.append(f"{path}: needs at least {schema['minItems']} items")
        if "items" in schema:
            for i, item in enumerate(instance):
                errs += validate(item, schema["items"], f"{path}[{i}]", root)
    elif t == "string":
        if not isinstance(instance, str):
            return [f"{path}: expected string"]
        if "minLength" in schema and len(instance) < schema["minLength"]:
            errs.append(f"{path}: shorter than {schema['minLength']}")
    elif t == "integer":
        if not isinstance(instance, int) or isinstance(instance, bool):
            return [f"{path}: expected integer"]
        if "const" in schema and instance != schema["const"]:
            errs.append(f"{path}: expected const {schema['const']}")
    if "pattern" in schema and isinstance(instance, str) and not re.search(schema["pattern"], instance):
        errs.append(f"{path}: does not match pattern {schema['pattern']}")
    if "enum" in schema and instance not in schema["enum"]:
        errs.append(f"{path}: '{instance}' not in {schema['enum']}")
    if "not" in schema and not validate(instance, schema["not"], path, root):
        errs.append(f"{path}: matches forbidden pattern")
    for sub in schema.get("allOf", []):
        if "if" in sub:
            if not validate(instance, {**sub["if"], "type": "object"}, path, root):
                errs += validate(instance, sub["then"], path, root)
        else:
            errs += validate(instance, sub, path, root)
    return errs

errors = []
seen_ids = {}
files = sorted(glob.glob("rules/tools/*.json"))
if not files:
    fail(["no rule files found"])

for f in files:
    try:
        rule = json.load(open(f))
    except json.JSONDecodeError as e:
        errors.append(f"{f}: invalid JSON — {e}")
        continue
    for e in validate(rule, SCHEMA):
        errors.append(f"{f}: {e}")
    rid = rule.get("id")
    if rid:
        if rid in seen_ids:
            errors.append(f"{f}: duplicate rule id '{rid}' (also in {seen_ids[rid]})")
        seen_ids[rid] = f
        expected = os.path.splitext(os.path.basename(f))[0]
        if rid != expected:
            errors.append(f"{f}: rule id '{rid}' must match filename '{expected}'")
    tids = [t.get("id") for t in rule.get("targets", [])]
    for tid in tids:
        if tids.count(tid) > 1:
            errors.append(f"{f}: duplicate target id '{tid}'")
    if rule.get("status") == "verified" and "verifiedOn" not in rule:
        errors.append(f"{f}: verified rules must set verifiedOn")
    for t in rule.get("targets", []):
        if t.get("kind") == "credential" and t.get("safety") != "protected":
            errors.append(f"{f}: target '{t.get('id')}' is a credential and must be protected")
        if t.get("kind") == "history" and t.get("safety") == "regenerable":
            errors.append(f"{f}: target '{t.get('id')}' is history and must not be regenerable")

# system-exclusions.json sanity
try:
    excl = json.load(open("rules/system-exclusions.json"))
    names = excl["excludedProcessNames"]
    assert isinstance(names, list) and all(isinstance(n, str) and n for n in names)
    if len(names) != len(set(names)):
        errors.append("rules/system-exclusions.json: duplicate entries")
except Exception as e:
    errors.append(f"rules/system-exclusions.json: {e}")

if errors:
    fail(errors)
print(f"OK — {len(files)} rule files valid, ids unique, semantics pass")
PY
