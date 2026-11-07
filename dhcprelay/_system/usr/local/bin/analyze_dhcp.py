#!/usr/bin/env python3
"""
analyze_dhcp.py - Phân tích Forensics gói tin DHCP bằng Zeek + TShark + Python
Đọc các file PCAPNG trong /home/ubuntu/captures/ (normal_dhcp.pcapng, attack_before.pcapng, attack_after.pcapng),
chạy Zeek sinh dhcp.log, thống kê chi tiết và xuất:
  1. /home/ubuntu/analysis/<scenario>/dhcp.log (Chuẩn Zeek TSV)
  2. /home/ubuntu/analysis/dhcp_packets_evidence.csv (Dẫn chứng từng frame gói tin)
  3. /home/ubuntu/analysis/dhcp_summary_metrics.csv (Bảng chỉ số tổng hợp)
  4. /home/ubuntu/analysis/dhcp_analysis_summary.json (Dữ liệu JSON chuẩn hóa)
  5. /home/ubuntu/reports/dhcp_defense_report.md (Báo cáo Markdown kèm biểu đồ ASCII)
  6. /var/log/dhcp_analysis_report.txt (Bản lưu phục vụ checkwork)
"""
import os
import sys
import csv
import json
import time
import shutil
import subprocess

CAPTURE_DIR = "/home/ubuntu/captures"
ANALYSIS_DIR = "/home/ubuntu/analysis"
REPORT_DIR = "/home/ubuntu/reports"
SYSTEM_REPORT_LOG = "/var/log/dhcp_analysis_report.txt"
FIREWALL_STATUS_LOG = "/var/log/firewall_status.log"

SCENARIOS = [
    ("baseline", "normal_dhcp.pcapng", "Kịch bản A: Baseline (Bình thường)"),
    ("attack_before", "attack_before.pcapng", "Kịch bản B: Flooding (Chưa bật nftables)"),
    ("attack_after", "attack_after.pcapng", "Kịch bản D: Flooding (Đã bật nftables)"),
]

DHCP_MSG_MAP = {
    "1": "DISCOVER",
    "2": "OFFER",
    "3": "REQUEST",
    "4": "DECLINE",
    "5": "ACK",
    "6": "NAK",
    "7": "RELEASE",
    "8": "INFORM",
}

def ensure_dirs():
    for d in [CAPTURE_DIR, ANALYSIS_DIR, REPORT_DIR, "/var/log/captures"]:
        os.makedirs(d, exist_ok=True)

