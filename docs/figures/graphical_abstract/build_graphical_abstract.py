"""Draw the VoIR graphical abstract from frozen publication coordinates.

Run with Python 3 and ReportLab. The adjacent CSV contains existing Figure 6
values; this script changes presentation only and performs no simulations.
All dimensions below are in PDF points. The three-panel composition is retained;
the bottom takeaway is omitted and the result interpretation is made explicit.
"""

from pathlib import Path
import csv
import math

from reportlab.lib.colors import HexColor, white
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph


# 1. Output, typography and the restrained palette used by the reference figures.
ROOT = Path(__file__).resolve().parent
WIDTH, HEIGHT = 900, 344
INK = HexColor("#252A30")
MUTED = HexColor("#60676D")
BORDER = HexColor("#CBD1D5")
PALE = HexColor("#F5F7F8")
BLUE = HexColor("#134B61")
CORAL = HexColor("#F18F6F")
GREEN = HexColor("#356A59")
UNKNOWN = HexColor("#E1E5E8")
FONTS = Path("C:/Windows/Fonts")
for name, filename in (("Body", "arial.ttf"), ("Bold", "arialbd.ttf"),
                       ("Math", "times.ttf"), ("Variable", "timesi.ttf")):
    pdfmetrics.registerFont(TTFont(name, str(FONTS / filename)))

pdf = canvas.Canvas(str(ROOT / "voir_graphical_abstract.pdf"), pagesize=(WIDTH, HEIGHT))
pdf.setTitle("Adversarial knowledge and system robustness")
pdf.setAuthor("Alex Sixie Cao and Leandro Iannacone")
pdf.setSubject("Graphical abstract draft using the corrected VoIR publication results")
# Crop the former takeaway strip while retaining the established drawing positions.
pdf.translate(0, -16)


def text(value, x, y, size=12, font="Body", color=INK, align="left"):
    """Draw a single baseline of text with explicit alignment."""
    pdf.setFillColor(color)
    pdf.setFont(font, size)
    draw = {"left": pdf.drawString, "center": pdf.drawCentredString,
            "right": pdf.drawRightString}[align]
    draw(x, y, value)


def paragraph(value, x, top, width, size=12, align=TA_CENTER, color=INK):
    """Place explanatory text or formatted mathematics in a bounded region."""
    style = ParagraphStyle("figure", fontName="Body", fontSize=size,
                           leading=1.26 * size, alignment=align, textColor=color)
    block = Paragraph(value, style)
    _, height = block.wrap(width, HEIGHT)
    block.drawOn(pdf, x, top - height)
    return height


def variable(value):
    return f'<font name="Variable">{value}</font>'


def roman(value):
    return f'<font name="Math">{value}</font>'


def subscript(value):
    return f'<sub size="9" rise="3">{value}</sub>'


def superscript(value):
    return f'<super size="9" rise="5">{value}</super>'


def math_symbol(value, *, italic=True, sub="", sup="", sub_italic=False):
    """Describe a mathematical symbol with correctly stacked script positions."""
    return (value, "Variable" if italic else "Math", sub, sup,
            "Variable" if sub_italic else "Math")


def math_line(symbols, x, baseline, size=17, align="center"):
    """Typeset a short equation as vector text, keeping superscripts above subscripts."""
    script_size = size * 0.64
    widths = []
    for value, font, sub, sup, sub_font in symbols:
        base_width = pdfmetrics.stringWidth(value, font, size)
        script_width = max(pdfmetrics.stringWidth(sub, sub_font, script_size),
                           pdfmetrics.stringWidth(sup, "Math", script_size))
        widths.append(base_width + script_width + (0.6 if script_width else 0))
    total = sum(widths)
    cursor = x - total / 2 if align == "center" else x
    for (value, font, sub, sup, sub_font), width in zip(symbols, widths):
        text(value, cursor, baseline, size, font)
        script_x = cursor + pdfmetrics.stringWidth(value, font, size) + 0.3
        if sub:
            text(sub, script_x, baseline - 0.24 * size, script_size, sub_font)
        if sup:
            text(sup, script_x, baseline + 0.43 * size, script_size, "Math")
        cursor += width
    return total


def upright(value):
    return math_symbol(value, italic=False)


