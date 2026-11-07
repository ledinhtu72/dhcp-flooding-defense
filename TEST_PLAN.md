# KẾ HOẠCH KIỂM THỬ & NGHIỆM THU (`TEST_PLAN.md`)

## 1. Danh mục kiểm thử tự động & thủ công

| Mã KT | Nội dung kiểm thử | Lệnh thực hiện | Kết quả mong đợi |
| :--- | :--- | :--- | :--- |
| **TC-01** | Khởi động Labtainer 4 container | `labtainer -r dhcp-flooding-defense` | 4 terminal (`dhcpserver`, `dhcprelay`, `attacker`, `client`) mở thành công |
| **TC-02** | Baseline DHCP & PCAP | `start-capture.sh normal_dhcp` -> `client-test.sh baseline` -> `stop-capture.sh` | Client nhận IP `10.10.0.100`, file `normal_dhcp.pcapng` có đủ 4 gói DORA |
| **TC-03** | Flooding trước khi bật Firewall | `start-capture.sh attack_before` -> `sudo attack-controlled.sh --level medium --starve` -> `stop-capture.sh` | File `attack_before.pcapng` ghi nhận >100 gói DHCP; Pool trên Server bị chiếm dụng |
| **TC-04** | Bật `nftables` & Flooding sau phòng thủ | `reset-leases.sh` -> `firewall-enable.sh` -> `start-capture.sh attack_after` -> `sudo attack-controlled.sh --level medium --starve` -> `client-test.sh after_defense` -> `stop-capture.sh` -> `firewall-status.sh` | Counter `dhcp_flood_drop` tăng cao (>70 gói bị chặn); Client hợp lệ nhận IP thành công (< 0.5s) |
| **TC-05** | Phân tích Zeek + Python | `analyze.sh` | Sinh đủ `dhcp.log`, CSV, JSON và báo cáo Markdown so sánh 3 kịch bản |
| **TC-06** | Chấm điểm tự động `checkwork` | `checkwork dhcp-flooding-defense` | Toàn bộ 6/6 goals đạt trạng thái **`Y`** |
| **TC-07** | Kiểm tra tương thích các lab cũ | Kiểm tra image `dhcp-lab.*` | Không ảnh hưởng `dhcp-flooding`, `dhcp-release-spoofing`, `dhcp-flooding-snort`, `rogue-dhcp-server` |

