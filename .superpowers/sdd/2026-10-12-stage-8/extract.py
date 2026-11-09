import re, sys
plan = open("docs/superpowers/plans/2026-10-12-stage-8.md", encoding="utf-8").read()
n = int(sys.argv[1]); idx = int(sys.argv[2]); out = sys.argv[3]
task = plan.split(f"### Task {n}:")[1].split(f"### Task {n+1}:")[0]
blocks = re.findall(r"```gdscript\n(.*?)```", task, re.S)
open(out, "w", encoding="utf-8", newline="\n").write(blocks[idx])
print(out, "<- block", idx, "of", len(blocks))
