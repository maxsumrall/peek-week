import { chromium } from 'playwright';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = path.resolve(process.argv[2] ?? '.');
const docs = path.join(root, 'docs');

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 1600 }, deviceScaleFactor: 2 });

await page.goto(pathToFileURL(path.join(docs, 'app-shot.html')).href);
await page.screenshot({ path: path.join(docs, 'app-running.png') });

await page.setViewportSize({ width: 1440, height: 1600 });
await page.goto(pathToFileURL(path.join(docs, 'github-page.html')).href);
await page.screenshot({ path: path.join(docs, 'github-preview.png'), fullPage: true });

await browser.close();
console.log('Captured previews into', docs);
