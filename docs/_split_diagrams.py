"""Split diagramme_classes.mmd into domain files + flat version."""
from __future__ import annotations

import re
from pathlib import Path

docs = Path(r"e:\MEMOIRE\docs")
src = (docs / "diagramme_classes.mmd").read_text(encoding="utf-8")
lines = src.splitlines()

out_flat: list[str] = []
out_domains: dict[str, list[str]] = {}
relations: list[str] = []

i = 0
while i < len(lines):
    line = lines[i]
    m = re.match(r'\s*namespace "([^"]+)" \{', line)
    if m:
        ns_name = m.group(1)
        ns_lines: list[str] = []
        i += 1
        depth = 1
        while i < len(lines) and depth > 0:
            l2 = lines[i]
            depth += l2.count("{") - l2.count("}")
            if depth > 0:
                if l2.startswith("        "):
                    ns_lines.append(re.sub(r"^        ", "    ", l2))
                else:
                    ns_lines.append(l2)
            i += 1
        out_domains[ns_name] = ns_lines
        out_flat.extend(ns_lines)
        continue

    if "-->" in line or "<--" in line or "..>" in line or (
        "--" in line and not line.strip().startswith("direction")
    ):
        # keep genuine relations (contain class names around arrows)
        if re.search(r"[A-Za-z].*(-->|<--|..\>|--)", line):
            relations.append(line)
            out_flat.append(line)
        else:
            out_flat.append(line)
    else:
        out_flat.append(line)
    i += 1

(docs / "diagramme_classes_flat.mmd").write_text("\n".join(out_flat) + "\n", encoding="utf-8")
print("flat lines", len(out_flat), "relations", len(relations), "domains", len(out_domains))

slug = {
    "Referentiel national et territorial": "01_referentiel",
    "Acteurs et journalisation": "02_acteurs",
    "Pedagogie et enseignement": "03_pedagogie",
    "Cotation LMD": "04_cotation",
    "Evaluations quiz": "05_quiz",
    "Interactions sociales et chat": "06_social",
    "Remontee provinciale et nationale": "07_rapports",
}

for name, body in out_domains.items():
    classes = re.findall(r"class\s+(\w+)", "\n".join(body))
    class_set = set(classes)
    rels = []
    for r in relations:
        mentioned = set(re.findall(r"\b([A-Z][A-Za-z0-9_]*)\b", r))
        if mentioned & class_set:
            rels.append(r)
    content = ["classDiagram", "    direction TB", ""] + body + [""] + rels + [""]
    s = slug.get(name, re.sub(r"[^a-z0-9]+", "_", name.lower()))
    path = docs / f"diagramme_classes_{s}.mmd"
    path.write_text("\n".join(content), encoding="utf-8")
    print("wrote", path.name, "classes", len(classes), "rels", len(rels))

print("DONE")
