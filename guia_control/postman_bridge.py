"""Local HTTP -> RSEE CH1 adapter for Postman. Only binds to 127.0.0.1."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import threading

from rsee_control import Controller

LOCK = threading.Lock()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--controller-ip', default='192.168.1.253')
    parser.add_argument('--local-ip', default='192.168.1.240')
    parser.add_argument('--http-port', type=int, default=8765)
    args = parser.parse_args()

    class Handler(BaseHTTPRequestHandler):
        def reply(self, code, data):
            encoded = json.dumps(data).encode('utf-8')
            self.send_response(code)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Content-Length', str(len(encoded)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(encoded)

        def valid_request(self):
            if self.headers.get('Host', '').lower() not in (f'127.0.0.1:{args.http_port}', f'localhost:{args.http_port}'):
                self.reply(403, {'error': 'Localhost Host required'})
                return False
            if self.headers.get('Origin'):
                self.reply(403, {'error': 'Use Postman desktop or a direct local HTTP client'})
                return False
            if self.path != '/brightness':
                self.reply(404, {'error': 'Endpoint: /brightness'})
                return False
            return True

        def operate(self, value=None):
            try:
                with LOCK:
                    controller = Controller(args.controller_ip, local_ip=args.local_ip)
                    try:
                        actual = controller.read() if value is None else controller.set(value)
                    finally:
                        controller.close()
                self.reply(200, {'channel': 'CH1', 'brightness': actual,
                                 'controller_ip': args.controller_ip, 'verified': True})
            except (OSError, ValueError) as exc:
                self.reply(502, {'error': str(exc), 'note': 'Read current brightness before retrying a write'})

        def do_GET(self):
            if self.valid_request():
                self.operate()

        def do_POST(self):
            if not self.valid_request():
                return
            if self.headers.get('Content-Type', '').split(';')[0].strip().lower() != 'application/json':
                self.reply(415, {'error': 'Use Content-Type: application/json'})
                return
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 1 <= length <= 1024 or self.headers.get('Transfer-Encoding'):
                    raise ValueError('JSON body must be 1 to 1024 bytes')
                self.connection.settimeout(5)
                data = json.loads(self.rfile.read(length))
                if not isinstance(data, dict) or set(data) != {'brightness'}:
                    raise ValueError('JSON must have only the brightness field')
                value = data['brightness']
                if type(value) is not int or not 0 <= value <= 255:
                    raise ValueError('brightness must be an integer from 0 to 255')
            except (ValueError, OSError) as exc:
                self.reply(400, {'error': str(exc)})
                return
            self.operate(value)

    server = ThreadingHTTPServer(('127.0.0.1', args.http_port), Handler)
    print(f'Postman bridge: http://127.0.0.1:{args.http_port}/brightness', flush=True)
    print(f'Controller: {args.controller_ip}:8234; Ctrl+C stops the bridge.', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
