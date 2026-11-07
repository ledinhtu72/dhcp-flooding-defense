# HƯỚNG DẪN THỰC HÀNH BÀI LAB: TẤN CÔNG DHCP FLOODING, PHÂN TÍCH GÓI TIN VỚI WIRESHARK/ZEEK/PYTHON VÀ PHÒNG THỦ BẰNG NFTABLES

---

## 1. Sơ Đồ Mạng Và Phân Bổ Địa Chỉ IP (Dual-Subnet Topology)

Bài lab mô phỏng kiến trúc mạng doanh nghiệp chia tách thành 2 phân đoạn mạng (**Dual-Subnet**) nối qua nút trung gian **DHCP Relay**:

```text
  [EXTERNAL_NET: 10.10.0.0/24]                    [INTERNAL_NET: 192.168.0.0/24]
 ┌────────────────────────────┐                  ┌──────────────────────────────┐
 │ attacker (10.10.0.20)      │                  │ dhcpserver (192.168.0.100)   │
 │  - yersinia / scapy        ├───┐          ┌───┤  - isc-dhcp-server           │
 └────────────────────────────┘   │          │   │  - Pool: 10.10.0.100 - .130  │
                                  ▼          ▼   └──────────────────────────────┘
 ┌────────────────────────────┐ ┌──────────────┐
 │ client (Dynamic DHCP)      │ │  dhcprelay   │  <-- ĐIỂM CHẶN & GIÁM SÁT TRUNG TÂM
 │  - MAC: 02:42:0a:0a:00:32  ├─► eth0:10.10.0.1│  - isc-dhcp-relay
 │  - dhclient                │ │ eth1:192.168.0.1 - Tường lửa: nftables
 └────────────────────────────┘ └──────────────┘  - Sensor: TShark / Wireshark
                                                  - Phân tích: Zeek + Python3
```

| Máy (Container) | Mạng kết nối | Địa chỉ IP | Vai trò chính |
| :--- | :--- | :--- | :--- |
| **`dhcpserver`** | `INTERNAL_NET` (`192.168.0.0/24`) | `eth0`: `192.168.0.100` | Máy chủ ISC DHCP cấp phát dải `10.10.0.100 - 10.10.0.130` (31 IP) |
| **`dhcprelay`** | Nối cả 2 mạng | `eth0`: `10.10.0.1`<br>`eth1`: `192.168.0.1` | Chuyển tiếp gói tin DHCP, đặt tường lửa **`nftables`**, bắt gói **TShark/Wireshark** và chạy **Zeek + Python** |
| **`attacker`** | `EXTERNAL_NET` (`10.10.0.0/24`) | `eth0`: `10.10.0.20` | Phát động tấn công DHCP Flooding bằng `yersinia` hoặc `scapy` |
| **`client`** | `EXTERNAL_NET` (`10.10.0.0/24`) | *Nhận IP động* | Máy trạm hợp lệ (`MAC: 02:42:0a:0a:00:32`) xin cấp phát IP động qua Relay |

---

## 2. GIAI ĐOẠN 1: Kiểm Tra Dịch Vụ & Cấp Phát DHCP Bình Thường (Kịch Bản A - Baseline)

### Bước 1: Kiểm tra trạng thái DHCP Server và DHCP Relay
1. Trên cửa sổ terminal **`dhcpserver`**:
   ```bash
   systemctl status dhcp-server-init.service --no-pager
   pgrep -a dhcpd
   ip route show
   ```
2. Trên cửa sổ terminal **`dhcprelay`**:
   ```bash
   systemctl status dhcp-relay-init.service --no-pager
   sysctl net.ipv4.ip_forward
   pgrep -a dhcrelay
   ip -br addr
   mkdir -p -m 777 /home/ubuntu/captures /home/ubuntu/analysis /home/ubuntu/reports
   ```

### Bước 2: Bắt gói tin chuẩn (`normal_dhcp.pcapng`) và Xin cấp IP trên Client
1. Trên cửa sổ terminal **`dhcprelay`**, chạy lệnh `tshark` bắt gói tin DHCP trên giao diện `eth1` (`192.168.0.1` hướng tới DHCP Server) trong 15 giây:
   ```bash
   tshark -i eth1 -f "udp port 67 or udp port 68" -a duration:15 -w /home/ubuntu/captures/normal.pcapng
   ```
