# DHCP Flooding Attack and Defense Using nftables Firewall (`dhcp-flooding-defense`)

- **Tên bài Labtainer:** `dhcp-flooding-defense`
- **Tên dự án:** DHCP Flooding Attack and Defense Using nftables Firewall
- **Phiên bản phát hành:** `v1.0.0`
- **Tương thích nền tảng:** Labtainers `v1.4.4n` | Docker `>= 24.x` | Ubuntu `20.04 / 22.04 / 24.04 LTS`

---

## 1. Giới Thiệu Bài Lab

**`dhcp-flooding-defense`** là bài thực hành Labtainers hoàn chỉnh mô phỏng cuộc tấn công làm ngập lụt dịch vụ cấp phát địa chỉ IP động (**DHCP Flooding / Starvation**) trong kiến trúc mạng doanh nghiệp phân tách hai phân đoạn (**Dual-Subnet**) qua bộ trung chuyển **DHCP Relay**, kết hợp:
1. **Phòng thủ chủ động tại điểm nghẽn lưu lượng (`dhcprelay`) bằng tường lửa nhân Linux `nftables`**: Ưu tiên máy trạm hợp lệ (`trusted_clients`) và giới hạn tốc độ (`rate-limit`) kết hợp bộ đếm (`counter`) chặn đứng các gói tin lũ.
2. **Thu thập bằng chứng mạng (Packet Capture) bằng `TShark` / `Wireshark`**: Lưu trữ 3 tệp PCAPNG chuẩn (`normal.pcapng`, `attack_before.pcapng`, `attack_after.pcapng`).
3. **Phân tích điều tra số (Network Forensics) bằng `Zeek` và `Python`**: Trích xuất `dhcp.log` chuẩn Zeek TSV, thống kê định lượng tốc độ gói tin (`pkt/s`), số lượng MAC giả mạo (`chaddr`), Transaction ID (`xid`) và số gói bị chặn bởi `nftables`.

---

## 2. Mục Tiêu Học Tập Và Thực Nghiệm

Sau khi hoàn thành bài lab, người học nắm vững:
- Cơ chế hoạt động 4 bước của DHCP (`DISCOVER -> OFFER -> REQUEST -> ACK`) đi qua **DHCP Relay (`giaddr`)** giữa hai subnet khác nhau.
- Bản chất kỹ thuật của tấn công **DHCP Flooding**: Sử dụng hàng loạt khung tin `DHCPDISCOVER` với địa chỉ MAC giả mạo ngẫu nhiên để làm quá tải hàng đợi xử lý của Relay/Server và làm cạn kiệt dải IP (`Pool Exhaustion`).
- Lý do kỹ thuật khi đặt tường lửa **`nftables`** tại hook `output` (`chain relay_out`) và hook `ingress` (`table netdev`) trên `dhcprelay` để lọc cả lưu lượng nhận từ `AF_PACKET` raw socket của `isc-dhcp-relay`.
- Kỹ năng sử dụng `tshark`, `wireshark`, `zeek`, `nft`, và `python3` để thu thập, phân tích và chứng minh hiệu quả phòng thủ bằng số liệu thực nghiệm.

---

## 3. Sơ Đồ Mạng (Dual-Subnet Topology)

Bài lab kế thừa kiến trúc Dual-Subnet chuẩn từ `labtainer-network-base`:

```text
  [EXTERNAL_NET: 10.10.0.0/24]                    [INTERNAL_NET: 192.168.0.0/24]
 ┌────────────────────────────┐                  ┌──────────────────────────────┐
 │ attacker (10.10.0.20)      │                  │ dhcpserver (192.168.0.100)   │
 │  - MAC: 02:42:0a:0a:00:14  ├───┐          ┌───┤  - MAC: 02:42:c0:a8:00:64    │
 │  - yersinia / scapy        │   │          │   │  - isc-dhcp-server           │
 └────────────────────────────┘   │          │   │  - Pool: 10.10.0.100 - .130  │
                                  ▼          ▼   └──────────────────────────────┘
 ┌────────────────────────────┐ ┌──────────────┐
 │ client (Dynamic DHCP)      │ │  dhcprelay   │  <-- ĐIỂM CHẶN & GIÁM SÁT TRUNG TÂM
 │  - MAC: 02:42:0a:0a:00:32  ├─► eth0:10.10.0.1│  - isc-dhcp-relay
 │  - dhclient                │ │ eth1:192.168.0.1 - Tường lửa: nftables (v1.0.9)
 └────────────────────────────┘ └──────────────┘  - Sensor: TShark / Wireshark
                                                  - Phân tích: Zeek + Python3
```

