#!/usr/bin/env node
// ZMMO Panel static server + /api proxy → manager-agent:55555
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = '/home/thay/zmmo/packages/panel/dist';
const PORT = 3013;
const API_TARGET = { host: '127.0.0.1', port: 55555 };

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json',
  '.ico': 'image/x-icon',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.exe': 'application/octet-stream',
};

function proxy(req, res) {
  const opts = {
    host: API_TARGET.host,
    port: API_TARGET.port,
    path: req.url.replace(/^\/api/, ''),
    method: req.method,
    headers: { ...req.headers, host: `${API_TARGET.host}:${API_TARGET.port}` },
  };
  const pr = http.request(opts, (pres) => {
    res.writeHead(pres.statusCode, pres.headers);
    pres.pipe(res);
  });
  pr.on('error', (e) => {
    res.writeHead(502, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'manager-agent unreachable', detail: e.message }));
  });
  req.pipe(pr);
}

const server = http.createServer((req, res) => {
  let urlPath = decodeURIComponent(req.url.split('?')[0]);
  if (urlPath.startsWith('/api')) return proxy(req, res);

  // SPA fallback → index.html
  if (urlPath === '/') urlPath = '/index.html';
  let fp = path.join(ROOT, urlPath);
  if (!fp.startsWith(ROOT)) { res.writeHead(403); return res.end(); }
  if (!fs.existsSync(fp) || fs.statSync(fp).isDirectory()) fp = path.join(ROOT, 'index.html');

  const ext = path.extname(fp).toLowerCase();
  res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
  fs.createReadStream(fp).pipe(res);
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`ZMMO Panel on http://0.0.0.0:${PORT}  (proxy /api → ${API_TARGET.port})`);
});