2. Ngay khi `tshark` đang chạy, chuyển sang cửa sổ terminal **`client`** và xin cấp phát IP động bằng `dhclient`:
   ```bash
   dhclient -r eth0
   dhclient -v eth0
   ip addr show eth0
   ```
3. Sau khi `tshark` dừng trên **`dhcprelay`**, kiểm tra các gói tin vừa bắt được (`DHCP Discover -> Offer -> Request -> ACK`):
   ```bash
   tshark -r /home/ubuntu/captures/normal.pcapng
   ```
> **Điều kiện đạt checkwork:** Mục tiêu **`client_base_ip`** chuyển sang **Y**.

---

## 3. GIAI ĐOẠN 2: Mô Phỏng Tấn Công DHCP Flooding Trước Khi Bật Tường Lửa (Kịch Bản B)

### Bước 3: Bắt gói tin `attack_before.pcapng` và Phát động tấn công
1. Trên cửa sổ terminal **`dhcprelay`**, khởi chạy `tshark` trong 15 giây để ghi lại lưu lượng tấn công khi chưa bật tường lửa:
   ```bash
   tshark -i eth1 -f "udp port 67 or udp port 68" -a duration:15 -w /home/ubuntu/captures/attack_before.pcapng
   ```
2. Ngay lập tức chuyển sang cửa sổ terminal **`attacker`**, phát tán bão gói tin `DHCPDISCOVER` với địa chỉ MAC giả mạo bằng **1 trong 2 cách**:
   - **Cách 1 (Scapy CLI - bắn 60 gói tốc độ 25 gói/giây):**
     ```bash
     python3 /home/ubuntu/dhcp_flood_scapy.py 60 0.04 discover
     ```
   - **Cách 2 (Yersinia CLI hoặc giao diện ncurses `yersinia -I`):**
     ```bash
     timeout 3 yersinia dhcp -attack 1 -interface eth0
     ```
3. Sau khi `tshark` dừng trên **`dhcprelay`**, kiểm tra số lượng gói tin tràn qua Relay tới DHCP Server:
   ```bash
   tshark -r /home/ubuntu/captures/attack_before.pcapng | head -n 25
   tshark -r /home/ubuntu/captures/attack_before.pcapng | wc -l
   ```
4. Trên cửa sổ terminal **`dhcpserver`**, kiểm tra bảng lease và làm mới lại bảng lease để chuẩn bị cho kịch bản phòng thủ:
   ```bash
   cat /var/lib/dhcp/dhcpd.leases | grep "^lease " | wc -l
   pkill dhcpd
   truncate -s 0 /var/lib/dhcp/dhcpd.leases
   dhcpd -4 -cf /etc/dhcp/dhcpd.conf -lf /var/lib/dhcp/dhcpd.leases eth0
   ```
> **Điều kiện đạt checkwork:** Mục tiêu **`flood_attack`** chuyển sang **Y**.

---

## 4. GIAI ĐOẠN 3: Phòng Thủ Bằng `nftables` Trên DHCP Relay & Kiểm Chứng (Kịch Bản C & D)

### Bước 4: Nạp bộ quy tắc tường lửa `nftables` trên `dhcprelay`
Trên cửa sổ terminal **`dhcprelay`**, kiểm tra nội dung file `/etc/nftables_dhcp_defense.nft` và kích hoạt bằng lệnh `nft`:
```bash
cat /etc/nftables_dhcp_defense.nft
nft -f /etc/nftables_dhcp_defense.nft
nft list table inet dhcp_defense
```

### Bước 5: Bắt gói tin `attack_after.pcapng`, Tấn công lại và Xin cấp IP trên Client
1. Trên cửa sổ terminal **`dhcprelay`**, khởi chạy `tshark` bắt gói tin sau khi đã bật `nftables`:
   ```bash
   tshark -i eth1 -f "udp port 67 or udp port 68" -a duration:20 -w /home/ubuntu/captures/attack_after.pcapng
   ```
