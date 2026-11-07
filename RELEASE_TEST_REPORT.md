# BÁO CÁO KIỂM THỬ TRƯỚC PHÁT HÀNH (`RELEASE_TEST_REPORT.md`)

- **Tên bài Labtainer:** `dhcp-flooding-defense`
- **Tên dự án:** DHCP Flooding Attack and Defense Using nftables Firewall
- **Phiên bản:** `v1.0.0`
- **Ngày kiểm thử:** `2026-11-06`

---

## 1. Thông Tin Môi Trường Đã Kiểm Thử

| Hạng mục | Thông số thực tế |
| :--- | :--- |
| **Hệ điều hành** | Ubuntu 24.04 LTS (`Linux Labtainer-VirtualBox 7.0.0-38-generic x86_64`) |
| **CPU** | AMD Ryzen 5 5600H with Radeon Graphics (2 vCPU cấp cho VM) |
| **RAM / Swap** | 4.5 GiB RAM + 3.7 GiB Swap |
| **Dung lượng ổ đĩa trống** | ~33 GB khả dụng |
| **Phiên bản Docker** | `Docker version 27.0.3, build 7d4bcd8` |
| **Phiên bản Labtainers** | `v1.4.4n (Distribution created: 09/11/2026 11:33)` |
| **Mạng nền tương thích** | `labtainer-network-base` (`1.0.0` - Dual-Subnet `192.168.0.0/24` & `10.10.0.0/24`) |

---

## 2. Bảng Tổng Hợp Kết Quả 8 Bài Kiểm Thử Bắt Buộc

| Mã Test | Hạng mục kiểm thử | Trạng thái | Kết quả thực nghiệm chi tiết |
| :--- | :--- | :---: | :--- |
| **Test 1** | **Kiểm tra gói TAR (`validate-package.sh`)** | **PASS** | `dhcp-flooding-defense.tar` giải nén chuẩn thư mục gốc `dhcp-flooding-defense/`, đủ toàn bộ file cấu hình Labtainers, 0 file rỗng, 0 token/secret bị đóng gói, khớp SHA256. |
| **Test 2** | **Kiểm tra Docker Image (`build-images.sh`)** | **PASS** | Đã build thành công 4 image độc lập cho `dhcpserver`, `dhcprelay`, `attacker`, `client` dưới namespace `zeus183` (`latest` và `v1.0.0`). Bảo toàn nguyên trạng image gốc của các bài lab khác. *(Bước push/pull từ Docker Hub chờ xác nhận Giai đoạn 8)*. |
| **Test 3** | **Kiểm thử Import bằng `imodule` (`test-import.sh`)** | **PASS** | Đã kiểm thử bằng công cụ `/home/student/labtainer/trunk/scripts/labtainer-student/bin/imodule` với gói `dhcp-flooding-defense.tar`. Giải nén tự động vào `$LABTAINER_DIR/labs/dhcp-flooding-defense` và hiển thị trong `labtainer -l`. |
| **Test 4** | **Khởi động bài lab (`labtainer dhcp-flooding-defense`)** | **PASS** | Khởi tạo đúng 2 mạng Docker (`INTERNAL_NET 192.168.0.0/24`, `EXTERNAL_NET 10.10.0.0/24`) và 4 container tương ứng 4 cửa sổ terminal. `dhcpd` và `dhcrelay` chạy ổn định, `client` nhận IP động `10.10.0.100/24` (Gateway `10.10.0.1`). |
| **Test 5** | **Kiểm tra mô phỏng tấn công DHCP Flooding** | **PASS** | Thực thi trên `attacker` bằng `dhcp_flood_scapy.py` (60 gói, 25 pkt/s) và `yersinia dhcp -attack 1`. Lưu lượng cô lập hoàn toàn trong `EXTERNAL_NET`/`INTERNAL_NET`, ghi nhận đầy đủ trong `attack_before.pcapng`. |
| **Test 6** | **Kiểm tra tường lửa `nftables` trên `dhcprelay`** | **PASS** | Nạp `/etc/nftables_dhcp_defense.nft` bằng `nft -f /etc/nftables_dhcp_defense.nft`. Bộ đếm `dhcp_flood_drop` chặn >80% gói tin lũ (`52/60` gói trong thử nghiệm chuẩn), trong khi `client` hợp lệ (`02:42:0a:0a:00:32`) vẫn nhận được IP `10.10.0.100` tức thì (`trusted_client_accept`). Hỗ trợ gỡ bảng luật an toàn mà không xóa ruleset hệ thống. |
| **Test 7** | **Kiểm tra Wireshark / TShark & Zeek / Python** | **PASS** | Thu thập đủ 3 file PCAPNG (`normal.pcapng`, `attack_before.pcapng`, `attack_after.pcapng`), mở được trên `tshark` và `wireshark`. `zeek -C -r` sinh `dhcp.log` chuẩn TSV; `analyze_dhcp.py` xuất đầy đủ CSV, JSON và báo cáo Markdown. `checkwork dhcp-flooding-defense` đạt **6/6 mục tiêu `Y`**. |
| **Test 8** | **Kiểm tra môi trường sạch (`test-import.sh`)** | **PASS** | Đã tạm di chuyển thư mục `$LABTAINER_DIR/labs/dhcp-flooding-defense` ra khỏi hệ thống, chạy `imodule` từ gói TAR độc lập và khởi chạy lại bài lab không cần bất kỳ chỉnh sửa thủ công nào. *(Kiểm thử pull từ máy ảo hoàn toàn chưa có Docker cache sẽ thực hiện ngay ở Giai đoạn 10 sau khi push lên Docker Hub)*. |

