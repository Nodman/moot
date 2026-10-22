#!/usr/bin/env bash
# Renders a moot markdown page (verdict, spec, plan) to HTML in the shape of the design page.
#
#   render-page.sh <page.md> [--out <page.html>] [--eyebrow "Spec · PROJ-1 · v2"]
#
# What the renderer knows: the H1 is the title and the paragraph right after it is the lede; the
# TL;DR section becomes the top block; sections named Tests and plan sections named "PR n" are
# collapsed; Human override, Decisions, Lead-decided points, Open questions and Open points are
# framed. Markdown covered: headings to h3, paragraphs, lists with one level of nesting, tables,
# fenced code, blockquotes, rules, inline code, bold, italics, links, images. An image whose path
# is a local file (relative to the markdown) is embedded into the page, so the published page needs
# no other files. Prints the output path.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
need python3
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

in="${1:-}"; shift || true
[[ -n "$in" && -f "$in" ]] || die "usage: render-page.sh <page.md> [--out <page.html>] [--eyebrow <text>]"
out="${in%.md}.html"; eyebrow="moot · $(date +%Y-%m-%d)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    --eyebrow) eyebrow="$2"; shift 2 ;;
    *) die "unknown flag: $1" ;;
  esac
done

python3 - "$in" "$out" "$eyebrow" "$here/../templates/page.html" <<'PY'
import base64, html, mimetypes, os, re, sys

src, out, eyebrow, shell = sys.argv[1:5]
lines = open(src, encoding="utf-8").read().splitlines()
base = os.path.dirname(os.path.abspath(src))


LIMIT = 16 * 1024 * 1024   # what a published page may hold, embedded images included
embedded = []


def image(m):
    alt, path = m.group(1), html.unescape(m.group(2))
    local = path if os.path.isabs(path) else os.path.join(base, path)
    if os.path.isfile(local):
        mime = mimetypes.guess_type(local)[0] or "application/octet-stream"
        raw = open(local, "rb").read()
        embedded.append((local, len(raw)))
        path = f"data:{mime};base64,{base64.b64encode(raw).decode('ascii')}"
    return f'<img src="{path}" alt="{alt}">'

COLLAPSED = re.compile(r"^(tests\b|pr \d)", re.I)
FRAMED = re.compile(r"^(human override|decisions|lead-decided|open questions|open points|questions for the human)", re.I)


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-") or "section"


def inline(text):
    parts = re.split(r"(`[^`]*`)", html.escape(text, quote=False))
    res = []
    for part in parts:
        if len(part) >= 2 and part.startswith("`") and part.endswith("`"):
            res.append("<code>" + part[1:-1] + "</code>")
            continue
        part = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", part)
        part = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<em>\1</em>", part)
        part = re.sub(r"!\[([^\]]*)\]\(([^)\s]+)\)", image, part)
        part = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", r'<a href="\2">\1</a>', part)
        res.append(part)
    return "".join(res)


