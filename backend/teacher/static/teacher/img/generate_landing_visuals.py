# -*- coding: utf-8 -*-
"""Génère des mockups d'écrans Yekola pour la landing portail établissement."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(r"e:\MEMOIRE\backend\teacher\static\teacher\img")
OUT.mkdir(parents=True, exist_ok=True)

INK = (10, 22, 40)
INK_MID = (19, 37, 63)
PRIMARY = (13, 71, 161)
PRIMARY_SOFT = (227, 238, 249)
CANVAS = (238, 241, 246)
SURFACE = (255, 255, 255)
BORDER = (208, 215, 226)
TEXT = (18, 26, 40)
MUTED = (90, 101, 120)
SUCCESS = (15, 118, 110)
WHITE = (255, 255, 255)


def font(size, bold=False):
    paths = [
        r"C:\Windows\Fonts\segoeuib.ttf" if bold else r"C:\Windows\Fonts\segoeui.ttf",
        r"C:\Windows\Fonts\arialbd.ttf" if bold else r"C:\Windows\Fonts\arial.ttf",
    ]
    for p in paths:
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            pass
    return ImageFont.load_default()


def rr(draw, box, fill, outline=None, r=12):
    draw.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=1)


def browser_chrome(draw, w, title="Yekola — Portail établissement"):
    rr(draw, (0, 0, w - 1, 42), (245, 247, 250), BORDER, 0)
    for i, c in enumerate([(239, 68, 68), (234, 179, 8), (34, 197, 94)]):
        draw.ellipse((14 + i * 18, 14, 26 + i * 18, 26), fill=c)
    draw.text((80, 12), title, fill=MUTED, font=font(13))


def sidebar(draw, h, active):
    draw.rectangle((0, 42, 200, h), fill=INK)
    draw.text((24, 58), "Yekola", fill=WHITE, font=font(20, True))
    items = [
        ("Tableau de bord", "dashboard"),
        ("Cours", "courses"),
        ("Notes LMD", "grades"),
        ("Rapports", "reports"),
        ("Messages", "chat"),
    ]
    y = 110
    for label, key in items:
        if key == active:
            rr(draw, (12, y - 6, 188, y + 28), INK_MID, r=8)
            color = WHITE
        else:
            color = (154, 168, 189)
        draw.text((28, y), label, fill=color, font=font(13))
        y += 42


def kpi(draw, x, y, w, label, value, sub):
    rr(draw, (x, y, x + w, y + 88), SURFACE, BORDER, 10)
    draw.text((x + 16, y + 14), label, fill=MUTED, font=font(12))
    draw.text((x + 16, y + 36), value, fill=TEXT, font=font(26, True))
    draw.text((x + 16, y + 66), sub, fill=SUCCESS, font=font(11))


def table(draw, x, y, w, headers, rows):
    rr(draw, (x, y, x + w, y + 40 + len(rows) * 36), SURFACE, BORDER, 10)
    draw.rectangle((x, y, x + w, y + 36), fill=PRIMARY_SOFT)
    col_w = w // len(headers)
    for i, h in enumerate(headers):
        draw.text((x + 14 + i * col_w, y + 10), h, fill=PRIMARY, font=font(12, True))
    for ri, row in enumerate(rows):
        yy = y + 44 + ri * 36
        for i, cell in enumerate(row):
            draw.text((x + 14 + i * col_w, yy), cell, fill=TEXT, font=font(12))
        if ri < len(rows) - 1:
            draw.line((x + 8, yy + 28, x + w - 8, yy + 28), fill=BORDER)


def make_manager():
    w, h = 1280, 760
    img = Image.new("RGB", (w, h), CANVAS)
    draw = ImageDraw.Draw(img)
    browser_chrome(draw, w, "Yekola — Admin (Université)")
    sidebar(draw, h, "dashboard")
    draw.text((230, 70), "Vue université", fill=TEXT, font=font(28, True))
    draw.text((230, 108), "Gouvernance académique · consolidation facultaire", fill=MUTED, font=font(14))
    kpi(draw, 230, 150, 230, "Facultés", "4", "Décanats actifs")
    kpi(draw, 480, 150, 230, "Étudiants", "1 248", "+62 ce semestre")
    kpi(draw, 730, 150, 230, "Cours LMD", "86", "Publiés")
    kpi(draw, 980, 150, 250, "Rapports", "3 / 4", "Reçus cette année")
    table(
        draw, 230, 270, 1000,
        ["Faculté", "Doyen", "Rapport", "Statut"],
        [
            ["Sciences", "Ilunga P.", "2025-2026", "Validé"],
            ["Droit", "Mukendi A.", "2025-2026", "Reçu"],
            ["Économie", "Kabongo M.", "2025-2026", "En cours"],
            ["Médecine", "Ngalula C.", "2025-2026", "Attendu"],
        ],
    )
    rr(draw, (230, 520, 1230, 700), SURFACE, BORDER, 10)
    draw.text((250, 540), "Résultats consolidés inter-facultés", fill=TEXT, font=font(16, True))
    # simple bars
    bars = [("Sciences", 0.82), ("Droit", 0.74), ("Économie", 0.69), ("Médecine", 0.77)]
    bx = 270
    for name, v in bars:
        bh = int(110 * v)
        draw.rectangle((bx, 660 - bh, bx + 70, 660), fill=PRIMARY)
        draw.text((bx, 670), name[:8], fill=MUTED, font=font(11))
        bx += 140
    img.save(OUT / "landing_manager.png", "PNG", optimize=True)


def make_dean():
    w, h = 1280, 760
    img = Image.new("RGB", (w, h), CANVAS)
    draw = ImageDraw.Draw(img)
    browser_chrome(draw, w, "Yekola — Décanat facultaire")
    sidebar(draw, h, "grades")
    draw.text((230, 70), "Délibération LMD", fill=TEXT, font=font(28, True))
    draw.text((230, 108), "Faculté des Sciences · Promotion L2 Informatique · S4", fill=MUTED, font=font(14))
    kpi(draw, 230, 150, 300, "Notes reçues", "28", "Soumises par enseignants")
    kpi(draw, 550, 150, 300, "À valider", "6", "En attente décanat")
    kpi(draw, 870, 150, 360, "Crédits semestre", "30 + 30", "Règle LMD")
    table(
        draw, 230, 270, 1000,
        ["Étudiant", "Cours", "TP", "Interro", "Examen", "Décision"],
        [
            ["KABONGO M.", "Algo. I", "14", "12", "15", "Admis"],
            ["ILUNGA P.", "BD", "11", "10", "12", "Admis"],
            ["MUKENDI A.", "Réseaux", "8", "7", "9", "Ajourné"],
            ["NGALULA C.", "Web", "13", "14", "16", "Admis"],
            ["TSHIBANDA L.", "Maths", "10", "11", "12", "Admis"],
        ],
    )
    rr(draw, (230, 520, 700, 700), SURFACE, BORDER, 10)
    draw.text((250, 545), "Workflow des notes", fill=TEXT, font=font(15, True))
    steps = ["DRAFT", "SOUMIS", "VALIDÉ", "PUBLIÉ"]
    sx = 270
    for i, s in enumerate(steps):
        rr(draw, (sx, 600, sx + 90, 640), PRIMARY if i < 3 else SUCCESS, r=8)
        draw.text((sx + 14, 610), s, fill=WHITE, font=font(11, True))
        if i < 3:
            draw.line((sx + 94, 620, sx + 110, 620), fill=BORDER, width=2)
        sx += 110
    rr(draw, (730, 520, 1230, 700), SURFACE, BORDER, 10)
    draw.text((750, 545), "Actions décanat", fill=TEXT, font=font(15, True))
    for i, t in enumerate(["Créer compte étudiant", "Affecter enseignant", "Générer rapport annuel"]):
        rr(draw, (750, 590 + i * 32, 1200, 616 + i * 32), PRIMARY_SOFT, r=6)
        draw.text((766, 594 + i * 32), t, fill=PRIMARY, font=font(12))
    img.save(OUT / "landing_dean.png", "PNG", optimize=True)


def make_teacher():
    w, h = 1280, 760
    img = Image.new("RGB", (w, h), CANVAS)
    draw = ImageDraw.Draw(img)
    browser_chrome(draw, w, "Yekola — Espace enseignant")
    sidebar(draw, h, "courses")
    draw.text((230, 70), "Mes cours affectés", fill=TEXT, font=font(28, True))
    draw.text((230, 108), "Semestre 2 · Contenu pédagogique & évaluation", fill=MUTED, font=font(14))
    courses = [
        ("Algorithmique I", "L2 Info", "12 leçons", "Publié"),
        ("Bases de données", "L2 Info", "9 leçons", "Publié"),
        ("Programmation Web", "L1 Info", "7 leçons", "Brouillon"),
    ]
    x = 230
    for title, promo, lessons, status in courses:
        rr(draw, (x, 150, x + 310, 290), SURFACE, BORDER, 12)
        draw.rectangle((x, 150, x + 310, 190), fill=PRIMARY)
        draw.text((x + 16, 162), title, fill=WHITE, font=font(15, True))
        draw.text((x + 16, 210), promo, fill=MUTED, font=font(12))
        draw.text((x + 16, 235), lessons, fill=TEXT, font=font(13))
        draw.text((x + 16, 260), status, fill=SUCCESS if status == "Publié" else (180, 83, 9), font=font(12, True))
        x += 330
    table(
        draw, 230, 320, 1000,
        ["Étudiant", "TP", "Interro", "Examen", "Total", "Statut"],
        [
            ["KABONGO M.", "14", "12", "15", "41", "Brouillon"],
            ["ILUNGA P.", "11", "10", "12", "33", "Brouillon"],
            ["MUKENDI A.", "8", "7", "9", "24", "Brouillon"],
            ["NGALULA C.", "13", "14", "—", "27", "En saisie"],
        ],
    )
    rr(draw, (230, 560, 1230, 720), SURFACE, BORDER, 10)
    draw.text((250, 580), "Prochaines actions", fill=TEXT, font=font(15, True))
    for i, (t, d) in enumerate([
        ("Corriger TP — Algorithmique I", "5 dépôts"),
        ("Publier quiz — Bases de données", "Prêt"),
        ("Transmettre notes au décanat", "À faire"),
    ]):
        yy = 620 + i * 28
        draw.text((260, yy), t, fill=TEXT, font=font(13))
        draw.text((1050, yy), d, fill=MUTED, font=font(12))
    img.save(OUT / "landing_teacher.png", "PNG", optimize=True)


def make_hero():
    """Composite hero visual: main dashboard framed on atmospheric background."""
    w, h = 1600, 900
    img = Image.new("RGB", (w, h), (232, 238, 247))
    draw = ImageDraw.Draw(img)
    # soft atmosphere
    for i in range(8):
        c = 220 + i
        draw.ellipse((-200 + i * 40, -100 + i * 20, 700 - i * 30, 500 - i * 20), fill=(c, c + 4, min(255, c + 12)))
    # load manager as hero shot
    mgr = Image.open(OUT / "landing_manager.png").convert("RGB")
    mgr = mgr.resize((1180, 700), Image.Resampling.LANCZOS)
    # drop shadow
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((220, 120, 1420, 840), radius=18, fill=(10, 22, 40, 40))
    img = Image.alpha_composite(img.convert("RGBA"), shadow).convert("RGB")
    draw = ImageDraw.Draw(img)
    # frame
    fx, fy = 210, 100
    img.paste(mgr, (fx, fy))
    draw.rounded_rectangle((fx - 2, fy - 2, fx + 1180 + 2, fy + 700 + 2), radius=14, outline=BORDER, width=2)
    img.save(OUT / "landing_hero.png", "PNG", optimize=True)


def main():
    make_manager()
    make_dean()
    make_teacher()
    make_hero()
    for name in ("landing_hero.png", "landing_manager.png", "landing_dean.png", "landing_teacher.png"):
        print(OUT / name)


if __name__ == "__main__":
    main()
