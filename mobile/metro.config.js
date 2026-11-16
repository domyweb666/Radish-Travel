// 預設設定，多一件事：測試階段把「用講的改行程」接到這台電腦的 claude cli（看 dev/ai-cli.js）。
// 只有 .env.local 寫了 EXPO_PUBLIC_AI_ENDPOINT=/__ai 才會掛上。
const { getDefaultConfig } = require('expo/metro-config');
const { aiCli, ROUTE } = require('./dev/ai-cli');

const config = getDefaultConfig(__dirname);

if (process.env.EXPO_PUBLIC_AI_ENDPOINT === ROUTE) {
  const prev = config.server?.enhanceMiddleware;
  config.server = {
    ...config.server,
    enhanceMiddleware: (middleware, server) => {
      const base = prev ? prev(middleware, server) : middleware;
      return (req, res, next) => aiCli(req, res, () => base(req, res, next));
    },
  };
  console.log('[ai-cli] 「用講的改行程」接到這台電腦的 claude cli');
}

module.exports = config;
