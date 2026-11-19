"""Loopback-only TLS fixture. Start only within a registered test window; no production data."""
import argparse
import json
import ssl
import threading
import time
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--cert', required=True)
parser.add_argument('--key', required=True)
parser.add_argument('--port-file', required=True)
parser.add_argument('--journal', required=True)
args = parser.parse_args()
counts = Counter()
lock = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *_args):
        pass

    def do_GET(self):
        with lock:
            counts[self.path] += 1
            attempt = counts[self.path]
        status, body, delay = 200, b'{"value":"ok"}', 0
        short = self.path.startswith('/farms/p-short-')
        if short:
            status = int(self.path.rsplit('-', 1)[1].split('.')[0])
        if self.path == '/client-manifest.json':
            status = 503 if attempt < 3 else 200
        elif self.path == '/parcel-catalog.json':
            status = 404
        elif self.path == '/farms/p-exhaust.json':
            status = 502
        elif self.path == '/farms/p-hash.json':
            body = b'{"value":"wrong"}'
        elif self.path == '/farms/p-invalid.json':
            body = b'not json'
        elif self.path in ('/farms/p-slow.json', '/farms/p-timeout.json'):
            delay = 2.0
        with lock:
            with Path(args.journal).open('a') as output:
                output.write(json.dumps({'at': time.time(), 'path': self.path,
                                         'attempt': attempt, 'status': status}) + '\n')
        if delay:
            time.sleep(delay)
        try:
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body) + (40 if short else 0)))
            if short:
                # Deliberately contradictory framing: a complete chunk stream whose
                # decoded body is shorter than Content-Length. Keep TLS open so the
                # engine reports its retained HTTP status, not a separate TLS EOF.
                self.send_header('Transfer-Encoding', 'chunked')
            self.end_headers()
            self.wfile.write((('%x\r\n' % len(body)).encode() + body + b'\r\n0\r\n\r\n') if short else body)
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
            pass  # Intentional cancelled/timeout clients.


server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
server.daemon_threads = True
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(args.cert, args.key)
server.socket = context.wrap_socket(server.socket, server_side=True)
Path(args.port_file).write_text(str(server.server_port))
server.serve_forever(poll_interval=0.1)