class Page:
    def __init__(self):
        self.title, self.lede, self.toc, self.out = "", "", [], []
        self.section_kind = None     # None | "tldr" | "frame" | "details" | "plain"
        self.h3_details = False
        self.seen_h2 = False

    def close_h3(self):
        if self.h3_details:
            self.out.append("</details>")
            self.h3_details = False

    def close_section(self):
        self.close_h3()
        if self.section_kind in ("tldr", "frame", "plain"):
            self.out.append("</section>")
        elif self.section_kind == "details":
            self.out.append("</details>")
        self.section_kind = None

    def heading(self, level, text):
        if level == 1:
            self.title = self.title or inline(text)
            return
        if level == 2:
            self.close_section()
            self.seen_h2 = True
            sid = slug(text)
            self.toc.append((sid, inline(text)))
            if text.lower().startswith("tl;dr"):
                self.section_kind = "tldr"
                self.out.append(f'<section class="tldr" id="{sid}"><h2>{inline(text)}</h2>')
            elif COLLAPSED.match(text):
                self.section_kind = "details"
                self.out.append(f'<details class="section" id="{sid}"><summary>{inline(text)}</summary>')
            elif FRAMED.match(text):
                self.section_kind = "frame"
                self.out.append(f'<section class="frame" id="{sid}"><h2>{inline(text)}</h2>')
            else:
                self.section_kind = "plain"
                self.out.append(f'<section id="{sid}"><h2>{inline(text)}</h2>')
            return
        self.close_h3()
        if COLLAPSED.match(text):
            self.h3_details = True
            self.out.append(f"<details><summary>{inline(text)}</summary>")
        else:
            self.out.append(f"<h3>{inline(text)}</h3>")

    def paragraph(self, text):
        if self.title and not self.seen_h2 and not self.lede:
            self.lede = f'  <p class="lede">{inline(text)}</p>'
            return
        self.out.append(f"<p>{inline(text)}</p>")

    def table(self, rows):
        cells = [[c.strip() for c in r.strip().strip("|").split("|")] for r in rows]
        if len(cells) > 1 and all(re.fullmatch(r":?-+:?", c or "-") for c in cells[1]):
            head, body = cells[0], cells[2:]
        else:
            head, body = None, cells
        h = ['<div class="tablewrap"><table>']
        if head:
            h.append("<thead><tr>" + "".join(f"<th>{inline(c)}</th>" for c in head) + "</tr></thead>")
        if body:
            h.append("<tbody>" + "".join("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>" for r in body) + "</tbody>")
        h.append("</table></div>")
        self.out.append("".join(h))

    def list(self, items):
        # items: (indent, ordered, text); one nesting level
        h, stack = [], []
        for indent, ordered, text in items:
            tag = "ol" if ordered else "ul"
            while stack and stack[-1][0] > indent:
                h.append(f"</li></{stack.pop()[1]}>")
            if not stack or stack[-1][0] < indent:
                h.append(f"<{tag}><li>{inline(text)}")
                stack.append((indent, tag))
            else:
                h.append(f"</li><li>{inline(text)}")
        while stack:
            h.append(f"</li></{stack.pop()[1]}>")
        self.out.append("".join(h))


page = Page()
i, n = 0, len(lines)
LIST_RE = re.compile(r"^(\s*)([-*]|\d+\.)\s+(.*)$")
while i < n:
    line = lines[i]
    if not line.strip():
        i += 1
        continue
    if line.startswith("```"):
        code = []
        i += 1
        while i < n and not lines[i].startswith("```"):
            code.append(lines[i]); i += 1
        i += 1
        page.out.append("<pre><code>" + html.escape("\n".join(code), quote=False) + "</code></pre>")
        continue
    m = re.match(r"^(#{1,3})\s+(.*?)\s*#*$", line)
    if m:
        page.heading(len(m.group(1)), m.group(2)); i += 1
        continue
    if re.fullmatch(r"\s*(-{3,}|\*{3,})\s*", line):
        page.out.append("<hr>"); i += 1
        continue
    if line.lstrip().startswith("|"):
        rows = []
        while i < n and lines[i].lstrip().startswith("|"):
            rows.append(lines[i]); i += 1
        page.table(rows)
        continue
    if LIST_RE.match(line):
        items = []
        while i < n and lines[i].strip():
            m = LIST_RE.match(lines[i])
            if m:
                items.append([len(m.group(1)), m.group(2)[0].isdigit(), m.group(3)])
            elif items:
                items[-1][2] += " " + lines[i].strip()
            else:
                break
            i += 1
        page.list(items)
        continue
    if line.startswith(">"):
        quote = []
        while i < n and lines[i].startswith(">"):
            quote.append(lines[i][1:].strip()); i += 1
        page.out.append("<blockquote><p>" + inline(" ".join(quote)) + "</p></blockquote>")
        continue
    para = []
    while i < n and lines[i].strip() and not re.match(r"^(#{1,3}\s|```|\s*\||>)", lines[i]) and not LIST_RE.match(lines[i]):
        para.append(lines[i].strip()); i += 1
    page.paragraph(" ".join(para))
page.close_section()

toc = "\n".join(f'  <a href="#{sid}">{text}</a>' for sid, text in page.toc)
doc = open(shell, encoding="utf-8").read()
for key, value in (("{{title}}", page.title or "Untitled"), ("{{eyebrow}}", html.escape(eyebrow, quote=False)),
                   ("{{toc}}", toc), ("{{lede}}", page.lede), ("{{body}}", "\n".join(page.out))):
    doc = doc.replace(key, value)
if len(doc.encode("utf-8")) > LIMIT:
    biggest = sorted(embedded, key=lambda e: -e[1])[:5]
    sys.exit("page would be over 16MB; shrink these first (sips -Z 1600 <file>):\n"
             + "\n".join(f"  {size // 1024}K  {path}" for path, size in biggest))
open(out, "w", encoding="utf-8").write(doc)
print(out)
PY
