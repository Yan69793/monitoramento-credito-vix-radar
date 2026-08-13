import pathlib
from playwright.sync_api import sync_playwright

HERE = pathlib.Path(__file__).parent
with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page()
    status = {}
    pg.on("response", lambda r: status.setdefault(r.url.split("/")[-1], r.status) if ("cormorant" in r.url or "woff2" in r.url) else None)
    pg.on("requestfailed", lambda r: status.setdefault("FAIL:" + r.url.split("/")[-1], r.failure))
    pg.on("pageerror", lambda e: print("PAGEERROR:", e))
    pg.goto((HERE / "banner-linkedin-1200x627.html").as_uri())
    pg.wait_for_timeout(2500)
    print("recursos:", status)
    faces = pg.evaluate("Array.from(document.fonts).map(f => f.family + ' ' + f.weight + ' ' + f.status).slice(0, 20)")
    print("fontfaces:", faces)
    pg.close()
    b.close()