---

## 4. Danh Sách Container Trong Bài Lab

Bài lab khởi chạy **4 container** tương ứng với **4 cửa sổ terminal tương tác**:

| Container | Mạng kết nối | Địa chỉ IP | Địa chỉ MAC | Docker Image (`REGISTRY zeus183`) | Vai trò chính |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`dhcpserver`** | `INTERNAL_NET` (`192.168.0.0/24`) | `eth0`: `192.168.0.100` | `02:42:c0:a8:00:64` | `zeus183/dhcp-flooding-defense.dhcpserver.student:latest` | Máy chủ ISC DHCP cấp phát dải `10.10.0.100 - 10.10.0.130` (31 IP) |
| **`dhcprelay`** | `EXTERNAL_NET` & `INTERNAL_NET` | `eth0`: `10.10.0.1`<br>`eth1`: `192.168.0.1` | `02:42:0a:0a:00:01`<br>`02:42:c0:a8:00:01` | `zeus183/dhcp-flooding-defense.dhcprelay.student:latest` | Chuyển tiếp DHCP, tường lửa `nftables`, bắt gói `TShark/Wireshark`, phân tích `Zeek/Python` |
| **`attacker`** | `EXTERNAL_NET` (`10.10.0.0/24`) | `eth0`: `10.10.0.20` | `02:42:0a:0a:00:14` | `zeus183/dhcp-flooding-defense.attacker.student:latest` | Máy Kali mô phỏng tấn công DHCP Flooding có kiểm soát (`scapy` / `yersinia`) |
| **`client`** | `EXTERNAL_NET` (`10.10.0.0/24`) | `eth0`: *Nhận IP động* | `02:42:0a:0a:00:32` | `zeus183/dhcp-flooding-defense.client.student:latest` | Máy trạm Ubuntu hợp lệ xin cấp phát IP qua DHCP Relay |

---

## 5. Yêu Cầu Hệ Thống

- **Hệ điều hành máy ảo:** Ubuntu 20.04 / 22.04 / 24.04 LTS (VMware hoặc VirtualBox).
- **Cấu hình khuyến nghị:** 2–4 vCPU, RAM 4–8 GB, dung lượng trống tối thiểu 5 GB.
- **Phần mềm nền tảng:** Docker Engine và bộ công cụ Labtainers đã cài đặt (`$LABTAINER_DIR` được thiết lập).
- **Không yêu cầu GPU, không sử dụng AI/LLM hoặc dịch vụ đám mây bên ngoài.**

---

## 6. Hướng Dẫn Import Bài Lab Từ GitHub Bằng `imodule`

Trên bất kỳ máy ảo Labtainers nào có kết nối mạng, mở terminal và chạy lệnh `imodule` chuẩn của Labtainers để tải và cài đặt gói `dhcp-flooding-defense.tar`:

```bash
# Cách 1: Import trực tiếp từ GitHub Releases (Khuyến nghị)
imodule https://github.com/ledinhtu72/dhcp-flooding-defense/releases/download/v1.0.0/dhcp-flooding-defense.tar

# Cách 2: Hoặc import trực tiếp từ nhánh main trên GitHub
imodule https://raw.githubusercontent.com/ledinhtu72/dhcp-flooding-defense/main/dhcp-flooding-defense.tar
```

Nếu bạn đã tải sẵn file `dhcp-flooding-defense.tar` về máy cục bộ (ví dụ tại `/tmp/dhcp-flooding-defense.tar`), bạn có thể import ngoại tuyến bằng:
```bash
imodule file:///tmp/dhcp-flooding-defense.tar
```

