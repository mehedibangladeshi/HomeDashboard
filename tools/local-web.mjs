import { spawn, spawnSync } from 'node:child_process';
import { mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

// No cloud credentials are used or printed. Generated files stay in .local/.
export function supabase(args, capture = false) {
  const result = spawnSync('npx', ['--yes', 'supabase@2.118.0', ...args], {
    encoding: 'utf8', stdio: capture ? ['ignore', 'pipe', 'pipe'] : 'inherit',
  });
  if (result.error || result.status !== 0) {
    throw new Error(`Supabase ${args[0]} failed. Check Docker and the CLI installation.`);
  }
  return capture ? JSON.parse(result.stdout) : undefined;
}

export function localStatus() {
  const status = supabase(['status', '-o', 'json'], true);
  const url = new URL(status.API_URL);
  if (!['localhost', '127.0.0.1'].includes(url.hostname)) {
    throw new Error('Local tooling refuses to operate on a remote project.');
  }
  return status;
}

function flutterCommand(args) {
  const sdk = process.env.HOMEDASHBOARD_FLUTTER_SDK;
  if (!sdk) return ['flutter', args];
  const dart = resolve(sdk, 'bin/cache/dart-sdk/bin/dart');
  if (!existsSync(dart)) throw new Error('Flutter SDK path is invalid.');
  return [dart, [
    `--packages=${resolve(sdk, 'packages/flutter_tools/.dart_tool/package_config.json')}`,
    resolve(sdk, 'packages/flutter_tools/bin/flutter_tools.dart'),
    '--suppress-analytics', '--no-version-check', ...args,
  ]];
}

async function main() {
  console.log('Starting local Supabase (first launch may download Docker images)…');
  supabase(['start', '--exclude', 'studio,imgproxy,logflare,vector'], true);
  supabase(['db', 'push', '--local']);
  const status = localStatus();
  mkdirSync('.local', { recursive: true });
  writeFileSync('.local/web.json', JSON.stringify({
    SUPABASE_URL: status.API_URL,
    SUPABASE_PUBLISHABLE_KEY: status.PUBLISHABLE_KEY ?? status.ANON_KEY,
    APP_ENV: 'local', WEB_APP_URL: 'http://localhost:3000',
    GOOGLE_SIGN_IN_ENABLED: false, GOOGLE_CALENDAR_ENABLED: false,
    PUSH_ENABLED: false,
  }, null, 2), { mode: 0o600 });
  const { seedLocal } = await import('./seed-local.mjs');
  await seedLocal(status);
  console.log('Web: http://localhost:3000');
  console.log(`Email inbox: ${status.MAILPIT_URL ?? status.INBUCKET_URL}`);
  console.log('Test emails: owner@home.test, manager@home.test, member@home.test');
  console.log('Use Email me a sign-in link, then open it from the local inbox.');
  const [command, args] = flutterCommand([
    'run', '-d', 'web-server', '--web-hostname', 'localhost',
    '--web-port', '3000', '--dart-define-from-file=.local/web.json',
  ]);
  const child = spawn(command, args, {
    stdio: 'inherit', env: { ...process.env, FLUTTER_SUPPRESS_ANALYTICS: 'true' },
  });
  child.on('error', () => {
    console.error('Flutter could not start. Install Flutter or set HOMEDASHBOARD_FLUTTER_SDK.');
    process.exitCode = 1;
  });
  child.on('exit', code => { process.exitCode = code ?? 1; });
}

if (process.argv[1] && resolve(process.argv[1]) === resolve('tools/local-web.mjs')) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
