# TESTING_GUIDE.md – `dhcp-flooding-defense`

Hướng dẫn thực hành và kiểm thử từng bước bằng **dòng lệnh trực tiếp (CLI)** cho bài lab **Mô phỏng Tấn công DHCP Flooding, Phân tích Gói tin với Wireshark/Zeek/Python và Phòng thủ bằng `nftables`**.

---

## 1. Quy ước ký hiệu và Sơ đồ mạng (Dual-Subnet)

```text
[HOST]          Lệnh chạy trên máy ảo Ubuntu Host (bên ngoài container)
[dhcpserver]    Lệnh chạy trên terminal của container dhcpserver (192.168.0.100)
[dhcprelay]     Lệnh chạy trên terminal của container dhcprelay (eth0: 10.10.0.1, eth1: 192.168.0.1)
[attacker]      Lệnh chạy trên terminal của container attacker (10.10.0.20)
[client]        Lệnh chạy trên terminal của container client (10.10.0.50 -> nhận IP động)
```

| Container | Mạng kết nối | Địa chỉ IP | Vai trò trong bài Lab |
| :--- | :--- | :--- | :--- |
| **`dhcpserver`** | `INTERNAL_NET` (`192.168.0.0/24`) | `eth0`: `192.168.0.100` | Máy chủ ISC DHCP cấp phát dải `10.10.0.100 - 10.10.0.130` (31 IP) |
| **`dhcprelay`** | Nối cả 2 mạng | `eth0`: `10.10.0.1` (`EXTERNAL_NET`)<br>`eth1`: `192.168.0.1` (`INTERNAL_NET`) | Điểm trung chuyển `isc-dhcp-relay`, đặt tường lửa **`nftables`**, **TShark/Wireshark** và **Zeek + Python** |
| **`attacker`** | `EXTERNAL_NET` (`10.10.0.0/24`) | `eth0`: `10.10.0.20` | Máy Kali phát tán gói tin `DHCPDISCOVER` giả mạo MAC bằng `yersinia` hoặc `scapy` |
| **`client`** | `EXTERNAL_NET` (`10.10.0.0/24`) | `eth0`: nhận IP động qua DHCP | Máy trạm hợp lệ (`MAC: 02:42:0a:0a:00:32`) xin cấp phát IP qua Relay |

---

## Bước 1: Khởi động bài Lab trên máy Host

Tại terminal của máy ảo Ubuntu Host (ở bất kỳ thư mục nào):
```bash
labtainer -r dhcp-flooding-defense
```
Hệ thống sẽ tự động mở **4 cửa sổ terminal** tương ứng với `dhcpserver`, `dhcprelay`, `attacker`, và `client`.

---

## Bước 2: Kiểm tra hạ tầng mạng ban đầu

### 2.1 – Kiểm tra trên terminal `dhcpserver`
```bash
systemctl status dhcp-server-init.service --no-pager
pgrep -a dhcpd
ip addr show eth0
ip route show
cat /etc/dhcp/dhcpd.conf
```
*Kỳ vọng:* Tiến trình `dhcpd` đang chạy trên `eth0` (`192.168.0.100/24`), có tuyến định tuyến `10.10.0.0/24 via 192.168.0.1`.

### 2.2 – Kiểm tra trên terminal `dhcprelay`
```bash
systemctl status dhcp-relay-init.service --no-pager
sysctl net.ipv4.ip_forward
pgrep -a dhcrelay
ip -br addr
mkdir -p -m 777 /home/ubuntu/captures /home/ubuntu/analysis /home/ubuntu/reports
```
*Kỳ vọng:* `net.ipv4.ip_forward = 1`, `dhcrelay` đang lắng nghe trên cả 2 card mạng (`eth0` nối với `EXTERNAL_NET 10.10.0.1/24` và `eth1` nối với `INTERNAL_NET 192.168.0.1/24`).

---

## Bước 3: Kịch bản A (Baseline) – Cấp phát DHCP bình thường & Bắt gói `normal_dhcp.pcapng`

### 3.1 – Khởi chạy `tshark` bắt gói tin trên `dhcprelay`
Trên terminal **`dhcprelay`**, bắt gói tin DHCP đi qua giao diện `eth1` (`192.168.0.1` hướng về DHCP Server `192.168.0.100`) trong 15 giây (hoặc nhấn `Ctrl+C` sau khi `client` nhận xong IP):
```bash
tshark -i eth1 -f "udp port 67 or udp port 68" -a duration:15 -w /home/ubuntu/captures/normal.pcapng
```

### 3.2 – Xin cấp phát IP động trên `client`
Ngay trong lúc `tshark` đang chạy trên `dhcprelay`, chuyển sang terminal **`client`** và chạy lệnh:
```bash
dhclient -r eth0
dhclient -v eth0
ip addr show eth0
ip route show
```
*Kỳ vọng:* `client` hoàn tất bắt tay 4 bước (`DHCPDISCOVER -> DHCPOFFER -> DHCPREQUEST -> DHCPACK`) và nhận địa chỉ IP `10.10.0.100/24`, Default Gateway `10.10.0.1`.

