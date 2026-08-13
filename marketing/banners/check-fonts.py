import pathlib
from playwright.sync_api import sync_playwright

HERE = pathlib.Path(__file__).parent
with sync_playwright() as p:
    b = p.chromium.launch()
    for name in ["banner-linkedin-1200x627.html", "banner-instagram-1080x1080.html"]:
        pg = b.new_page()
        pg.goto((HERE / name).as_uri())
        result = pg.evaluate(
            "document.fonts.ready.then(() => ({"
            " cormorant: document.fonts.check('500 16px \"Cormorant Garamond\"'),"
            " cormorantItalic: document.fonts.check('italic 500 16px \"Cormorant Garamond\"'),"
            " dmsans: document.fonts.check('16px \"DM Sans\"')"
            "}))"
        )
        print(name, "| cormorant:", result["cormorant"], "| dmsans:", result["dmsans"])
        pg.close()
    b.close()
