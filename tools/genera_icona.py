"""Icone di tk-clienti nello stile delle app TK: quadrato navy, valigetta bianca, bollino blu con la persona.
Uso: python tools/genera_icona.py (serve Pillow) -> assets/icona.png e assets/icona-adattiva.png,
poi: dart run flutter_launcher_icons"""
import os
from PIL import Image, ImageDraw, ImageFont

QUI = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_ICONE = r"C:\dev\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf"
NAVY, NAVY2, BLU = (15, 23, 42), (30, 41, 59), (37, 99, 235)
VALIGETTA = chr(0xF02C7)  # Icons.work_rounded
PERSONA = chr(0xF0071)  # Icons.person_rounded
G = 4096


def sfondo(img):
    lato = img.size[0]
    grad = Image.new("RGB", (lato, lato))
    gd = ImageDraw.Draw(grad)
    for i in range(lato):
        t = i / lato
        gd.line([(0, i), (lato, i)], fill=tuple(int(NAVY2[k] + (NAVY[k] - NAVY2[k]) * t) for k in range(3)))
    maschera = Image.new("L", (lato, lato), 0)
    ImageDraw.Draw(maschera).rounded_rectangle([0, 0, lato - 1, lato - 1], radius=int(lato * .24), fill=255)
    img.paste(grad, (0, 0), maschera)


def simbolo(img, x0, y0, s):
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(FONT_ICONE, int(s * .86))
    d.text((x0 + s * .42, y0 + s * .44), VALIGETTA, font=f, fill="white", anchor="mm")
    cx, cy, r = x0 + s * .76, y0 + s * .74, s * .22
    d.ellipse([cx - r * 1.12, cy - r * 1.12, cx + r * 1.12, cy + r * 1.12], fill=NAVY)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=BLU)
    fp = ImageFont.truetype(FONT_ICONE, int(s * .30))
    d.text((cx, cy), PERSONA, font=fp, fill="white", anchor="mm")


img = Image.new("RGBA", (G, G), (0, 0, 0, 0))
sfondo(img)
simbolo(img, G * .14, G * .12, G * .76)
img.resize((1024, 1024), Image.LANCZOS).save(os.path.join(QUI, "assets", "icona.png"))
ad = Image.new("RGBA", (G, G), (0, 0, 0, 0))
simbolo(ad, G * .19, G * .17, G * .62)
ad.resize((1024, 1024), Image.LANCZOS).save(os.path.join(QUI, "assets", "icona-adattiva.png"))
print("icone create")
