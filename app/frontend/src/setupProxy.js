const { createProxyMiddleware } = require('http-proxy-middleware');

// Proxies /api from the dev server to the Go API.
//
// This replaces the "proxy" field in package.json, which only accepts a literal
// string. The target has to differ by environment: running on the host the API
// is on localhost, but inside docker-compose "localhost" is the frontend
// container itself and the API is reachable as `api` on the compose network.
module.exports = function (app) {
  app.use(
    '/api',
    createProxyMiddleware({
      target: process.env.API_PROXY_TARGET || 'http://localhost:3000',
      changeOrigin: true,
    })
  );
};
