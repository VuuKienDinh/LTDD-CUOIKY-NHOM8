# Hệ thống Đặt Vé Xe Khách Trực Tuyến — BusTicketBooking

Dự án **BusTicketBooking** được xây dựng đầy đủ theo tài liệu đặc tả nghiệp vụ [Bao_Cao_Tong_Hop_Cac_Chuc_Nang_He_Thong_Dat_Xe.docx](Bao_Cao_Tong_Hop_Cac_Chuc_Nang_He_Thong_Dat_Xe.docx), bao gồm **ASP.NET Core Web API (.NET 8) + EF Core + SQL Server + SignalR + VNPay Sandbox** và ứng dụng di động **Flutter** hỗ trợ đầy đủ 4 phân hệ: **Customer (Khách hàng & Guest)**, **Bus Operator (Nhà xe Multi-tenant)**, **Driver (Tài xế)** và **Admin (Quản trị hệ thống)**.

---

## 1. Kiến trúc Hệ thống & Cấu trúc Thư mục

- **Backend (`webAPI/`)**:
  - [Models/Enums.cs](webAPI/Models/Enums.cs) & [Models/Entities.cs](webAPI/Models/Entities.cs): Đầy đủ **26 bảng thực thể (Entities)** theo đặc tả nghiệp vụ.
  - [Data/BusBookingDbContext.cs](webAPI/Data/BusBookingDbContext.cs): Cấu hình khóa ngoại `DeleteBehavior.Restrict`, Unique Index trên `Email`, `PlateNumber`, `BookingCode`, `TicketCode`, `QRTokenHash` và **Filtered Unique Index** trên `BookingDetails(TripSeatId) WHERE [IsActiveBooking] = 1` (`BR09`).
  - [Data/DatabaseSeeder.cs](webAPI/Data/DatabaseSeeder.cs): Tự động khởi tạo CSDL `BusTicketBookingDb` trên `SQLEXPRESS`, seed dữ liệu mẫu và tự động xuất file [Database_BusTicketBooking_Schema.sql](webAPI/Database_BusTicketBooking_Schema.sql).
  - [Services/SeatHoldCleanupService.cs](webAPI/Services/SeatHoldCleanupService.cs): Background Service tự động giải phóng ghế giữ chỗ quá hạn 10 phút (`AT05`, `BR10`) và quá hạn thanh toán.
  - [Hubs/TripTrackingHub.cs](webAPI/Hubs/TripTrackingHub.cs): SignalR Hub (`/hubs/trip-tracking`) phát tọa độ GPS và trạng thái chuyến xe thời gian thực.
  - **Controllers**:
    - [AuthController.cs](webAPI/Controllers/AuthController.cs): Đăng ký, đăng nhập JWT + RefreshToken, cập nhật hồ sơ (`FR02`), đổi mật khẩu (`FR01`), đăng ký đối tác nhà xe (`UC14`/`FR03`), gửi yêu cầu hỗ trợ (`UC31`).
    - [TripsController.cs](webAPI/Controllers/TripsController.cs): Tra cứu chuyến xe (`UC03`), lọc theo khoảng giá/khung giờ/loại xe/nhà xe/số ghế trống (`FR11`), xem điểm đón/trả (`UC04`), sơ đồ ghế 2 tầng (`UC05`), theo dõi GPS bảo mật (`AT10`, `BR22`).
    - [BookingsController.cs](webAPI/Controllers/BookingsController.cs): Giữ ghế `Serializable` (`AT04`, `BR11`), tạo đơn đặt vé nhiều ghế kèm mã khuyến mãi (`FUTA50K`, `SINHVIEN30K`, `GIAM10` - `AT06`, `BR13`), tích hợp **VNPay Sandbox + IPN Idempotency + Late Payment Reconciliation** (`AT07`, `BR16`), đặt vé **COD** (`AT08`), hủy vé & tính phí hoàn tiền theo bậc thời gian (`UC11`, `BR20`, `BR21`), vé QR chống giả mạo (`BR17`), đánh giá chuyến đi (`UC13`, `BR24`, `BR25`).
    - [OperatorController.cs](webAPI/Controllers/OperatorController.cs): Cô lập dữ liệu đa nhà xe (`AT02`, `BR03`), quản lý đội xe & cấu hình sơ đồ ghế (`UC18`, `BR27`), lịch bảo trì xe (`BusMaintenances`), quản lý tài xế & hồ sơ chứng chỉ (`DriverDocuments`), quản lý tuyến & trạm đón/trả (`UC20`), tạo nhân sự `CompanyStaff` (`UC16`), lập lịch chuyến xe kiểm tra trùng xe/tài xế/bằng lái/thời gian quay đầu (`AT03`, `BR06`–`BR08`), đổi tài xế (`UC22`), hủy chuyến hàng loạt (`AT11`), xác nhận thu COD (`AT08`), đánh dấu NoShow, phản hồi khiếu nại (`UC31`).
    - [DriverController.cs](webAPI/Controllers/DriverController.cs): Xem chuyến được phân công (`BR04`), quét QR check-in chống quét trùng (`AT09`, `BR18`), xem lịch sử soát vé (`TicketCheckIns`), cập nhật trạng thái chuyến kèm lý do trễ (`BR28`), phát tọa độ GPS (`AT10`, `BR23`), báo cáo sự cố (`TripIncidents`).
    - [AdminController.cs](webAPI/Controllers/AdminController.cs): Duyệt/Từ chối/Tạm ngưng nhà xe (`UC15`), khóa/mở khóa tài khoản, gửi thông báo toàn hệ thống (`UC29`), hoàn tất hoàn tiền (`UC27`), báo cáo doanh thu tách biệt doanh thu đã thu, COD chưa thu và tiền hoàn (`AT12`, `BR26`), nhật ký AuditLog (`UC30`), và kiểm tra tự động 12 tiêu chí nghiệm thu `AT01`–`AT12` (`/api/admin/acceptance-criteria`).

