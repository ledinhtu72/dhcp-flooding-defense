#!/usr/bin/env bash
# =============================================================================
# analyze.sh - Chạy phân tích Zeek + Python trên các file PCAP đã thu thập
# =============================================================================
set -euo pipefail
python3 /usr/local/bin/analyze_dhcp.py "$@"