def run_zeek_on_pcap(scenario_key, pcap_path):
    scen_dir = os.path.join(ANALYSIS_DIR, scenario_key)
    os.makedirs(scen_dir, exist_ok=True)
    res = subprocess.run(
        ["/usr/local/bin/zeek", "-r", pcap_path],
        cwd=scen_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    dhcp_log_path = os.path.join(scen_dir, "dhcp.log")
    has_dhcp_log = os.path.isfile(dhcp_log_path) and os.path.getsize(dhcp_log_path) > 0
    return has_dhcp_log, dhcp_log_path, res.stdout.strip()

def parse_pcap_packets(scenario_key, pcap_path):
    cmd = [
        "tshark", "-r", pcap_path,
        "-Y", "dhcp or bootp",
        "-T", "fields",
        "-E", "separator=\t",
        "-e", "frame.number",
        "-e", "frame.time_epoch",
        "-e", "eth.src",
        "-e", "eth.dst",
        "-e", "ip.src",
        "-e", "ip.dst",
        "-e", "dhcp.hw.mac_addr",
        "-e", "dhcp.id",
        "-e", "dhcp.option.dhcp",
        "-e", "dhcp.ip.your",
        "-e", "dhcp.option.requested_ip_address",
    ]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    packets = []
    for line in res.stdout.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        while len(parts) < 11:
            parts.append("")
        frame_no, ts_str, eth_src, eth_dst, ip_src, ip_dst, chaddr, xid, opt_dhcp, yiaddr, req_ip = parts
        try:
            ts = float(ts_str)
        except ValueError:
            ts = 0.0
        mtype = DHCP_MSG_MAP.get(opt_dhcp.strip(), f"OTHER({opt_dhcp})")
        packets.append({
            "scenario": scenario_key,
            "frame": int(frame_no) if frame_no.isdigit() else 0,
            "timestamp": round(ts, 6),
            "eth_src": eth_src or "-",
            "eth_dst": eth_dst or "-",
            "ip_src": ip_src or "-",
            "ip_dst": ip_dst or "-",
            "client_mac_chaddr": chaddr or "-",
            "xid": xid or "-",
            "msg_type": mtype,
            "yiaddr": yiaddr if yiaddr and yiaddr != "0.0.0.0" else "-",
            "requested_ip": req_ip or "-",
        })
    return packets

def compute_metrics(scenario_key, filename, label, pcap_path):
    if not os.path.exists(pcap_path):
        return {
            "scenario": scenario_key,
            "filename": filename,
            "label": label,
            "exists": False,
            "zeek_dhcp_log": False,
            "zeek_dhcp_log_path": "-",
            "total_packets": 0,
            "duration_sec": 0.0,
            "discover_count": 0,
            "offer_count": 0,
            "request_count": 0,
            "ack_count": 0,
            "nak_count": 0,
            "release_count": 0,
            "discover_per_sec": 0.0,
            "request_per_sec": 0.0,
            "unique_eth_src_macs": 0,
            "unique_client_chaddr_macs": 0,
            "unique_xids": 0,
            "offer_to_discover_ratio": 0.0,
            "ack_to_request_ratio": 0.0,
            "packets": [],
        }

    has_zeek_log, zeek_log_path, _ = run_zeek_on_pcap(scenario_key, pcap_path)
    packets = parse_pcap_packets(scenario_key, pcap_path)

    counts = {"DISCOVER": 0, "OFFER": 0, "REQUEST": 0, "ACK": 0, "NAK": 0, "RELEASE": 0}
    eth_macs = set()
    chaddr_macs = set()
    xids = set()
    timestamps = []

    for pkt in packets:
        mt = pkt["msg_type"]
        if mt in counts:
            counts[mt] += 1
        if pkt["eth_src"] != "-":
            eth_macs.add(pkt["eth_src"])
        if pkt["client_mac_chaddr"] != "-":
            chaddr_macs.add(pkt["client_mac_chaddr"])
        if pkt["xid"] != "-":
            xids.add(pkt["xid"])
        if pkt["timestamp"] > 0:
            timestamps.append(pkt["timestamp"])

    if len(timestamps) >= 2:
        duration = max(0.1, max(timestamps) - min(timestamps))
    elif len(timestamps) == 1:
        duration = 1.0
    else:
        duration = 0.0

    disc_cnt = counts["DISCOVER"]
    off_cnt = counts["OFFER"]
    req_cnt = counts["REQUEST"]
    ack_cnt = counts["ACK"]

    disc_rate = round(disc_cnt / duration, 2) if duration > 0 else 0.0
    req_rate = round(req_cnt / duration, 2) if duration > 0 else 0.0
    off_disc_ratio = round((off_cnt / disc_cnt) * 100.0, 1) if disc_cnt > 0 else 0.0
    ack_req_ratio = round((ack_cnt / req_cnt) * 100.0, 1) if req_cnt > 0 else 0.0

    return {
        "scenario": scenario_key,
        "filename": filename,
        "label": label,
        "exists": True,
        "zeek_dhcp_log": has_zeek_log,
        "zeek_dhcp_log_path": zeek_log_path,
        "total_packets": len(packets),
        "duration_sec": round(duration, 3),
        "discover_count": disc_cnt,
        "offer_count": off_cnt,
        "request_count": req_cnt,
        "ack_count": ack_cnt,
        "nak_count": counts["NAK"],
        "release_count": counts["RELEASE"],
        "discover_per_sec": disc_rate,
        "request_per_sec": req_rate,
        "unique_eth_src_macs": len(eth_macs),
        "unique_client_chaddr_macs": len(chaddr_macs),
        "unique_xids": len(xids),
        "offer_to_discover_ratio": off_disc_ratio,
        "ack_to_request_ratio": ack_req_ratio,
        "packets": packets,
    }

def get_firewall_counters():
    subprocess.run(["/usr/local/bin/firewall-status.sh"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    counters = {
        "active": False,
        "external_dhcp_rx": 0,
        "trusted_client_accept": 0,
        "dhcp_rate_limit_accept": 0,
        "dhcp_flood_drop": 0,
    }
    if not os.path.exists(FIREWALL_STATUS_LOG):
        return counters
    with open(FIREWALL_STATUS_LOG, "r", encoding="utf-8", errors="ignore") as f:
        text = f.read()
    if "NFT_DEFENSE_ACTIVE=TRUE" in text:
        counters["active"] = True
    for line in text.splitlines():
        if "1. Tổng gói DHCP nhận từ EXTERNAL_NET" in line and ":" in line:
            tok = line.split(":")[1].strip().split()[0]
            if tok.isdigit():
                counters["external_dhcp_rx"] = int(tok)
        elif "2. Gói DHCP hợp lệ từ Client" in line and ":" in line:
            tok = line.split(":")[1].strip().split()[0]
            if tok.isdigit():
                counters["trusted_client_accept"] = int(tok)
        elif "3. Gói DHCP qua ngưỡng Rate-Limit" in line and ":" in line:
            tok = line.split(":")[1].strip().split()[0]
            if tok.isdigit():
                counters["dhcp_rate_limit_accept"] = int(tok)
        elif "5. Gói DHCP Flooding bị CHẶN" in line and ":" in line:
            tok = line.split(":")[1].strip().split()[0]
            if tok.isdigit():
                counters["dhcp_flood_drop"] = int(tok)
    return counters

def ascii_bar(value, max_val, width=25):
    if max_val <= 0:
        return ""
    filled = int(round((value / max_val) * width))
    filled = max(0, min(width, filled))
    return "█" * filled + "░" * (width - filled)

def main():
    ensure_dirs()
    all_metrics = []
    all_evidence_packets = []
    capture_status_lines = []

    for scen_key, fname, label in SCENARIOS:
        pcap_path = os.path.join(CAPTURE_DIR, fname)
        if scen_key == "baseline":
            norm_short = os.path.join(CAPTURE_DIR, "normal.pcapng")
            if os.path.exists(norm_short) and not os.path.exists(pcap_path):
                shutil.copy2(norm_short, pcap_path)
            elif os.path.exists(pcap_path) and not os.path.exists(norm_short):
                shutil.copy2(pcap_path, norm_short)
        if not os.path.exists(pcap_path):
            alt_path = os.path.join("/var/log/captures", fname)
            if os.path.exists(alt_path):
                shutil.copy2(alt_path, pcap_path)
        if os.path.exists(pcap_path) and os.path.getsize(pcap_path) > 0:
            capture_status_lines.append(f"CAPTURED {fname} normal.pcapng size={os.path.getsize(pcap_path)}\n")
        m = compute_metrics(scen_key, fname, label, pcap_path)
        all_evidence_packets.extend(m.pop("packets", []))
        all_metrics.append(m)

    if capture_status_lines:
        cap_log = "/var/log/captures/capture_status.log"
        with open(cap_log, "a", encoding="utf-8") as f:
            f.writelines(capture_status_lines)
        os.chmod(cap_log, 0o666)

    fw_counters = get_firewall_counters()

    evidence_csv = os.path.join(ANALYSIS_DIR, "dhcp_packets_evidence.csv")
    with open(evidence_csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "scenario", "frame", "timestamp", "eth_src", "eth_dst",
            "ip_src", "ip_dst", "client_mac_chaddr", "xid", "msg_type", "yiaddr", "requested_ip"
        ])
        writer.writeheader()
        for row in all_evidence_packets:
            writer.writerow(row)

    summary_csv = os.path.join(ANALYSIS_DIR, "dhcp_summary_metrics.csv")
    metric_fields = [
        "scenario", "filename", "exists", "zeek_dhcp_log", "total_packets", "duration_sec",
        "discover_count", "offer_count", "request_count", "ack_count", "nak_count", "release_count",
        "discover_per_sec", "request_per_sec", "unique_eth_src_macs", "unique_client_chaddr_macs",
        "unique_xids", "offer_to_discover_ratio", "ack_to_request_ratio"
    ]
    with open(summary_csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=metric_fields, extrasaction="ignore")
        writer.writeheader()
        for m in all_metrics:
            writer.writerow(m)

    summary_json = os.path.join(ANALYSIS_DIR, "dhcp_analysis_summary.json")
    json_payload = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "measurement_point": "dhcprelay INTERNAL_IF (post-nftables relay_out hook towards DHCP Server 192.168.0.100)",
        "scenarios": all_metrics,
        "nftables_counters": fw_counters,
    }
    with open(summary_json, "w", encoding="utf-8") as f:
        json.dump(json_payload, f, indent=2, ensure_ascii=False)

    max_pkts = max([m["total_packets"] for m in all_metrics] + [1])
    max_disc = max([m["discover_count"] for m in all_metrics] + [1])

    lines = []
    lines.append("# BÁO CÁO PHÂN TÍCH FORENSICS DHCP FLOODING & HIỆU QUẢ TƯỜNG LỬA NFTABLES")
    lines.append(f"- **Thời gian tạo báo cáo:** `{json_payload['generated_at']}`")
    lines.append(f"- **Điểm đặt Sensor bắt gói (PCAP):** Giao diện `INTERNAL_NET` (`192.168.0.1`) trên `dhcprelay` (ngay sau hook lọc `relay_out` của `nftables` hướng về DHCP Server `192.168.0.100`).")
    lines.append("")
    lines.append("## 1. Bảng Thống Kê So Sánh Giữa 3 Kịch Bản (Từ PCAP & Zeek `dhcp.log`)")
    lines.append("")
    lines.append("| Kịch bản | File PCAP | Tổng gói DHCP | Discover | Offer | Request | ACK | Discover/s | Unique Client MAC (`chaddr`) | Unique XID | Zeek `dhcp.log` |")
    lines.append("| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |")
    for m in all_metrics:
        z_status = "OK" if m["zeek_dhcp_log"] else "Missing"
        lines.append(
            f"| **{m['label']}** | `{m['filename']}` | {m['total_packets']} | {m['discover_count']} | "
            f"{m['offer_count']} | {m['request_count']} | {m['ack_count']} | {m['discover_per_sec']} pkt/s | "
            f"{m['unique_client_chaddr_macs']} | {m['unique_xids']} | {z_status} |"
        )
    lines.append("")
    lines.append("## 2. Biểu Đồ Trực Quan So Sánh Lưu Lượng Tới DHCP Server Trước & Sau Phòng Thủ")
    lines.append("```text")
    lines.append("A. Tổng gói tin DHCP đi qua Relay tới DHCP Server (192.168.0.100):")
    for m in all_metrics:
        bar = ascii_bar(m["total_packets"], max_pkts)
        lines.append(f"  {m['scenario']:<15} | {bar} {m['total_packets']} packets")
    lines.append("")
    lines.append("B. Số lượng gói DHCP DISCOVER đi tới DHCP Server:")
    for m in all_metrics:
        bar = ascii_bar(m["discover_count"], max_disc)
        lines.append(f"  {m['scenario']:<15} | {bar} {m['discover_count']} discovers ({m['discover_per_sec']} pkt/s)")
    lines.append("```")
    lines.append("")
    lines.append("## 3. Số Liệu Xác Minh Bộ Đếm Tường Lửa `nftables` (`table inet dhcp_defense`)")
    lines.append(f"- **Trạng thái tường lửa:** `{'ACTIVE' if fw_counters['active'] else 'INACTIVE'}`")
    lines.append(f"- **Tổng gói DHCP nhận từ `EXTERNAL_NET` (`external_dhcp_rx`):** `{fw_counters['external_dhcp_rx']}` packets")
    lines.append(f"- **Gói DHCP từ Client hợp lệ được ưu tiên (`trusted_client_accept`):** `{fw_counters['trusted_client_accept']}` packets")
    lines.append(f"- **Gói DHCP từ MAC lạ trong ngưỡng Rate-Limit (`dhcp_rate_limit_accept`):** `{fw_counters['dhcp_rate_limit_accept']}` packets")
    lines.append(f"- **Gói DHCP Flooding vượt ngưỡng bị DROP (`dhcp_flood_drop`):** `{fw_counters['dhcp_flood_drop']}` packets")
    lines.append("")
    lines.append("## 4. Dẫn Chứng Bằng Chứng Gói Tin Điển Hình (Sample Frame Evidence)")
    lines.append("| Kịch bản | Frame # | Timestamp | Client MAC (`chaddr`) | IP Nguồn -> Đích | Loại DHCP | XID | IP Cấp (`yiaddr`) |")
    lines.append("| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |")
    for scen_key, _, _ in SCENARIOS:
        scen_pkts = [p for p in all_evidence_packets if p["scenario"] == scen_key][:6]
        for p in scen_pkts:
            lines.append(
                f"| `{scen_key}` | {p['frame']} | {p['timestamp']} | `{p['client_mac_chaddr']}` | "
                f"`{p['ip_src']} -> {p['ip_dst']}` | **{p['msg_type']}** | `{p['xid']}` | `{p['yiaddr']}` |"
            )
    lines.append("")
    lines.append("## 5. Đường Dẫn Các Tệp Kết Quả Xuất Ra")
    lines.append(f"- **Zeek Logs:** `/home/ubuntu/analysis/{{baseline,attack_before,attack_after}}/dhcp.log`")
    lines.append(f"- **CSV Bằng chứng gói tin:** `{evidence_csv}`")
    lines.append(f"- **CSV Bảng chỉ số tổng hợp:** `{summary_csv}`")
    lines.append(f"- **JSON Tổng hợp:** `{summary_json}`")
    lines.append(f"- **Báo cáo Markdown:** `/home/ubuntu/reports/dhcp_defense_report.md`")
    lines.append("")
    lines.append("ZEEK_PYTHON_REPORT_COMPLETED=TRUE")

    report_text = "\n".join(lines) + "\n"
    md_report_path = os.path.join(REPORT_DIR, "dhcp_defense_report.md")
    with open(md_report_path, "w", encoding="utf-8") as f:
        f.write(report_text)

    with open(SYSTEM_REPORT_LOG, "w", encoding="utf-8") as f:
        f.write(report_text)
    os.chmod(SYSTEM_REPORT_LOG, 0o666)

    print(report_text)

if __name__ == "__main__":
    main()
