const puppeteer = require("./_render_tmp/node_modules/puppeteer-core");
const path = require("path");
const fs = require("fs");

const chrome = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
const docs = path.resolve(__dirname);

const targets = process.argv.slice(2);
if (!targets.length) {
  console.error("Usage: node _render_png.js <file.mmd> [more.mmd...]");
  process.exit(1);
}

(async () => {
  const browser = await puppeteer.launch({
    executablePath: chrome,
    headless: "new",
    args: ["--no-sandbox", "--disable-gpu", "--allow-file-access-from-files"],
  });

  async function render(src) {
    const out = src.replace(/\.mmd$/i, ".png");
    const page = await browser.newPage();
    page.setDefaultTimeout(300000);
    await page.setViewport({ width: 1800, height: 1400, deviceScaleFactor: 2 });
    const url =
      "file:///" +
      docs.replace(/\\/g, "/") +
      "/_render_mermaid.html?src=" +
      encodeURIComponent(src);
    console.log("open", src);
    page.on("pageerror", (e) => console.error("pageerror", e.message));
    page.on("console", (msg) => {
      if (msg.type() === "error") console.error("console", msg.text());
    });
    await page.goto(url, { waitUntil: "networkidle0", timeout: 300000 });
    const err = await page.evaluate(() => document.body.dataset.error || "");
    if (err) throw new Error("mermaid: " + err);
    await page.waitForFunction(() => document.body.dataset.ready === "1", {
      timeout: 300000,
    });
    await page.waitForSelector("#diagram svg", { timeout: 120000 });
    // Also save SVG
    const svg = await page.$eval("#diagram", (el) => el.innerHTML);
    fs.writeFileSync(path.join(docs, src.replace(/\.mmd$/i, ".svg")), svg, "utf8");
    const box = await page.evaluate(() => {
      const svgEl = document.querySelector("#diagram svg");
      const r = svgEl.getBoundingClientRect();
      return {
        width: Math.ceil(r.width) + 48,
        height: Math.ceil(r.height) + 48,
      };
    });
    console.log(src, "size", box);
    const vw = Math.min(Math.max(box.width, 800), 8000);
    const vh = Math.min(Math.max(box.height, 600), 12000);
    await page.setViewport({ width: vw, height: vh, deviceScaleFactor: 2 });
    await new Promise((r) => setTimeout(r, 600));
    const el = await page.$("#diagram");
    await el.screenshot({ path: path.join(docs, out), type: "png" });
    console.log("wrote", out);
    await page.close();
  }

  try {
    for (const t of targets) {
      await render(t);
    }
  } finally {
    await browser.close();
  }
  console.log("ALL DONE");
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
