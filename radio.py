#!/usr/bin/python3

import argparse
import telnetlib

parser = argparse.ArgumentParser()
parser.add_argument("action", help="setlivesource <source>")
parser.add_argument("livesource", nargs='?', default="", help="livesource to set")

args = parser.parse_args()

tn = telnetlib.Telnet(host="127.0.0.1", port=8500)

if args.action == "setlivesource":
  if args.livesource != "":
    tn.write(("setlivesource " + str(args.livesource) + "\n").encode('ascii'))
  else:
    print("Error: you need to provide a livesource")

if args.action == "getlivesource":
  tn.write(b"getlivesource\n")

tn.write(b"exit\n")

print(tn.read_some().decode('ascii'))
