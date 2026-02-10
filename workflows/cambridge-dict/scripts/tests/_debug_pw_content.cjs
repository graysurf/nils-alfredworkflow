const { chromium } = require('playwright');
(async () => {
  const url = process.argv[2];
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 12000 });
  const html = await page.content();
  console.log(html.slice(0, 2000));
  console.error('HAS_CF', /cloudflare|challenge|attention required|cf-challenge/i.test(html));
  await browser.close();
})();
