# render-banners.py — renderiza os banners HTML em PNG 2x via Playwright.
# Valida tambem overflow e carregamento de fontes. Somente leitura de arquivos locais.
import sys, pathlib
from playwright.sync_api import sync_playwright

HERE = pathlib.Path(__file__).parent
JOBS = [
    ("banner-linkedin-1200x627.html", 1200, 627, "vixradar-banner-linkedin-1200x627.png"),
    ("banner-instagram-1080x1080.html", 1080, 1080, "vixradar-banner-instagram-1080x1080.png"),
]

ok = True
with sync_playwright() as p:
    browser = p.chromium.launch()
    for html, w, h, out in JOBS:
        page = browser.new_page(viewport={"width": w, "height": h}, device_scale_factor=2)
        errors = []
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.goto((HERE / html).as_uri())
        page.evaluate("document.fonts.ready.then(() => window.__fontsReady = true)")
        page.wait_for_function("window.__fontsReady === true", timeout=15000)
        page.wait_for_timeout(400)
        ov = page.evaluate(
            "() => ({sw: document.documentElement.scrollWidth, sh: document.documentElement.scrollHeight,"
            " iw: window.innerWidth, ih: window.innerHeight})"
        )
        fonts = page.evaluate(
            "() => ({serif: getComputedStyle(document.querySelector('h1')).fontFamily,"
            " sans: getComputedStyle(document.body).fontFamily})"
        )
        page.screenshot(path=str(HERE / out))
        browser.close_page if False else None
        page.close()
        overflow = ov["sw"] > ov["iw"] or ov["sh"] > ov["ih"]
        if overflow:
            ok = False
        print(f"{out}: {ov['sw']}x{ov['sh']} vs viewport {ov['iw']}x{ov['ih']} overflow={overflow}")
        print(f"  fonts: {fonts}")
        if errors:
            ok = False
            print(f"  pageerrors: {errors}")
    browser.close()
sys.exit(0 if ok else 1)