- **Ứng dụng Di động Flutter (`lib/`)**:
  - [services/api_client.dart](lib/services/api_client.dart): Tự động dò kết nối qua `http://127.0.0.1:5284` (`adb reverse` USB), `http://192.168.1.10:5284` (Wi-Fi LAN), `http://10.0.2.2:5284` (Android Emulator) và hỗ trợ chế độ **Khách vãng lai (Guest)**.
  - [screens/auth_screen.dart](lib/screens/auth_screen.dart): Đăng nhập, Đăng ký, Chế độ Guest, Đăng ký mở Nhà xe mới (`UC14`) và Đăng nhập nhanh 1-click cho 6 tài khoản Demo.
  - [screens/customer_shell.dart](lib/screens/customer_shell.dart) & [screens/seat_booking_screen.dart](lib/screens/seat_booking_screen.dart): Tìm kiếm & bộ lọc nâng cao, chọn ghế 2 tầng có đồng hồ đếm ngược 10 phút, áp mã giảm giá, cổng giả lập VNPay Sandbox & COD, xem vé QR, theo dõi GPS trực tuyến, hủy vé, đánh giá sao và gửi hỗ trợ.
  - [screens/operator_screen.dart](lib/screens/operator_screen.dart): Quản trị nhà xe với 5 tab (Chuyến xe, Đội xe & Sơ đồ ghế, Tài xế & Hồ sơ GPLX, Tuyến đường & Nhân sự, Hỗ trợ & Khiếu nại).
  - [screens/driver_screen.dart](lib/screens/driver_screen.dart): Điều hành chuyến đi, quét QR/nhập mã vé, xem lịch sử check-in, phát GPS tự động 10 giây/lần và báo cáo sự cố.
  - [screens/admin_screen.dart](lib/screens/admin_screen.dart): Dashboard doanh thu, chạy kiểm thử `AT01`–`AT12`, duyệt nhà xe, xử lý hoàn tiền, khóa user và xem AuditLog.

---

## 2. Tài khoản Demo Mặc định (Mật khẩu chung: `123456`)

| Vai trò | Email | Mô tả nghiệp vụ |
| :--- | :--- | :--- |
| **Customer** | `customer@gmail.vn` | Tìm chuyến, giữ ghế 10p, thanh toán VNPay/COD, vé QR, theo dõi GPS, đánh giá |
| **Customer 2** | `khach2@gmail.vn` | Khách hàng thứ 2 để kiểm thử tranh chấp giữ ghế đồng thời (`AT04`) |
| **BusOperator 1** | `operator@phuongtrang.vn` | Quản lý Nhà xe Phương Trang (FUTA Bus Lines) |
| **BusOperator 2** | `operator@thanhbuoi.vn` | Quản lý Nhà xe Thành Bưởi (kiểm thử cô lập dữ liệu Multi-tenant `AT02`) |
| **Driver** | `driver1@phuongtrang.vn` | Tài xế Nguyễn Văn Tài — Quét QR check-in, cập nhật trạng thái chuyến, phát GPS |
| **Admin** | `admin@busticket.vn` | Quản trị hệ thống — Duyệt nhà xe, hoàn tiền, báo cáo doanh thu, kiểm tra `AT01`–`AT12` |

---

## 3. Hướng dẫn Chạy Dự án

1. **Chạy Backend (`webAPI`)**:
   ```powershell
   dotnet run --project webAPI/webAPI.csproj --urls "http://0.0.0.0:5284"
   ```
   - Swagger UI: `http://localhost:5284/swagger`
   - Cổng Web quản trị: `http://localhost:5284/`
   - Kiểm tra nhanh 12 tiêu chí nghiệm thu `AT01`–`AT12`: `http://localhost:5284/api/admin/acceptance-criteria`

2. **Chạy Ứng dụng Flutter**:
   ```powershell
   flutter pub get
   flutter run
   ```

3. **Kết nối Điện thoại Android thật qua cáp USB**:
   ```powershell
   adb reverse tcp:5284 tcp:5284
   ```
   *(Ứng dụng cũng tự động fallback sang IP LAN Wi-Fi `http://192.168.1.10:5284` hoặc `http://10.0.2.2:5284` cho máy ảo).*
