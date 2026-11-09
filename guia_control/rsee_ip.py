"""Read/back up USR configuration; optionally change only the saved static IP.

Default is read-only. --apply is required to write and restart the Ethernet
module to activate a new address. This script never writes LED brightness.
"""
import argparse
import ctypes
import datetime
import getpass
import ipaddress
import json
import pathlib
import socket
import time


def udp_query(local_ip, broadcast, payload, timeout=2):
    packets = []
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.bind((local_ip, 0))
        sock.sendto(payload, (broadcast, 1500))
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            sock.settimeout(max(.001, deadline - time.monotonic()))
            try:
                data, source = sock.recvfrom(4096)
            except socket.timeout:
                break
            packets.append((source, data))
    return packets


def authenticated(command, mac, username, password, parameters=b''):
    def field(text):
        data = text.encode('ascii')
        if len(data) > 5:
            raise ValueError('USR credentials support at most 5 ASCII characters plus null')
        return data.ljust(6, b'\0')
    contents = bytes([command]) + mac + field(username) + field(password) + parameters
    if len(contents) > 255:
        raise ValueError('Packet too long')
    body = bytes([len(contents)]) + contents
    return b'\xff' + body + bytes([sum(body) & 255])


def read_configuration(local_ip, broadcast, host, mac, username, password):
    packets = udp_query(local_ip, broadcast, authenticated(3, mac, username, password))
    selected = [(source, data) for source, data in packets if source[0] == host]
    main = next((data for source, data in selected if len(data) == 130), None)
    if main is None or main[53:59] != mac:
        raise ValueError('No valid 130-byte configuration from the expected IP/MAC')
    return main, selected


def read_brightness(host, local_ip):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind((local_ip, 0))
        sock.settimeout(3)
        sock.connect((host, 8234))
        sock.sendall(b'SA#')
        data = bytearray()
        deadline = time.monotonic() + 3
        while len(data) < 5:
            sock.settimeout(max(.001, deadline - time.monotonic()))
            part = sock.recv(5 - len(data))
            if not part:
                raise ConnectionError('Peer closed during brightness read')
            data.extend(part)
        if data[:1] != b'a' or not data[1:].isdigit() or int(data[1:]) > 255:
            raise ValueError('Unexpected brightness response')
        return int(data[1:])


def arp_probe(target, local_ip):
    if not hasattr(ctypes, 'windll'):
        raise RuntimeError('This IP-change helper requires Windows SendARP')
    address = int.from_bytes(socket.inet_aton(target), 'little')
    source = int.from_bytes(socket.inet_aton(local_ip), 'little')
    buffer = (ctypes.c_ubyte * 8)()
    length = ctypes.c_ulong(8)
    send_arp = ctypes.windll.iphlpapi.SendARP
    send_arp.argtypes = [ctypes.c_ulong, ctypes.c_ulong, ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulong)]
    send_arp.restype = ctypes.c_ulong
    code = send_arp(address, source, buffer, ctypes.byref(length))
    return {'code': int(code), 'mac': bytes(buffer[:length.value]).hex(':') if code == 0 else None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--current-ip', default='192.168.1.253')
    parser.add_argument('--local-ip', default='192.168.1.240')
    parser.add_argument('--prefix', type=int, default=24)
    parser.add_argument('--new-ip')
    parser.add_argument('--mac', default='38:f4:06:0e:56:93')
    parser.add_argument('--username', default='rsee')
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    if args.apply and not args.new_ip:
        parser.error('--apply requires --new-ip')
    network = ipaddress.IPv4Interface(f'{args.local_ip}/{args.prefix}').network
    broadcast = str(network.broadcast_address)
    mac = bytes.fromhex(args.mac.replace(':', '').replace('-', ''))
    if len(mac) != 6:
        parser.error('MAC must be six bytes')
    if args.new_ip:
        address = ipaddress.IPv4Address(args.new_ip)
        if address not in network or address in (network.network_address, network.broadcast_address) or args.new_ip in (args.local_ip, args.current_ip):
            parser.error('New IP must be a different usable address on the same local subnet')
    password = getpass.getpass('USR password: ')
    out = pathlib.Path(__file__).parent / ('ip_backup_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    result = {'timestamp': datetime.datetime.now().astimezone().isoformat(),
              'current_ip': args.current_ip, 'requested_ip': args.new_ip,
              'apply_requested': args.apply, 'write_sent': False}
    try:
        main, packets = read_configuration(args.local_ip, broadcast, args.current_ip, mac, args.username, password)
        for i, (source, data) in enumerate(packets):
            (out / f'before_packet_{i}.bin').write_bytes(data)
        if socket.inet_ntoa(main[9:13][::-1]) != args.current_ip or not main[3] & 128:
            raise ValueError('Saved IP/mode inconsistent: require matching static IP')
        result['brightness_before'] = read_brightness(args.current_ip, args.local_ip)
        result['backup_complete'] = True
        result['saved_uart_baud'] = int.from_bytes(main[67:71], 'little')
        result['saved_data_port'] = int.from_bytes(main[79:81], 'little')
        if args.new_ip:
            result['arp_probe'] = arp_probe(args.new_ip, args.local_ip)
            if result['arp_probe']['code'] == 0:
                raise ValueError('New IP answered ARP; do not overwrite a potentially occupied address')
            if result['arp_probe']['code'] != 67:
                raise ValueError('ARP check failed for a reason other than no response; stopping')
        if args.apply:
            basic = bytearray(main[:67])
            basic[9:13] = socket.inet_aton(args.new_ip)[::-1]
            result['requested_changed_offsets'] = [i for i, (a, b) in enumerate(zip(main[:67], basic)) if a != b]
            result['write_sent'] = True
            (out / 'result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
            replies = udp_query(args.local_ip, broadcast, authenticated(5, mac, args.username, password, basic))
            result['write_acknowledged'] = any(source[0] == args.current_ip and data == bytes.fromhex('FF01054B') for source, data in replies)
            saved, _ = read_configuration(args.local_ip, broadcast, args.current_ip, mac, args.username, password)
            expected = bytes(basic) + main[67:]
            if saved != expected:
                raise ValueError('Saved configuration differs from expected; no restart sent')
            (out / 'saved_after_write.bin').write_bytes(saved)
            result['restart_sent'] = True
            (out / 'result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
            udp_query(args.local_ip, broadcast, authenticated(2, mac, args.username, password))
            time.sleep(3)
            after, _ = read_configuration(args.local_ip, broadcast, args.new_ip, mac, args.username, password)
            (out / 'after_restart.bin').write_bytes(after)
            if after != expected:
                raise ValueError('Post-restart configuration mismatch')
            result['brightness_after'] = read_brightness(args.new_ip, args.local_ip)
            result['brightness_unchanged'] = result['brightness_after'] == result['brightness_before']
            result['active_ip_verified'] = args.new_ip
        result['success'] = True
    except (OSError, ValueError, RuntimeError) as exc:
        result['success'] = False
        result['error'] = type(exc).__name__ + ': ' + str(exc)
        result['note'] = 'Stopped without retry or automatic rollback; inspect saved state before another change.'
    (out / 'result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2))
    print('Backup:', str(out.resolve()))
    if not result['success']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
