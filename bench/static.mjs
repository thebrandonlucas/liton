// For the precompression experiment: serves a UI directory's files under /ui/
// as liton's daemon does (no-cache, ETag revalidation), but sends a file's
// precompressed `.br` sibling when the browser accepts Brotli, and passes
// every other path to liton's daemon.
import fs from "node:fs";
import http from "node:http";
import path from "node:path";

const types = { ".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8", ".mjs": "text/javascript; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".wasm": "application/wasm" };

export function precompressed_server(listen_port, www, daemon_port) {
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, "http://x");
    if (url.pathname === "/") {
      res.writeHead(302, { location: "/ui/index.html" }).end();
      return;
    }
    const file = url.pathname.startsWith("/ui/") ? path.join(www, path.basename(url.pathname)) : null;
    if (!file || !fs.existsSync(file)) {
      const upstream = http.request({ host: "127.0.0.1", port: daemon_port, path: req.url, method: req.method, headers: req.headers }, (answer) => {
        res.writeHead(answer.statusCode, answer.headers);
        answer.pipe(res);
      });
      upstream.on("error", () => res.destroy());
      req.pipe(upstream);
      return;
    }
    const brotli = /\bbr\b/.test(req.headers["accept-encoding"] ?? "") && fs.existsSync(`${file}.br`);
    const sent = brotli ? `${file}.br` : file;
    const stat = fs.statSync(sent);
    const etag = `W/"${stat.size.toString(16)}-${stat.mtimeMs.toString(16)}${brotli ? "-br" : ""}"`;
    const headers = { "content-type": types[path.extname(file)] ?? "application/octet-stream", "cache-control": "no-cache", vary: "Accept-Encoding", etag };
    if (req.headers["if-none-match"] === etag) {
      res.writeHead(304, headers).end();
      return;
    }
    if (brotli) headers["content-encoding"] = "br";
    headers["content-length"] = stat.size;
    res.writeHead(200, headers);
    fs.createReadStream(sent).pipe(res);
  });
  return new Promise((resolve) => server.listen(listen_port, "127.0.0.1", () => resolve(server)));
}
