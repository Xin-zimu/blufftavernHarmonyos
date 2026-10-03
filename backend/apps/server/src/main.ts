import { createApp } from './app.js';
import { readConfig } from './config/env.js';

const config = readConfig();
const { app } = await createApp(config);
const shutdownTimeoutMs = 10_000;
let shuttingDown = false;

const shutdown = async (signal: NodeJS.Signals) => {
  if (shuttingDown) return;
  shuttingDown = true;
  const forceExit = setTimeout(() => {
    app.log.error({ signal, timeoutMs: shutdownTimeoutMs }, 'Forced shutdown after timeout');
    process.exit(1);
  }, shutdownTimeoutMs);
  forceExit.unref?.();

  try {
    await app.close();
    clearTimeout(forceExit);
    process.exit(0);
  } catch (error) {
    app.log.error({ signal, error }, 'Shutdown failed');
    process.exit(1);
  }
};
process.on('SIGINT', () => void shutdown('SIGINT'));
process.on('SIGTERM', () => void shutdown('SIGTERM'));

try { await app.listen({ host: config.host, port: config.port }); }
catch (error) { app.log.error(error); process.exit(1); }
