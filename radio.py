#!/usr/bin/python3

import argparse
import sys
import telnetlib


def remove_last_line_from_string(s):
    return s[:s.rfind('\n')]


def send_tn_command(port, command, parameters=""):
    try:
        tn = telnetlib.Telnet(host="127.0.0.1", port=port)
    except Exception:
        sys.exit("Failed to connect to telnet server, is liquidsoap running ?")

    tn.write((command + " " + parameters + "\n").encode('ascii'))
    tn.write(b"exit\n")

    return remove_last_line_from_string(tn.read_until(b"\nEND").decode('ascii'))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("port", help="telnet port")
    parser.add_argument("command", help="<command>")
    parser.add_argument("parameter", nargs='?', default="", help="command parameter")

    args = parser.parse_args()

    print(send_tn_command(args.port, args.command, args.parameter))