2. Chuyển sang cửa sổ terminal **`attacker`**, chạy lại lệnh tấn công DHCP Flooding:
   ```bash
   python3 /home/ubuntu/dhcp_flood_scapy.py 60 0.04 discover
   ```
3. Ngay sau đó, chuyển sang cửa sổ terminal **`client`**, giải phóng và xin cấp lại IP để kiểm chứng Client hợp lệ vẫn được phục vụ bình thường:
   ```bash
   dhclient -r eth0
   dhclient -v eth0
   ip addr show eth0
   ```
4. Khi `tshark` trên **`dhcprelay`** dừng, kiểm tra bộ đếm `counter` của `nftables` và số gói tin trong `attack_after.pcapng`:
   ```bash
   nft list table netdev dhcp_defense_ingress
   nft list table inet dhcp_defense
   tshark -r /home/ubuntu/captures/attack_after.pcapng
   ```
> **Điều kiện đạt checkwork:** Các mục tiêu **`pcap_captured`**, **`nft_defense`**, và **`client_defense`** chuyển sang **Y**.

---

## 5. GIAI ĐOẠN 4: Phân Tích Forensics Bằng Zeek & Python

### Bước 6: Trích xuất `dhcp.log` bằng Zeek và chạy Python tổng hợp báo cáo
Trên cửa sổ terminal **`dhcprelay`**:
```bash
# 1. Phân tích 3 file PCAPNG bằng Zeek để sinh dhcp.log
mkdir -p /home/ubuntu/analysis/baseline /home/ubuntu/analysis/attack_before /home/ubuntu/analysis/attack_after
cd /home/ubuntu/analysis/baseline && zeek -C -r /home/ubuntu/captures/normal.pcapng
cd /home/ubuntu/analysis/attack_before && zeek -C -r /home/ubuntu/captures/attack_before.pcapng
cd /home/ubuntu/analysis/attack_after && zeek -C -r /home/ubuntu/captures/attack_after.pcapng

# 2. Kiểm tra nội dung file dhcp.log do Zeek sinh ra
cat /home/ubuntu/analysis/baseline/dhcp.log
cat /home/ubuntu/analysis/attack_after/dhcp.log

# 3. Chạy trình phân tích Python để tổng hợp bảng chỉ số, kiểm tra counter nftables và vẽ biểu đồ ASCII
python3 /usr/local/bin/analyze_dhcp.py
```
> **Điều kiện đạt checkwork:** Mục tiêu **`zeek_analysis`** chuyển sang **Y**.

---

## 6. ĐÁNH GIÁ VÀ NỘP BÀI (`checkwork`)

Trên terminal máy Host Ubuntu, chạy lệnh kiểm tra kết quả:
```bash
checkwork dhcp-flooding-defense
```

| Mục tiêu (`goals.config`) | Trạng thái | Ý nghĩa đánh giá |
| :--- | :---: | :--- |
| **`client_base_ip`** | **Y** | Client xin cấp phát thành công địa chỉ IP động ban đầu qua DHCP Relay |
| **`pcap_captured`** | **Y** | Thu thập đủ 3 tệp PCAPNG (`normal_dhcp.pcapng`, `attack_before.pcapng`, `attack_after.pcapng`) |
| **`flood_attack`** | **Y** | Thực thi tấn công DHCP Flooding trên `attacker` |
| **`nft_defense`** | **Y** | Kích hoạt tường lửa `nftables` trên `dhcprelay` và xác minh bộ đếm chặn gói tin tấn công (`dhcp_flood_drop`) |
| **`client_defense`** | **Y** | Client giải phóng (`dhclient -r`) và xin cấp lại IP thành công khi đã bật tường lửa |
| **`zeek_analysis`** | **Y** | Phân tích gói tin bằng Zeek (`dhcp.log`) + Python và xuất báo cáo định lượng |

Khi hoàn tất thực hành, dừng bài lab bằng lệnh:
```bash
stoplab dhcp-flooding-defense
```