---

## 7. Hướng Dẫn Chạy Bài Lab Bằng `labtainer`

Sau khi chạy `imodule`, khởi động ngay bài lab bằng lệnh:
```bash
labtainer dhcp-flooding-defense
```
*(Nếu muốn khởi tạo lại bài lab mới từ đầu và xóa kết quả phiên trước, dùng: `labtainer -r dhcp-flooding-defense`).*

Labtainers sẽ tự động tải 4 Docker image từ tài khoản Docker Hub `zeus183` (nếu chưa có sẵn trên máy) và mở **4 cửa sổ terminal**: `dhcpserver`, `dhcprelay`, `attacker`, và `client`.

---

## 8. Hướng Dẫn Thực Hiện Mô Phỏng DHCP Flooding

1. **Kiểm tra cấp phát bình thường (Baseline) trên `client`:**
   ```bash
   dhclient -r eth0
   dhclient -v eth0
   ip addr show eth0
   ```
2. **Thực hiện tấn công DHCP Flooding có kiểm soát trên `attacker`:**
   - **Cách 1 (Khuyến nghị - Dùng Scapy CLI có giới hạn số gói và tốc độ):**
     ```bash
     # Gửi 60 gói DHCPDISCOVER với MAC ngẫu nhiên, khoảng cách 0.04s (~25 gói/giây)
     python3 /home/ubuntu/dhcp_flood_scapy.py 60 0.04 discover
     ```
     *(Hoặc sử dụng công cụ điều khiển nhiều mức độ: `attack-controlled.sh --level medium --timeout 10`, dừng khẩn cấp bằng `Ctrl+C` hoặc `attack-stop.sh`).*
   - **Cách 2 (Dùng `yersinia` có giới hạn thời gian `timeout`):**
     ```bash
     timeout 3 yersinia dhcp -attack 1 -interface eth0
     ```

---

## 9. Hướng Dẫn Bật / Tắt Và Kiểm Tra Tường Lửa `nftables`

