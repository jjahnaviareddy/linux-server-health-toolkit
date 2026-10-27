#!/usr/bin/env python3
"""Generate a standalone HTML page from a health report."""

import argparse
import html
from pathlib import Path


def inline(text):
    parts = text.split("**")
    if len(parts) % 2 == 0:
        return html.escape(text)
    return "".join(
        f"<strong>{html.escape(part)}</strong>"
        if i % 2 else html.escape(part)
        for i, part in enumerate(parts)
    )


def render(text):
    output = []
    table_open = False

    for line in text.splitlines():
        line = line.strip()

        if line.startswith("|") and line.endswith("|"):
            cells = [cell.strip() for cell in line[1:-1].split("|")]
            if all(cell and set(cell) <= set("-: ") for cell in cells):
                continue

            tag = "td"
            if not table_open:
                output.append('<div class="table-wrap"><table>')
                table_open = True
                tag = "th"

            output.append(
                "<tr>"
                + "".join(f"<{tag}>{inline(cell)}</{tag}>" for cell in cells)
                + "</tr>"
            )
            continue

        if table_open:
            output.append("</table></div>")
            table_open = False

        if not line:
            continue
        if line == "---":
            output.append("<hr>")
        elif line.startswith("## "):
            output.append(f"<h2>{inline(line[3:])}</h2>")
        elif line.startswith("# "):
            output.append(f"<h1>{inline(line[2:])}</h1>")
        elif line.startswith("- "):
            output.append(f'<p class="metric">{inline(line[2:])}</p>')
        else:
            output.append(f"<p>{inline(line)}</p>")

    if table_open:
        output.append("</table></div>")

    return "\n".join(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    args = parser.parse_args()

    content = render(args.report.read_text(encoding="utf-8"))
    target = args.report.with_suffix(".html")

    page = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Linux Server Health Report</title>
<style>
* { box-sizing: border-box; }
body {
    margin: 0; padding: 30px 16px;
    background: #eef2f7; color: #18243a;
    font: 16px/1.6 Arial, sans-serif;
}
main {
    max-width: 1050px; margin: auto; padding: 32px;
    background: white; border-radius: 16px;
    box-shadow: 0 8px 32px #14213d12;
}
h1 { margin-top: 0; color: #173d70; font-size: 28px; }
h2 {
    margin-top: 28px; padding-bottom: 8px;
    border-bottom: 2px solid #e5edf6;
}
.metric {
    background: #f4f8fc; padding: 12px 16px;
    border-left: 4px solid #2979b8;
}
.table-wrap { overflow-x: auto; }
table { width: 100%; border-collapse: collapse; margin: 16px 0; }
th { background: #173d70; color: white; text-align: left; }
th, td { padding: 12px; border-bottom: 1px solid #e4eaf2; }
tr:nth-child(even) { background: #f5f8fc; }
hr { border: 0; border-top: 1px solid #e4eaf2; }
@media (max-width: 600px) {
    main { padding: 16px; }
    h1 { font-size: 23px; }
}
</style>
</head>
<body><main>
"""
    page += content + "\n</main></body></html>\n"
    target.write_text(page, encoding="utf-8")
    print(f"HTML report written to: {target}")


if __name__ == "__main__":
    main()
