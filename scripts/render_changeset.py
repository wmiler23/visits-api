"""Render `aws cloudformation describe-change-set` JSON as a Markdown summary.

Usage: python scripts/render_changeset.py changeset.json [commit]
"""

import json
import sys

REPLACEMENT_LABEL = {"True": "**Yes**", "Conditional": "Maybe", "False": "No"}


def changed_properties(resource_change):
    names = []
    for detail in resource_change.get("Details", []):
        target = detail.get("Target", {})
        if target.get("Attribute") == "Properties" and target.get("Name"):
            names.append(target["Name"])
        elif target.get("Attribute") and target.get("Attribute") != "Properties":
            names.append(target["Attribute"])
    return sorted(set(names))


def render(change_set, commit=""):
    rows = [c["ResourceChange"] for c in change_set.get("Changes", []) if c.get("Type") == "Resource"]
    counts = {"Add": 0, "Modify": 0, "Remove": 0}
    replacements = 0
    lines = []
    for rc in rows:
        action = rc.get("Action", "?")
        counts[action] = counts.get(action, 0) + 1
        replacement = rc.get("Replacement", "")
        if replacement == "True":
            replacements += 1
        props = ", ".join(f"`{p}`" for p in changed_properties(rc)) or "-"
        lines.append(
            f"| {action} | `{rc.get('LogicalResourceId', '?')}` | {rc.get('ResourceType', '?')} "
            f"| {REPLACEMENT_LABEL.get(replacement, '-')} | {props} |"
        )

    if not rows:
        return "No resource changes.\n"

    summary = (
        f"**{len(rows)} resource change(s):** {counts['Add']} add, {counts['Modify']} modify, "
        f"{counts['Remove']} remove."
    )
    if replacements:
        summary += f" **{replacements} replacement(s): the resource is deleted and recreated.**"
    out = [
        summary,
        "",
        "| Action | Logical ID | Type | Replaced | Changed |",
        "| --- | --- | --- | --- | --- |",
        *lines,
        "",
    ]
    if commit:
        out.append(f"Previewed at commit `{commit}`.")
    out.append(
        "Code-only changes do not show here: the Lambda bundle is built after merge, "
        "so this preview compares infrastructure only."
    )
    return "\n".join(out) + "\n"


def main(argv):
    if len(argv) not in (2, 3):
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8") as fh:
        change_set = json.load(fh)
    sys.stdout.write(render(change_set, argv[2] if len(argv) == 3 else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
