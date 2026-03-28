#!/usr/bin/python3
import os
import socket
import hashlib
import struct

def generate_license():
    # Detect hostname
    hostname = os.environ.get("IOL_HOSTNAME")
    if not hostname:
        hostname = socket.gethostname()
    
    # Detect hostid from the system (reflects current hostname/IP identity)
    hostid_str = os.popen("hostid").read().strip()
    try:
        hostid = int(hostid_str, 16)
    except:
        hostid = 0
    
    ioukey = hostid
    for x in hostname:
        ioukey = ioukey + ord(x)
    
    # Original Cisco IOU License Generator logic
    iouPad1 = b'\x4B\x58\x21\x81\x56\x7B\x0D\xF3\x21\x43\x9B\x7E\xAC\x1D\xE6\x8A'
    iouPad2 = b'\x80' + 39*b'\0'
    
    # Note: Using '!i' (signed big-endian) to match the original generator
    md5input = iouPad1 + iouPad2 + struct.pack('!i', ioukey) + iouPad1
    license_key = hashlib.md5(md5input).hexdigest()[:16]
    
    print("[license]")
    print(f"{hostname} = {license_key};")

if __name__ == "__main__":
    generate_license()