---

## 3. Các Lỗi Đã Phát Hiện Trong Quá Trình Phát Triển & Cách Xử Lý

1. **Lỗi xung đột thư viện `GLIBC_2.34` khi chạy binary `nft` trong container Ubuntu 20.04:**
   - *Nguyên nhân:* Image nền `labtainer.network.ssh2` dùng Ubuntu 20.04 (glibc 2.31), trong khi `nft` v1.0.9 của host biên dịch với glibc 2.39.
   - *Cách xử lý:* Đóng gói kèm bộ thư viện chia sẻ độc lập tại `/opt/nft-libs/` và tạo wrapper `/usr/sbin/nft` gọi qua `ld-linux-x86-64.so.2 --library-path /opt/nft-libs/lib`.
2. **Lỗi `tshark: Permission denied` khi ghi file vào `/home/ubuntu/captures`:**
   - *Nguyên nhân:* Tiến trình `dumpcap` do `tshark` gọi tự động hạ quyền (`CAP_DAC_OVERRIDE`), nên không tạo được file mới trong thư mục thuộc sở hữu `ubuntu:ubuntu` có mode `755`.
   - *Cách xử lý:* Thiết lập quyền `chmod -R 777 /home/ubuntu/captures /home/ubuntu/analysis /home/ubuntu/reports /var/log/captures` ngay trong Dockerfile của `dhcprelay`.
3. **Lỗi `datatype mismatch` trong `/etc/nftables_dhcp_defense.nft` khi đối sánh `@th,288,48`:**
   - *Nguyên nhân:* Biểu thức đọc raw payload `@th,288,48` (trường `chaddr` của BOOTP) có kiểu số nguyên 48-bit (`integer`), không khớp với kiểu `ether_addr` của `set`.
   - *Cách xử lý:* Sử dụng đối sánh trực tiếp `@th,288,48 0x02420a0a0032` trong `chain relay_out`, nạp thành công 100% qua lệnh `nft -f /etc/nftables_dhcp_defense.nft`.
4. **Lỗi container `attacker` bị bỏ qua khi chấm điểm `checkwork` do sót `/var/labtainer/did_param` trong image gốc:**
   - *Nguyên nhân:* Image `huynguyen1324/dhcp-lab.attacker.student` trước đó từng được commit từ một container đang chạy của bài `rogue-dhcp-server`, làm sót `/var/labtainer/did_param` và `.local/.labname` (`rogue-dhcp-server`).
   - *Cách xử lý:* Làm sạch `/var/labtainer/did_param` và làm rỗng `.local/{.email,.labname,.seed,.watermark}` trong `Dockerfile.dhcp-flooding-defense.attacker.student`. Kết quả `checkwork dhcp-flooding-defense` đạt tuyệt đối **6/6 tiêu chí `Y`**.