def arrow(points, color=MUTED, width=0.85):
    """Draw a directed dependency, with an arrowhead only at its destination."""
    pdf.setStrokeColor(color)
    pdf.setLineWidth(width)
    path = pdf.beginPath()
    path.moveTo(*points[0])
    for point in points[1:]:
        path.lineTo(*point)
    pdf.drawPath(path)
    start, end = points[-2:]
    angle = math.atan2(end[1] - start[1], end[0] - start[0])
    length, half_width = 5.4, 2.25
    base_x = end[0] - length * math.cos(angle)
    base_y = end[1] - length * math.sin(angle)
    head = pdf.beginPath()
    head.moveTo(*end)
    head.lineTo(base_x - half_width * math.sin(angle), base_y + half_width * math.cos(angle))
    head.lineTo(base_x + half_width * math.sin(angle), base_y - half_width * math.cos(angle))
    head.close()
    pdf.setFillColor(color)
    pdf.drawPath(head, fill=1, stroke=0)


def panel(x, y, width, height, fill=white, line=BORDER):
    pdf.setFillColor(fill)
    pdf.setStrokeColor(line)
    pdf.setLineWidth(0.65)
    pdf.roundRect(x, y, width, height, 4, stroke=1, fill=1)


# 2. Physical system and a schematic observation of three component identities.
# Alternating colours indicate the actual five/five composition. Grey question
# marks in the lower row mean unknown identities, not damaged components.
panel(16, 32, 206, 310)
text("DANIELS SYSTEM", 119, 317, 15, "Bold", align="center")
arrow([(119, 275), (119, 298)], BLUE, 1.1)
text("F", 130, 286, 15, "Variable", BLUE)
pdf.setStrokeColor(INK)
pdf.setLineWidth(2.3)
pdf.line(39, 269, 199, 269)
pdf.line(39, 207, 199, 207)
pdf.setLineWidth(0.5)
for x in range(43, 198, 8):
    pdf.line(x, 206, x - 4, 201)
component_centres = [47.5 + 15.9 * index for index in range(10)]
for index, x in enumerate(component_centres):
    pdf.setStrokeColor(CORAL if index % 2 == 0 else BLUE)
    pdf.setLineWidth(4)
    pdf.line(x, 208, x, 268)

for x, label, color in ((33, "5 brittle", CORAL), (119, "5 ductile", BLUE)):
    pdf.setFillColor(color)
    pdf.rect(x, 187, 10, 4, stroke=0, fill=1)
    text(label, x + 15, 184.5, 13)
pdf.setStrokeColor(BORDER)
pdf.setLineWidth(0.5)
pdf.line(30, 171, 208, 171)
text("ADVERSARIAL KNOWLEDGE", 119, 150, 12.8, "Bold", align="center")
known_indices = {0, 3, 7}
for index, x in enumerate(component_centres):
    known = index in known_indices
    color = (CORAL if index % 2 == 0 else BLUE) if known else UNKNOWN
    pdf.setFillColor(color)
    pdf.setStrokeColor(color)
    pdf.roundRect(x - 6.5, 115, 13, 21, 1, fill=1, stroke=0)
    if not known:
        text("?", x, 120.5, 10, color=MUTED, align="center")
paragraph(f'Knowledge state {variable("κ")}{subscript(variable("h"))}', 27, 106, 184, 14)
paragraph(f'{variable("h")} = 3 known identities', 27, 84, 184, 13)
text("?  Unknown type", 119, 59, 12.5, color=MUTED, align="center")


# 3. Central framework. Both physical response and knowledge inform selection.
# The forward KL reference is the intact/null-action distribution. The VoIR
# comparison instead uses the uninformed attack at the same resource budget.
panel(244, 32, 312, 310, PALE)
text("VALUE OF INFORMATION", 400, 320, 14.5, "Bold", align="center")
text("OF ROBUSTNESS", 400, 302, 12.8, "Bold", align="center")
panel(266, 234, 268, 54)
action = variable("a") + superscript("*") + roman("(") + variable("d") + roman(", ") + variable("κ") + roman(")")
paragraph(f'Most damaging action {action}', 272, 278, 256, 14)
paragraph(f'Fixed attack size {variable("r")}', 272, 256, 256, 13, color=MUTED)
arrow([(222, 257), (265, 257)])
arrow([(222, 125), (235, 125), (235, 243), (265, 243)])
arrow([(400, 231), (400, 216)])
paragraph("Survival / extinction probabilities", 260, 208, 280, 14)
math_line([math_symbol("I", sub="rob"), upright(" = exp(−"),
           math_symbol("D", sub="KL"), upright(")")], 400, 170)