### 3.3 – Kiểm tra file `normal_dhcp.pcapng` và bảng Lease
- Trên terminal **`dhcprelay`** (sau khi `tshark` dừng):
  ```bash
  tshark -r /home/ubuntu/captures/normal.pcapng
  ```
- Trên terminal **`dhcpserver`**:
  ```bash
  cat /var/lib/dhcp/dhcpd.leases
  ```

---

## Bước 4: Kịch bản B (Attack Before Defense) – Tấn công DHCP Flooding khi CHƯA bật `nftables`

### 4.1 – Khởi chạy `tshark` ghi nhận tấn công trên `dhcprelay`
Trên terminal **`dhcprelay`**, bắt gói tin lưu vào `/home/ubuntu/captures/attack_before.pcapng`:
```bash
tshark -i eth1 -f "udp port 67 or udp port 68" -a duration:15 -w /home/ubuntu/captures/attack_before.pcapng
```

### 4.2 – Phát động tấn công DHCP Flooding trên `attacker`
Ngay khi `tshark` bắt đầu chạy, chuyển sang terminal **`attacker`** và thực hiện tấn công bằng **1 trong 2 cách sau**:

* **Cách 1: Bắn 60 gói `DHCPDISCOVER` với MAC giả mạo ngẫu nhiên bằng Scapy (tốc độ 25 gói/giây, tự dừng sau ~2.5 giây):**
  ```bash
  python3 /home/ubuntu/dhcp_flood_scapy.py 60 0.04 discover
  ```
* **Cách 2: Sử dụng công cụ `yersinia` (chạy giới hạn 3 giây bằng `timeout` hoặc nhấn `Ctrl+C` / giao diện `yersinia -I`):**
  ```bash
  timeout 3 yersinia dhcp -attack 1 -interface eth0
  ```

### 4.3 – Quan sát hậu quả trên `dhcprelay` và `dhcpserver`
- Trên terminal **`dhcprelay`** (sau khi `tshark` dừng):
  ```bash
  tshark -r /home/ubuntu/captures/attack_before.pcapng | head -n 30
  tshark -r /home/ubuntu/captures/attack_before.pcapng | wc -l
  ```
  *Kỳ vọng:* Hàng trăm gói tin `DHCP Discover` (từ các địa chỉ MAC giả mạo) và `DHCP Offer` tràn qua `eth1` sang `dhcpserver`.
- Trên terminal **`dhcpserver`**, kiểm tra bảng lease và **xóa trắng bảng lease** để chuẩn bị cho kịch bản phòng thủ:
  ```bash
  grep "^lease " /var/lib/dhcp/dhcpd.leases | sort -u | wc -l
  pkill dhcpd
  truncate -s 0 /var/lib/dhcp/dhcpd.leases
  dhcpd -4 -cf /etc/dhcp/dhcpd.conf -lf /var/lib/dhcp/dhcpd.leases eth0
  ```

---

## Bước 5: Kịch bản C & D (Defense with `nftables`) – Bật tường lửa `nftables` & Tấn công lại

### 5.1 – Kiểm tra và nạp bộ quy tắc `nftables` trên `dhcprelay`
Trên terminal **`dhcprelay`**, xem nội dung tệp cấu hình `/etc/nftables_dhcp_defense.nft` và nạp trực tiếp bằng lệnh `nft`:
```bash
cat /etc/nftables_dhcp_defense.nft
nft -f /etc/nftables_dhcp_defense.nft
nft list table inet dhcp_defense
```
*Giải thích kỹ thuật:*
- `table netdev dhcp_defense_ingress` (hook `ingress` trên `eth0`) đếm tổng số gói DHCP đi vào từ mạng `EXTERNAL_NET`.
- `table inet dhcp_defense` (chain `relay_out`, hook `output`) kiểm soát lưu lượng do tiến trình `dhcrelay` chuyển tiếp sang `192.168.0.100:67`:
  1. Ưu tiên cho phép Client hợp lệ (`02:42:0a:0a:00:32` tại trường BOOTP `chaddr` `@th,288,48`).
  2. Giới hạn tốc độ (`limit rate 3/second burst 6 packets`) đối với các gói DHCP từ MAC lạ.
  3. Ghi log có kiểm soát và **`drop`** toàn bộ gói tin DHCP Flooding vượt ngưỡng (`dhcp_flood_drop`).

### 5.2 – Bắt gói tin `attack_after.pcapng` trên `dhcprelay`
Trên terminal **`dhcprelay`**, khởi chạy `tshark` trong 20 giây:
```bash
tshark -i eth1 -f "udp port 67 or udp port 68" -a duration:20 -w /home/ubuntu/captures/attack_after.pcapng
```

