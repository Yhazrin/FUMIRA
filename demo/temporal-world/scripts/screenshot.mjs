/**
 * Screenshot the rendered scene for comparison with reference image.
 * Usage: node scripts/screenshot.mjs [output.png] [waitMs]
 */
import puppeteer from 'puppeteer';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const outPath = process.argv[2] || path.join(__dirname, '../runtime/jobs/scene-reconstruct-test/output/screenshot.png');
const waitMs = parseInt(process.argv[3] || '3000', 10);

async function main() {
  const browser = await puppeteer.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 720 });

  console.log('Navigating to scene...');
  await page.goto('http://localhost:3210/desktop.html', { waitUntil: 'networkidle2', timeout: 15000 });

  // Wait for Three.js to render
  console.log(`Waiting ${waitMs}ms for render...`);
  await new Promise(r => setTimeout(r, waitMs));

  // Hide UI overlays for clean screenshot
  await page.evaluate(() => {
    const ids = ['loading', 'qr-panel', 'time-display', 'interval-card', 'scene-status', 'top-bar'];
    ids.forEach(id => {
      const el = document.getElementById(id);
      if (el) el.style.display = 'none';
    });
  });

  await page.screenshot({ path: outPath, fullPage: false });
  console.log(`Screenshot saved: ${outPath}`);

  await browser.close();
}

main().catch(err => {
  console.error('Screenshot failed:', err.message);
  process.exit(1);
});
