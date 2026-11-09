#!/usr/bin/env python3
"""Short-lived stdio bridge from QML to its prestarted controller."""
import os
import selectors
import socket
import sys
import time


def main():
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        deadline = time.monotonic() + 2
        while True:
            try:
                connection.connect(sys.argv[1])
                break
            except (FileNotFoundError, ConnectionRefusedError):
                if time.monotonic() >= deadline:
                    raise ValueError('Prestarted picker controller is unavailable.')
                time.sleep(0.01)
        with selectors.DefaultSelector() as selector:
            selector.register(sys.stdin.fileno(), selectors.EVENT_READ)
            selector.register(connection, selectors.EVENT_READ)
            while True:
                for key, _ in selector.select():
                    if key.fileobj is connection:
                        data = connection.recv(65536)
                        if not data:
                            return
                        sys.stdout.buffer.write(data)
                        sys.stdout.buffer.flush()
                    else:
                        data = os.read(sys.stdin.fileno(), 65536)
                        if data:
                            connection.sendall(data)
                        else:
                            selector.unregister(sys.stdin.fileno())
                            connection.shutdown(socket.SHUT_WR)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, IndexError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        sys.exit(1)
