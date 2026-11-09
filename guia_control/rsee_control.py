"""Control CH1 using the RSEE V2022 protocol validated on this controller."""
import argparse
import datetime
import json
import pathlib
import random
import socket
import time


class Controller:
    def __init__(self, host='192.168.1.253', port=8234, local_ip='192.168.1.240'):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.settimeout(3)
        try:
            self.sock.bind((local_ip, 0))
            self.sock.connect((host, port))
        except BaseException:
            self.sock.close()
            raise

    def close(self):
        self.sock.close()

    def receive(self, count):
        data = bytearray()
        deadline = time.monotonic() + 3
        while len(data) < count:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError('Response deadline exceeded')
            self.sock.settimeout(remaining)
            part = self.sock.recv(count - len(data))
            if not part:
                raise ConnectionError('Controller closed TCP connection')
            data.extend(part)
        return bytes(data)

    def read(self):
        self.sock.sendall(b'SA#')
        data = self.receive(5)
        if data[:1] != b'a' or not data[1:].isdigit():
            raise ValueError(f'Unexpected response: {data!r}')
        value = int(data[1:])
        if not 0 <= value <= 255:
            raise ValueError('Brightness out of range')
        return value

    def set(self, value):
        if type(value) is not int or not 0 <= value <= 255:
            raise ValueError('Brightness must be an integer from 0 to 255')
        self.sock.sendall(f'SA{value:04d}#'.encode('ascii'))
        if self.receive(1) != b'A':
            raise ValueError('Write not acknowledged')
        actual = self.read()
        if actual != value:
            raise ValueError(f'Readback mismatch: expected {value}, received {actual}')
        return actual

    def ramp(self, target, step=5, interval=.2):
        current = self.read()
        if type(target) is not int or not 0 <= target <= 255 or step <= 0 or interval < 0:
            raise ValueError('Invalid ramp parameters')
        while current != target:
            current += min(step, target-current) if current < target else -min(step, current-target)
            self.set(current)
            if current != target:
                time.sleep(interval)
        return current


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='192.168.1.253')
    parser.add_argument('--local-ip', default='192.168.1.240')
    parser.add_argument('--log', default=None)
    commands = parser.add_subparsers(dest='action', required=True)
    commands.add_parser('read')
    setter = commands.add_parser('set')
    setter.add_argument('value', type=int, choices=range(256), metavar='0..255')
    ramp = commands.add_parser('ramp')
    ramp.add_argument('value', type=int, choices=range(256), metavar='0..255')
    ramp.add_argument('--step', type=int, default=5)
    ramp.add_argument('--interval', type=float, default=.2)
    demo = commands.add_parser('random-demo')
    demo.add_argument('--interval', type=float, default=.7)
    args = parser.parse_args()
    result = {'timestamp': datetime.datetime.now().astimezone().isoformat(),
              'host': args.host, 'port': 8234, 'action': args.action, 'steps': []}
    controller = None
    try:
        controller = Controller(args.host, local_ip=args.local_ip)
        result['initial_brightness'] = controller.read()
        if args.action == 'read':
            pass
        elif args.action == 'set':
            controller.set(args.value)
        elif args.action == 'ramp':
            controller.ramp(args.value, args.step, args.interval)
        else:
            if args.interval < .1:
                raise ValueError('Demo interval must be at least 0.1 seconds')
            start = result['initial_brightness']
            if start < 250:
                ascending = sorted(random.sample(range(start+1, 256), min(5,255-start)))
                descending = sorted(random.sample(range(start+1, ascending[-1]), min(4,ascending[-1]-start-1)), reverse=True)
                sequence = ascending + descending + [start]
            else:
                descending = sorted(random.sample(range(0,start), 5), reverse=True)
                ascending = sorted(random.sample(range(descending[-1]+1,start), min(4,start-descending[-1]-1)))
                sequence = descending + ascending + [start]
            result['planned_values'] = sequence
            result['interval_seconds'] = args.interval
            for value in sequence:
                actual = controller.set(value)
                result['steps'].append({'timestamp': datetime.datetime.now().astimezone().isoformat(),
                                        'requested': value, 'verified': actual})
                print('Verified brightness:', actual, flush=True)
                time.sleep(args.interval)
        result['final_brightness'] = controller.read()
        result['success'] = True
    except (OSError, ValueError) as exc:
        result['success'] = False
        result['error'] = type(exc).__name__ + ': ' + str(exc)
        result['note'] = 'Stopped; no automatic retry or further write. Read device before continuing.'
    finally:
        if controller:
            controller.close()
    output = pathlib.Path(args.log) if args.log else pathlib.Path(__file__).with_name('operation_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f') + '.json')
    output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2), flush=True)
    if not result['success']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
