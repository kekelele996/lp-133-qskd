const { createApp } = require('./src/app');
const env = require('./src/config/env');
const messages = require('./src/constants/messages');
const logger = require('./src/utils/logger');
const ensureSchema = require('./src/db/ensureSchema');

const start = async () => {
  await ensureSchema();

  const app = createApp();
  app.listen(env.port, () => {
    logger.info(`${messages.server.started}，端口: ${env.port}`);
  });
};

start().catch((err) => {
  logger.error('服务启动失败', err.stack || err.message || err);
  process.exit(1);
});
