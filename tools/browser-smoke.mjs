import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { localStatus } from './local-web.mjs';

const status = localStatus();
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
const page = await context.newPage();
const errors = [];
page.on('pageerror', error => errors.push(error.message));
async function accessible() {
  const placeholder = page.locator('flt-semantics-placeholder');
  await placeholder.waitFor({ state: 'attached', timeout: 120000 });
  await placeholder.click({ force: true });
}
try {
  await page.goto('http://localhost:3000');
  await accessible();
  await page.getByRole('textbox', { name: 'Email address' }).fill('owner@home.test');
  await page.getByRole('button', { name: 'Email me a sign-in link' }).click();
  const inbox = status.MAILPIT_URL ?? status.INBUCKET_URL;
  let link;
  for (let attempt = 0; attempt < 30 && !link; attempt++) {
    const response = await fetch(`${inbox}/api/v1/messages`);
    const messages = await response.json();
    const mail = messages.messages?.find(message =>
      message.To?.some(recipient => recipient.Address === 'owner@home.test'));
    if (mail) {
      const detail = await (await fetch(`${inbox}/api/v1/message/${mail.ID}`)).json();
      link = (detail.Text ?? '').match(/https?:\/\/[^\s<>]+\/auth\/v1\/verify[^\s<>]+/)?.[0];
      if (!link) link = (detail.HTML ?? '').match(/href="(https?:\/\/[^" ]+\/auth\/v1\/verify[^" ]+)"/)?.[1]?.replaceAll('&amp;', '&');
    }
    if (!link) await new Promise(resolve => setTimeout(resolve, 500));
  }
  assert.ok(link, 'Supabase must send an actual sign-in email to local Mailpit');
  await page.goto(link);
  await accessible();
  await page.getByRole('button', { name: 'Spending' }).click();
  await page.getByRole('button', { name: 'Purchase' }).click();
  const summary = `Browser test groceries ${Date.now()}`;
  await page.getByRole('textbox', { name: 'Amount (BDT)' }).fill('123.45');
  await page.getByRole('textbox', { name: 'What did you buy?' }).fill(summary);
  await page.getByRole('button', { name: 'Save purchase' }).click();
  await page.getByText(summary, { exact: true }).waitFor({ timeout: 30000 });
  await page.reload();
  await accessible();
  await page.getByRole('button', { name: 'Spending' }).click();
  await page.getByText(summary, { exact: true }).waitFor({ timeout: 30000 });
  await page.screenshot({ path: '.local/web-acceptance.png' });
  assert.deepEqual(errors, [], 'Browser should not produce uncaught errors');
  console.log('PASS: local email login, expense creation, browser reload and persisted spending.');
} finally {
  await browser.close();
}
