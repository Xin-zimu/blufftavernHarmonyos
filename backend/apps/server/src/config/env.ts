export interface ServerConfig {
  host: string;
  port: number;
  clientOrigin: string;
  logLevel: string;
  webRoot?: string;
}

export function readConfig(env: NodeJS.ProcessEnv = process.env): ServerConfig {
  const port = Number(env.PORT ?? 3001);
  if (!Number.isInteger(port) || port < 0 || port > 65_535) throw new Error('PORT must be a valid integer');
  const webRoot = env.WEB_ROOT?.trim();
  return {
    host: env.HOST ?? '127.0.0.1',
    port,
    clientOrigin: env.CLIENT_ORIGIN ?? 'http://localhost:5173',
    logLevel: env.LOG_LEVEL ?? 'info',
    ...(webRoot ? { webRoot } : {}),
  };
}
