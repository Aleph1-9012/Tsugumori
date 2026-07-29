#!/usr/bin/env python3
import socket, sys, json

def main():
    if len(sys.argv) < 3:
        print("ERR usage: mpv_ctl.py <socket_path> <json_command>")
        sys.exit(1)
    sock_path = sys.argv[1]
    cmd_json = sys.argv[2]
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(2)
        s.connect(sock_path)
        s.sendall((cmd_json + "\n").encode())
        s.close()
        print("OK")
    except Exception as e:
        print("ERR " + str(e))
        sys.exit(2)

if __name__ == "__main__":
    main()
