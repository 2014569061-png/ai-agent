// Owned, data-free HTTP process used by the terminal preview integration tests.
const http = require('http');
const args = process.argv.slice(2);
const value = (name, fallback) => {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : fallback;
};
if (args.includes('--fail')) process.exit(23);
const port = Number(value('--port', 0));
const host = value('--host', '127.0.0.1');
const server = http.createServer((_, response) => {
  response.writeHead(200, { 'content-type': 'application/json' });
  response.end(JSON.stringify({ port: server.address().port, host: server.address().address }));
});
server.on('error', () => process.exit(24));
setTimeout(() => server.listen(port, host), Number(value('--delay', 0)));
process.on('SIGTERM', () => server.close(() => process.exit(0)));