text("Intact-system reference", 400, 150, 13, color=MUTED, align="center")
pdf.setStrokeColor(BORDER)
pdf.setLineWidth(0.5)
pdf.line(260, 139, 540, 139)

math_line([math_symbol("VoIR", italic=False, sub="D"), upright("("),
           math_symbol("d"), upright(" | "), math_symbol("κ"), upright(" ≠ "),
           math_symbol("κ", sub="0"), upright(")")], 400, 112)
math_line([upright("= "), math_symbol("D", sub="KL", sup="*"), upright("("),
           math_symbol("d"), upright(" | "), math_symbol("κ"), upright(") − "),
           math_symbol("D", sub="KL", sup="*"), upright("("), math_symbol("d"),
           upright(" | "), math_symbol("κ", sub="0"), upright(")")], 400, 86)
text("Compared with uninformed attacks", 400, 61, 13, color=MUTED, align="center")


# 4. Corrected numerical example, using three of the published Figure 6 curves.
panel(580, 32, 304, 310)
text("DANIELS EXAMPLE", 732, 317, 15, "Bold", align="center")
text("Selected knowledge states", 732, 295, 13, color=MUTED, align="center")
arrow([(557, 195), (579, 195)])
with (ROOT / "figure6_selected.csv").open(newline="", encoding="utf-8") as stream:
    rows = list(csv.DictReader(stream))
selected = {h: sorted((row for row in rows if int(row["h"]) == h), key=lambda row: int(row["r"]))
            for h in (1, 5, 10)}
for h, curve in selected.items():
    assert [int(row["r"]) for row in curve] == list(range(1, 10))
    assert max(curve, key=lambda row: float(row["VoIR_D_nats"]))["r"] == "7"
    assert float(curve[-1]["VoIR_D_nats"]) == 0

plot_x, plot_y, plot_width, plot_height = 629, 134, 235, 146
def coordinates(r, value):
    return plot_x + (r - 1) / 8 * plot_width, plot_y + value / 2 * plot_height

pdf.setStrokeColor(MUTED)
pdf.setLineWidth(0.6)
pdf.line(plot_x, plot_y, plot_x + plot_width, plot_y)
pdf.line(plot_x, plot_y, plot_x, plot_y + plot_height)
for value in (0, 1, 2):
    _, y = coordinates(1, value)
    pdf.line(plot_x - 3, y, plot_x, y)
    text(str(value), plot_x - 7, y - 4, 12.5, color=MUTED, align="right")
for r in (1, 3, 5, 7, 9):
    x, _ = coordinates(r, 0)
    pdf.line(x, plot_y, x, plot_y - 3)
    text(str(r), x, plot_y - 16, 12.5, color=MUTED, align="center")

curve_colors = {1: CORAL, 5: GREEN, 10: INK}
for h, curve in selected.items():
    pdf.setStrokeColor(curve_colors[h])
    pdf.setFillColor(curve_colors[h])
    pdf.setLineWidth(1.55)
    path = pdf.beginPath()
    for index, row in enumerate(curve):
        point = coordinates(int(row["r"]), float(row["VoIR_D_nats"]))
        (path.moveTo if index == 0 else path.lineTo)(*point)
    pdf.drawPath(path)
    for row in curve:
        x, y = coordinates(int(row["r"]), float(row["VoIR_D_nats"]))
        pdf.circle(x, y, 2.3, fill=1, stroke=0)
for index, h in enumerate((1, 5, 10)):
    y = 267 - 17 * index
    pdf.setStrokeColor(curve_colors[h])
    pdf.setLineWidth(1.55)
    pdf.line(640, y, 658, y)
    paragraph(f'{variable("h")} = {h}', 664, y + 7, 55, 13, align=TA_LEFT)

paragraph(f'Attack size {variable("r")}', 635, 109, 220, 14)
pdf.saveState()
pdf.translate(602, 207)
pdf.rotate(90)
math_line([math_symbol("VoIR", italic=False, sub="D"), upright("("),
           math_symbol("r"), upright(" | "), math_symbol("κ", sub="h", sub_italic=True),
           upright(") (nats)")], 0, 0, size=14)
pdf.restoreState()
paragraph('More knowledge can reduce system robustness.<br/>'
          'The value of knowledge rises and then falls<br/>'
          'as attack size increases in this example.', 592, 88, 280, 12.3)


# 5. Export the artwork without a separate bottom takeaway.
pdf.showPage()
pdf.save()
print(ROOT / "voir_graphical_abstract.pdf")