Toàn bộ cấu hình tường lửa nằm tại [`/etc/nftables_dhcp_defense.nft`](file:///home/student/labtainer/trunk/labs/dhcp-flooding-defense/firewall/nftables_dhcp_defense.nft) trên container **`dhcprelay`**.

1. **Xem nội dung quy tắc và kích hoạt tường lửa `nftables` trên `dhcprelay`:**
   ```bash
   cat /etc/nftables_dhcp_defense.nft
   nft -f /etc/nftables_dhcp_defense.nft
   ```
   *(Hoặc chạy lệnh hỗ trợ: `firewall-enable.sh`).*
2. **Xem trạng thái tường lửa và bộ đếm gói tin (`counter`) trên `dhcprelay`:**
   ```bash
   nft list table netdev dhcp_defense_ingress
   nft list table inet dhcp_defense
   ```
   *(Hoặc chạy: `firewall-status.sh`).*
3. **Tắt tường lửa và khôi phục trạng thái ban đầu trên `dhcprelay` (không ảnh hưởng các bảng NAT của Docker):**
   ```bash
   nft delete table inet dhcp_defense
   nft delete table netdev dhcp_defense_ingress
   ```
   *(Hoặc chạy: `firewall-disable.sh`).*

---

## 10. Hướng Dẫn Thu Thập Gói Tin Với Wireshark / TShark

Trên terminal **`dhcprelay`**, tạo thư mục lưu trữ và thu thập 3 tệp PCAPNG chuẩn trên giao diện `eth1` (`192.168.0.1` hướng về `dhcpserver`):

```bash
mkdir -p -m 777 /home/ubuntu/captures /home/ubuntu/analysis /home/ubuntu/reports

# 1. Thu thập lưu lượng chuẩn (Baseline) khi Client xin IP bình thường:
tshark -i eth1 -f "udp port 67 or udp port 68" -a duration:15 -w /home/ubuntu/captures/normal.pcapng

# 2. Thu thập lưu lượng khi tấn công DHCP Flooding CHƯA bật nftables:
tshark -i eth1 -f "udp port 67 or udp port 68" -a duration:15 -w /home/ubuntu/captures/attack_before.pcapng

# 3. Thu thập lưu lượng khi tấn công DHCP Flooding ĐÃ bật nftables:
tshark -i eth1 -f "udp port 67 or udp port 68" -a duration:20 -w /home/ubuntu/captures/attack_after.pcapng
```

Đọc nhanh tệp PCAP bằng `tshark` hoặc mở giao diện đồ họa `wireshark`:
```bash
tshark -r /home/ubuntu/captures/normal.pcapng
tshark -r /home/ubuntu/captures/attack_before.pcapng | head -n 25
tshark -r /home/ubuntu/captures/attack_after.pcapng
wireshark /home/ubuntu/captures/attack_after.pcapng &
```

---

## 11. Hướng Dẫn Phân Tích Gói Tin Bằng Zeek Và Python

Trên terminal **`dhcprelay`**, phân tích cả 3 tệp PCAPNG bằng `zeek` để trích xuất tệp `dhcp.log` chuẩn Zeek TSV:

```bash
mkdir -p /home/ubuntu/analysis/baseline /home/ubuntu/analysis/attack_before /home/ubuntu/analysis/attack_after
cd /home/ubuntu/analysis/baseline && zeek -C -r /home/ubuntu/captures/normal.pcapng
cd /home/ubuntu/analysis/attack_before && zeek -C -r /home/ubuntu/captures/attack_before.pcapng
cd /home/ubuntu/analysis/attack_after && zeek -C -r /home/ubuntu/captures/attack_after.pcapng

# Xem nội dung dhcp.log
cat /home/ubuntu/analysis/baseline/dhcp.log
cat /home/ubuntu/analysis/attack_after/dhcp.log
```

Sau đó chạy trình phân tích thống kê Python để đối chiếu toàn bộ 3 kịch bản cùng số liệu bộ đếm `nftables`:
```bash
python3 /usr/local/bin/analyze_dhcp.py
```

---

## 12. Hướng Dẫn Xem Kết Quả Phân Tích Và Chấm Điểm (`checkwork`)

1. **Các tệp báo cáo định lượng được xuất tự động trên `dhcprelay`:**
   - Báo cáo Markdown kèm biểu đồ ASCII: `/home/ubuntu/reports/dhcp_defense_report.md`
   - Bảng chỉ số tổng hợp CSV: `/home/ubuntu/analysis/dhcp_summary_metrics.csv`
   - Dẫn chứng từng gói tin CSV: `/home/ubuntu/analysis/dhcp_packets_evidence.csv`
   - Dữ liệu chuẩn hóa JSON: `/home/ubuntu/analysis/dhcp_analysis_summary.json`
2. **Kiểm tra chấm điểm tự động trên terminal máy Host Ubuntu:**
   ```bash
   checkwork dhcp-flooding-defense
   ```
   Bảng 6 tiêu chí đánh giá tự động:
   - `client_base_ip`: Client nhận thành công IP động ban đầu từ DHCP Server.
   - `pcap_captured`: Thu thập đủ 3 tệp PCAPNG (`normal`, `attack_before`, `attack_after`).
   - `flood_attack`: Thực hiện mô phỏng tấn công DHCP Flooding trên `attacker`.
   - `nft_defense`: Kích hoạt tường lửa `nftables` trên `dhcprelay` và xác minh bộ đếm chặn gói tin tấn công (`dhcp_flood_drop`).
   - `client_defense`: Client giải phóng và xin cấp lại IP thành công khi đã bật tường lửa.
   - `zeek_analysis`: Phân tích các tệp PCAP bằng Zeek + Python và tạo báo cáo so sánh.

---

## 13. Hướng Dẫn Dừng Bài Lab Và Khôi Phục An Toàn

- **Dừng bài lab chuẩn Labtainers (trên máy Host):**
  ```bash
  stoplab dhcp-flooding-defense
  ```
- **Khôi phục/dọn dẹp an toàn:** మీరు có thể sử dụng script [`scripts/cleanup.sh`](file:///home/student/labtainer/trunk/labs/dhcp-flooding-defense/scripts/cleanup.sh) để dừng riêng các container và mạng của bài lab `dhcp-flooding-defense` mà không chạm tới bất kỳ bài lab hay mạng dùng chung nào khác.
- **Gỡ bỏ bài lab (nếu muốn xóa khỏi danh sách labs):**
  ```bash
  stoplab dhcp-flooding-defense
  rm -rf "$LABTAINER_DIR/labs/dhcp-flooding-defense"
  ```

---

## 14. Các Lỗi Thường Gặp Và Cách Xử Lý (Troubleshooting)

1. **Lỗi `tshark: The file ... could not be opened: Permission denied`:**
   - *Nguyên nhân:* `dumpcap` hạ quyền khi mở file trong thư mục không có quyền ghi cho nhóm `other`.
   - *Cách xử lý:* Chạy `chmod -R 777 /home/ubuntu/captures /home/ubuntu/analysis /home/ubuntu/reports` trên `dhcprelay` (đã được cấu hình sẵn tự động trong image mới).
2. **Lỗi `grep: /var/lib/dhcp/dhcpd.leases: No such file or directory`:**
   - *Nguyên nhân:* Gõ nhầm lệnh kiểm tra bảng lease của Server trên cửa sổ `dhcprelay`.
   - *Cách xử lý:* Chuyển sang cửa sổ **`dhcpserver`** để đọc `/var/lib/dhcp/dhcpd.leases`.
3. **Làm mới bảng lease của DHCP Server sau khi thử nghiệm ngập lụt:**
   - Trên cửa sổ **`dhcpserver`**, chạy:
     ```bash
     pkill dhcpd
     truncate -s 0 /var/lib/dhcp/dhcpd.leases
     dhcpd -4 -cf /etc/dhcp/dhcpd.conf -lf /var/lib/dhcp/dhcpd.leases eth0
     ```

---

## 15. Cách Kiểm Tra Docker Image

Để kiểm tra các Docker image của bài lab trên máy:
```bash
docker images | grep dhcp-flooding-defense
```
Hoặc kiểm tra khả năng pull trực tiếp từ Docker Hub:
```bash
docker pull zeus183/dhcp-flooding-defense.dhcpserver.student:latest
docker pull zeus183/dhcp-flooding-defense.dhcprelay.student:latest
docker pull zeus183/dhcp-flooding-defense.attacker.student:latest
docker pull zeus183/dhcp-flooding-defense.client.student:latest
```

---

## 16. Link GitHub Repository & GitHub Release

- **GitHub Repository:** https://github.com/ledinhtu72/dhcp-flooding-defense
- **GitHub Release (`v1.0.0`):** https://github.com/ledinhtu72/dhcp-flooding-defense/releases/tag/v1.0.0
- **Link tải trực tiếp file TAR (`imodule`):**
  - Release Asset: `https://github.com/ledinhtu72/dhcp-flooding-defense/releases/download/v1.0.0/dhcp-flooding-defense.tar`
  - Main Branch Raw: `https://raw.githubusercontent.com/ledinhtu72/dhcp-flooding-defense/main/dhcp-flooding-defense.tar`

---

## 17. Link Docker Hub Chính

- **Link Docker Hub Repository chính:** https://hub.docker.com/r/zeus183/dhcp-flooding-defense
- **Link Docker Hub Namespace (`zeus183`):** https://hub.docker.com/u/zeus183
- **Danh sách 4 Image chuẩn Labtainers (tự động pull khi chạy `labtainer dhcp-flooding-defense`):**
  1. `zeus183/dhcp-flooding-defense.dhcpserver.student:latest` (`v1.0.0`)
  2. `zeus183/dhcp-flooding-defense.dhcprelay.student:latest` (`v1.0.0`)
  3. `zeus183/dhcp-flooding-defense.attacker.student:latest` (`v1.0.0`)
  4. `zeus183/dhcp-flooding-defense.client.student:latest` (`v1.0.0`)