### 5.3 – Phát động lại tấn công trên `attacker` & Kiểm chứng cấp IP trên `client`
1. Ngay khi `tshark` đang chạy, chuyển sang terminal **`attacker`** và phát động lại cuộc tấn công tương tự Bước 4.2:
   ```bash
   python3 /home/ubuntu/dhcp_flood_scapy.py 60 0.04 discover
   ```
2. Ngay sau đó, chuyển sang terminal **`client`** để giải phóng và xin cấp phát lại IP động:
   ```bash
   dhclient -r eth0
   dhclient -v eth0
   ip addr show eth0
   ```
   *Kỳ vọng:* `client` hợp lệ lập tức nhận được địa chỉ IP `10.10.0.100` mà không bị nghẽn hay từ chối dịch vụ!

### 5.4 – Kiểm tra bộ đếm `counter` của `nftables` trên `dhcprelay`
Sau khi `tshark` dừng trên terminal **`dhcprelay`**, kiểm tra trực tiếp bộ đếm gói tin trên `nftables`:
```bash
nft list table netdev dhcp_defense_ingress
nft list table inet dhcp_defense
tshark -r /home/ubuntu/captures/attack_after.pcapng
```
*Kỳ vọng:*
- Bộ đếm `dhcp_flood_drop` trong `nft list table inet dhcp_defense` ghi nhận hàng chục gói tin tấn công đã bị **DROP** (`counter packets 52 ... drop`).
- Số lượng gói tin đi tới DHCP Server trong `attack_after.pcapng` giảm mạnh (~80–85%) so với `attack_before.pcapng`.

---

## Bước 6: Phân tích Forensics bằng Zeek + Python (và Wireshark GUI)

### 6.1 – Phân tích từng tệp PCAP bằng `zeek` trên `dhcprelay`
Trên terminal **`dhcprelay`**, chạy lệnh `zeek` để trích xuất tệp `dhcp.log` cho cả 3 kịch bản:
```bash
mkdir -p /home/ubuntu/analysis/baseline /home/ubuntu/analysis/attack_before /home/ubuntu/analysis/attack_after

cd /home/ubuntu/analysis/baseline && zeek -C -r /home/ubuntu/captures/normal.pcapng
cd /home/ubuntu/analysis/attack_before && zeek -C -r /home/ubuntu/captures/attack_before.pcapng
cd /home/ubuntu/analysis/attack_after && zeek -C -r /home/ubuntu/captures/attack_after.pcapng

cat /home/ubuntu/analysis/baseline/dhcp.log
head -n 20 /home/ubuntu/analysis/attack_before/dhcp.log
cat /home/ubuntu/analysis/attack_after/dhcp.log
```

### 6.2 – Tổng hợp báo cáo thống kê và biểu đồ so sánh bằng `python3`
Trên terminal **`dhcprelay`**, chạy lệnh Python phân tích dữ liệu PCAP + Zeek `dhcp.log` + bộ đếm `nftables`:
```bash
python3 /usr/local/bin/analyze_dhcp.py
```
Lệnh trên sẽ in trực tiếp bảng đối chiếu 3 kịch bản và biểu đồ trực quan ra màn hình, đồng thời xuất các tệp kết quả tại:
- `/home/ubuntu/reports/dhcp_defense_report.md`
- `/home/ubuntu/analysis/dhcp_summary_metrics.csv`
- `/home/ubuntu/analysis/dhcp_packets_evidence.csv`
- `/home/ubuntu/analysis/dhcp_analysis_summary.json`

### 6.3 – (Tùy chọn) Phân tích trực quan trên giao diện đồ họa Wireshark
Trên terminal **`dhcprelay`**:
```bash
wireshark /home/ubuntu/captures/attack_before.pcapng &
wireshark /home/ubuntu/captures/attack_after.pcapng &
```
*(Gợi ý bộ lọc hiển thị trên Wireshark: `dhcp`, `dhcp.option.dhcp == 1` cho gói Discover, `dhcp.option.dhcp == 2` cho gói Offer, `dhcp.option.dhcp == 5` cho gói ACK).*

---

## Bước 7: Chấm điểm tự động (`checkwork`) và Dừng bài Lab trên máy Host

Tại terminal của máy ảo Ubuntu Host:
```bash
checkwork dhcp-flooding-defense
```

Kết quả mong đợi (đạt cả 6/6 tiêu chí **`Y`**):
```text
Labname dhcp-flooding-defense

Student: b22dcat261
 Y -  client_base_ip
 Y -  pcap_captured
 Y -  flood_attack
 Y -  nft_defense
 Y -  client_defense
 Y -  zeek_analysis
```

Khi hoàn tất thực hành, dừng bài lab bằng lệnh:
```bash
stoplab dhcp-flooding-defense
```
