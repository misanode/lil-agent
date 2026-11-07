import { spawn } from 'node:child_process';
import electron from 'electron';

const dev = process.argv.includes('--dev');
const env = { ...process.env };
let vite = null;
if (dev) {
  const { createServer } = await import('vite');
  vite = await createServer();
  await vite.listen();
  env.VITE_DEV_SERVER_URL = vite.resolvedUrls.local[0];
}
const child = spawn(electron, ['.'], { stdio: 'inherit', env });
child.on('exit', async (code) => {
  await vite?.close();
  process.exit(code ?? 0);
});
