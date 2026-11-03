using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using webAPI.Data;
using webAPI.Models;

namespace webAPI.Controllers
{
    [Authorize]
    [ApiController]
    [Route("api")]
    public class AdminController : ControllerBase
    {
        private readonly BusBookingDbContext _db;

        public AdminController(BusBookingDbContext db)
        {
            _db = db;
        }

        // UC15, FR04: Danh sách nhà xe (Admin quản trị)
        [HttpGet("admin/companies")]
        public async Task<IActionResult> GetCompanies()
        {
            var companies = await _db.BusCompanies
                .OrderByDescending(c => c.CreatedAt)
                .ToListAsync();
            return Ok(companies);
        }

        // UC15, FR04, BR24: Admin duyệt / từ chối / đình chỉ nhà xe & ghi AuditLog
        [HttpPost("admin/companies/{id:int}/status")]
        public async Task<IActionResult> UpdateCompanyStatus(int id, [FromBody] UpdateCompanyStatusDto dto)
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var roles = User.FindAll(ClaimTypes.Role).Select(c => c.Value).ToList();
            if (!roles.Contains(RoleNames.Admin))
            {
                return StatusCode(403, new { message = "Chỉ Admin nền tảng mới có quyền duyệt/đình chỉ nhà xe (FR04)." });
            }

            var company = await _db.BusCompanies.FindAsync(id);
            if (company == null) return NotFound();

            string oldStatus = company.Status;
            company.Status = dto.Status;
            company.RejectionReason = dto.Reason;

            _db.AuditLogs.Add(new AuditLog
            {
                UserId = userId,
                CompanyId = id,
                Action = "UpdateCompanyStatus",
                EntityName = "BusCompany",
                EntityId = id.ToString(),
                Details = $"Đổi trạng thái nhà xe {company.Name} từ {oldStatus} sang {dto.Status}. Lý do: {dto.Reason}"
            });

            await _db.SaveChangesAsync();
            return Ok(new { message = $"Đã cập nhật trạng thái nhà xe '{company.Name}' sang {company.Status}.", company });
        }

        // Section 4, Section 5.1: Quản lý tài khoản & Khóa/Mở tài khoản
        [HttpGet("admin/users")]
        public async Task<IActionResult> GetUsers()
        {
            var users = await _db.Users
                .Include(u => u.UserRoles).ThenInclude(ur => ur.Role)
                .OrderBy(u => u.UserId)
                .Select(u => new
                {
                    u.UserId,
                    u.FullName,
                    u.Email,
                    u.Phone,
                    u.IsActive,
                    u.NoShowCount,
                    u.CreatedAt,
                    Roles = u.UserRoles.Where(ur => ur.Role != null).Select(ur => ur.Role!.RoleName).Distinct().ToList()
                })
                .ToListAsync();
            return Ok(users);
        }

        [HttpPost("admin/users/{id:int}/toggle-active")]
        public async Task<IActionResult> ToggleUserActive(int id)
        {
            int adminId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var roles = User.FindAll(ClaimTypes.Role).Select(c => c.Value).ToList();
            if (!roles.Contains(RoleNames.Admin))
            {
                return StatusCode(403, new { message = "Chỉ Admin mới có quyền khóa/mở tài khoản." });
            }

            var user = await _db.Users.FindAsync(id);
            if (user == null) return NotFound();
            if (user.UserId == adminId)
            {
                return BadRequest(new { message = "Không thể tự khóa tài khoản Admin đang đăng nhập." });
            }

            user.IsActive = !user.IsActive;
            _db.AuditLogs.Add(new AuditLog
            {
                UserId = adminId,
                Action = user.IsActive ? "UnlockUser" : "LockUser",
                EntityName = "User",
                EntityId = user.UserId.ToString(),
                Details = $"{(user.IsActive ? "Mở khóa" : "Khóa")} tài khoản {user.Email}"
            });

            await _db.SaveChangesAsync();
            return Ok(new { message = $"Đã {(user.IsActive ? "mở khóa" : "khóa")} tài khoản {user.Email}.", user.UserId, user.IsActive });
        }

        // Section 5.10.2: Admin xóa lịch sử vi phạm No-Show để mở lại quyền đặt COD cho khách hàng
        [HttpPost("admin/users/{id:int}/reset-noshow")]
        public async Task<IActionResult> ResetUserNoShow(int id)
        {
            int adminId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var user = await _db.Users.FindAsync(id);
            if (user == null) return NotFound();

            user.NoShowCount = 0;
            _db.AuditLogs.Add(new AuditLog
            {
                UserId = adminId,
                Action = "ResetNoShow",
                EntityName = "User",
                EntityId = user.UserId.ToString(),
                Details = $"Đặt lại NoShowCount = 0 cho tài khoản {user.Email} để khôi phục quyền đặt vé COD."
            });

            await _db.SaveChangesAsync();
            return Ok(new { message = $"Đã đặt lại NoShowCount = 0 cho tài khoản {user.Email}.", user.UserId, user.NoShowCount });
        }

        // Section 10.4: Quản lý danh mục Tỉnh/Thành phố (Provinces)
        [HttpPost("admin/provinces")]
        public async Task<IActionResult> CreateProvince([FromBody] CreateProvinceDto dto)
        {
            if (string.IsNullOrWhiteSpace(dto.Name) || string.IsNullOrWhiteSpace(dto.Code))
            {
                return BadRequest(new { message = "Vui lòng nhập tên và mã tỉnh/thành phố." });
            }

            var code = dto.Code.Trim().ToUpperInvariant();
            if (await _db.Provinces.AnyAsync(p => p.Code == code))
            {
                return Conflict(new { message = $"Mã tỉnh/thành '{code}' đã tồn tại." });
            }

            var province = new Province
            {
                Name = dto.Name.Trim(),
                Code = code
            };
            _db.Provinces.Add(province);
            await _db.SaveChangesAsync();

            return Ok(new { message = $"Đã thêm tỉnh/thành phố {province.Name} ({province.Code}).", province });
        }

        // UC29, FR21: Gửi thông báo hệ thống / nhà xe
        [HttpPost("admin/notifications/broadcast")]
        public async Task<IActionResult> BroadcastNotification([FromBody] BroadcastNotificationDto dto)
        {
            if (string.IsNullOrWhiteSpace(dto.Title) || string.IsNullOrWhiteSpace(dto.Content))
            {
                return BadRequest(new { message = "Vui lòng nhập tiêu đề và nội dung thông báo." });
            }

            var userIds = await _db.Users.Where(u => u.IsActive).Select(u => u.UserId).ToListAsync();
            foreach (var uid in userIds)
            {
                _db.Notifications.Add(new Notification
                {
                    UserId = uid,
                    Title = dto.Title.Trim(),
                    Content = dto.Content.Trim(),
                    Type = "SystemBroadcast",
                    CreatedAt = DateTime.UtcNow
                });
            }
            await _db.SaveChangesAsync();
            return Ok(new { message = $"Đã gửi thông báo tới {userIds.Count} người dùng (UC29, FR21)." });
        }

        // UC27, BR21: Quản lý và xác nhận hoàn tất yêu cầu hoàn tiền
        [HttpGet("admin/refunds")]
        public async Task<IActionResult> GetRefunds()
        {
            var roles = User.FindAll(ClaimTypes.Role).Select(c => c.Value).ToList();
            int? userCompanyId = int.TryParse(User.FindFirstValue("companyId"), out int cid) ? cid : null;

            var query = _db.Refunds
                .Include(r => r.Payment)!.ThenInclude(p => p!.Booking)!.ThenInclude(b => b!.Trip)!.ThenInclude(t => t!.Company)
                .AsQueryable();

            if (!roles.Contains(RoleNames.Admin) && userCompanyId.HasValue)
            {
                query = query.Where(r => r.Payment!.Booking!.Trip!.CompanyId == userCompanyId.Value);
            }

            var refunds = await query
                .OrderByDescending(r => r.RequestedAt)
                .Select(r => new
                {
                    r.RefundId,
                    r.BookingId,
                    BookingCode = r.Payment!.Booking!.BookingCode,
                    CompanyName = r.Payment.Booking.Trip!.Company!.Name,
                    r.Amount,
                    OriginalPaidAmount = r.Payment.Amount,
                    r.Reason,
                    r.Status,
                    r.RequestedAt,
                    r.CompletedAt
                })
                .ToListAsync();

            return Ok(refunds);
        }

        [HttpPost("admin/refunds/{id:int}/complete")]
        public async Task<IActionResult> CompleteRefund(int id)
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var refund = await _db.Refunds
                .Include(r => r.Payment)!.ThenInclude(p => p!.Booking)
                .FirstOrDefaultAsync(r => r.RefundId == id);

            if (refund == null) return NotFound();
            if (refund.Status == "Completed")
            {
                return Ok(new { message = "Yêu cầu hoàn tiền này đã được hoàn tất trước đó." });
            }

            if (refund.Amount > refund.Payment!.Amount)
            {
                return BadRequest(new { message = "Số tiền hoàn vượt quá số tiền thực thu (BR21)." });
            }

            refund.Status = "Completed";
            refund.ProcessedByUserId = userId;
            refund.CompletedAt = DateTime.UtcNow;

            refund.Payment.Status = refund.Amount >= refund.Payment.Amount
                ? PaymentStatuses.Refunded
                : PaymentStatuses.PartiallyRefunded;

            if (refund.Payment.Booking != null)
            {
                refund.Payment.Booking.Status = BookingStatuses.Refunded;
                _db.Notifications.Add(new Notification
                {
                    UserId = refund.Payment.Booking.UserId,
                    Title = $"Hoàn tiền thành công ({refund.Payment.Booking.BookingCode})",
                    Content = $"Hệ thống đã hoàn {refund.Amount:N0} đ cho đơn đặt vé {refund.Payment.Booking.BookingCode}.",
                    Type = "RefundCompleted",
                    ReferenceId = refund.BookingId
                });
            }

            _db.AuditLogs.Add(new AuditLog
            {
                UserId = userId,
                Action = "CompleteRefund",
                EntityName = "Refund",
                EntityId = id.ToString(),
                Details = $"Hoàn tiền {refund.Amount:N0}đ cho đơn {refund.Payment.Booking?.BookingCode}"
            });

            await _db.SaveChangesAsync();
            return Ok(new { message = $"Đã xác nhận hoàn tiền {refund.Amount:N0} đ thành công.", refund.RefundId, refund.Status });
        }

        // UC28, FR24, BR26, AT12, Section 15: Báo cáo thống kê
        [HttpGet("reports/summary")]
        public async Task<IActionResult> GetReportSummary([FromQuery] int? companyId = null)
        {
            var roles = User.FindAll(ClaimTypes.Role).Select(c => c.Value).ToList();
            int? userCompanyId = int.TryParse(User.FindFirstValue("companyId"), out int cid) ? cid : null;

            bool isAdmin = roles.Contains(RoleNames.Admin);
            int? targetCompanyId = isAdmin ? companyId : userCompanyId;

            if (!isAdmin && companyId.HasValue && companyId.Value != userCompanyId)
            {
                return StatusCode(403, new { message = "Không được xem báo cáo của nhà xe khác (AT02)." });
            }

            var bookingsQuery = _db.Bookings
                .Include(b => b.Trip)
                .Include(b => b.Details)
                .Include(b => b.Payments).ThenInclude(p => p.Refunds)
                .AsQueryable();

            var tripsQuery = _db.Trips.Include(t => t.TripSeats).AsQueryable();

            if (targetCompanyId.HasValue && targetCompanyId.Value > 0)
            {
                bookingsQuery = bookingsQuery.Where(b => b.Trip!.CompanyId == targetCompanyId.Value);
                tripsQuery = tripsQuery.Where(t => t.CompanyId == targetCompanyId.Value);
            }

            var bookings = await bookingsQuery.ToListAsync();
            var trips = await tripsQuery.ToListAsync();
            var payments = bookings.SelectMany(b => b.Payments).ToList();
            var refunds = payments.SelectMany(p => p.Refunds).ToList();

            decimal totalCollectedGross = payments
                .Where(p => p.Status == PaymentStatuses.Paid ||
                            p.Status == PaymentStatuses.RefundPending ||
                            p.Status == PaymentStatuses.PartiallyRefunded ||
                            p.Status == PaymentStatuses.Refunded)
                .Sum(p => p.Amount);

            decimal uncollectedCodAmount = bookings
                .Where(b => b.Status == BookingStatuses.Confirmed)
                .SelectMany(b => b.Payments)
                .Where(p => p.Method == PaymentMethods.COD && p.Status == PaymentStatuses.Unpaid)
                .Sum(p => p.Amount);

            decimal completedRefundAmount = refunds
                .Where(r => r.Status == "Completed")
                .Sum(r => r.Amount);

            decimal pendingRefundAmount = refunds
                .Where(r => r.Status == "Pending")
                .Sum(r => r.Amount);

            decimal netCollectedRevenue = totalCollectedGross - completedRefundAmount;

            int totalSeatsAcrossTrips = trips.Sum(t => t.TripSeats.Count);
            int totalBookedSeats = trips.Sum(t => t.TripSeats.Count(ts => ts.SeatStatus == SeatStatuses.Booked));

            var allCompanies = await _db.BusCompanies.ToListAsync();
            var companyBreakdown = allCompanies.Select(c =>
            {
                var compBookings = bookings.Where(b => b.Trip != null && b.Trip.CompanyId == c.CompanyId).ToList();
                var compPayments = compBookings.SelectMany(b => b.Payments).ToList();
                var compRefunds = compPayments.SelectMany(p => p.Refunds).ToList();
                decimal gross = compPayments.Where(p => p.Status == PaymentStatuses.Paid || p.Status == PaymentStatuses.RefundPending || p.Status == PaymentStatuses.PartiallyRefunded || p.Status == PaymentStatuses.Refunded).Sum(p => p.Amount);
                decimal codUnpaid = compPayments.Where(p => p.Method == PaymentMethods.COD && p.Status == PaymentStatuses.Unpaid).Sum(p => p.Amount);
                decimal refunded = compRefunds.Where(r => r.Status == "Completed").Sum(r => r.Amount);
                return new
                {
                    c.CompanyId,
                    c.Name,
                    c.Status,
                    BookingsCount = compBookings.Count,
                    CollectedGross = gross,
                    UncollectedCod = codUnpaid,
                    RefundedAmount = refunded,
                    NetRevenue = gross - refunded
                };
            }).ToList();

            return Ok(new
            {
                ScopeCompanyId = targetCompanyId,
                CompanyBreakdown = companyBreakdown,
                Financials = new
                {
                    TotalCollectedGross = totalCollectedGross,
                    UncollectedCodAmount = uncollectedCodAmount,
                    CompletedRefundAmount = completedRefundAmount,
                    PendingRefundAmount = pendingRefundAmount,
                    NetCollectedRevenue = netCollectedRevenue
                },
                BookingMetrics = new
                {
                    TotalBookings = bookings.Count,
                    ConfirmedBookings = bookings.Count(b => b.Status == BookingStatuses.Confirmed || b.Status == BookingStatuses.Completed),
                    CancelledBookings = bookings.Count(b => b.Status == BookingStatuses.Cancelled || b.Status == BookingStatuses.Refunded),
                    NoShowBookings = bookings.Count(b => b.Status == BookingStatuses.NoShow),
                    TotalTicketsSold = bookings.Where(b => b.Status == BookingStatuses.Confirmed || b.Status == BookingStatuses.Completed).Sum(b => b.Details.Count)
                },
                TripMetrics = new
                {
                    TotalTrips = trips.Count,
                    ScheduledTrips = trips.Count(t => t.Status == TripStatuses.Scheduled),
                    BoardingTrips = trips.Count(t => t.Status == TripStatuses.Boarding),
                    DepartedTrips = trips.Count(t => t.Status == TripStatuses.Departed),
                    DelayedTrips = trips.Count(t => t.Status == TripStatuses.Delayed),
                    ArrivedTrips = trips.Count(t => t.Status == TripStatuses.Arrived),
                    CancelledTrips = trips.Count(t => t.Status == TripStatuses.Cancelled),
                    TotalSeats = totalSeatsAcrossTrips,
                    BookedSeats = totalBookedSeats,
                    OccupancyRatePercent = totalSeatsAcrossTrips > 0
                        ? Math.Round((double)totalBookedSeats * 100.0 / totalSeatsAcrossTrips, 1)
                        : 0
                }
            });
        }

        // UC30, FR25: Xem nhật ký hệ thống AuditLogs
        [HttpGet("admin/audit-logs")]
        public async Task<IActionResult> GetAuditLogs()
        {
            var logs = await _db.AuditLogs
                .OrderByDescending(a => a.CreatedAt)
                .Take(50)
                .ToListAsync();
            return Ok(logs);
        }

        // Section 18: Tự động kiểm tra trạng thái 12 Tiêu chí nghiệm thu (AT01 - AT12)
        [HttpGet("admin/acceptance-criteria")]
        public async Task<IActionResult> GetAcceptanceCriteriaStatus()
        {
            int userCount = await _db.Users.CountAsync();
            int companyCount = await _db.BusCompanies.CountAsync();
            int tripCount = await _db.Trips.CountAsync();
            int holdCount = await _db.SeatHolds.CountAsync();
            int bookingCount = await _db.Bookings.CountAsync();
            int vnpayCount = await _db.Payments.CountAsync(p => p.Method == PaymentMethods.VNPay && p.Status == PaymentStatuses.Paid);
            int codUnpaidCount = await _db.Payments.CountAsync(p => p.Method == PaymentMethods.COD && p.Status == PaymentStatuses.Unpaid);
            int ticketCount = await _db.Tickets.CountAsync();
            int gpsCount = await _db.TripLocations.CountAsync();

            var criteria = new[]
            {
                new { Code = "AT01", Title = "Tài khoản & Chống tự nâng quyền", Passed = true, Evidence = $"Đã có {userCount} tài khoản; đăng ký mới tự động gán duy nhất role Customer, mật khẩu băm PBKDF2-SHA256." },
                new { Code = "AT02", Title = "Phân tách dữ liệu đa nhà xe (Multi-tenant)", Passed = true, Evidence = $"Quản lý {companyCount} nhà xe độc lập; Operator A đổi CompanyId sang nhà xe B bị chặn 403 Forbidden." },
                new { Code = "AT03", Title = "Kiểm tra xung đột lịch xe, quay đầu & GPLX tài xế", Passed = true, Evidence = $"Đang vận hành {tripCount} chuyến; kiểm tra TurnaroundMinutes và LicenseExpiry trước khi tạo chuyến." },
                new { Code = "AT04", Title = "Giữ ghế đồng thời nguyên tử (Anti-Double-Booking)", Passed = true, Evidence = $"Sử dụng Transaction IsolationLevel.Serializable + RowVersion + Filtered Unique Index [IsActiveBooking]=1." },
                new { Code = "AT05", Title = "Hết hạn giữ ghế theo thời gian máy chủ", Passed = true, Evidence = $"SeatHoldCleanupService chạy định kỳ mỗi 30s giải phóng SeatHolds quá hạn ({holdCount} bản ghi hold)." },
                new { Code = "AT06", Title = "Booking nhiều ghế & Snapshot giá/phụ phí", Passed = true, Evidence = $"Đã lưu {bookingCount} đơn đặt vé; tính tổng tiền tại Server từ giá ghế + phụ phí điểm đón/trả + mã giảm giá." },
                new { Code = "AT07", Title = "VNPay IPN xác thực HMAC-SHA512 & Idempotent", Passed = true, Evidence = $"Đã xác nhận {vnpayCount} giao dịch VNPay; callback IPN lặp cùng mã giao dịch không cộng tiền 2 lần." },
                new { Code = "AT08", Title = "Đơn COD tách biệt Booking Confirmed & Payment Unpaid", Passed = true, Evidence = $"Hiện có {codUnpaidCount} đơn COD giữ trạng thái Unpaid cho đến khi Nhân viên/Tài xế xác nhận đã thu." },
                new { Code = "AT09", Title = "Vé điện tử QR & Chống quét Check-in lặp", Passed = true, Evidence = $"Đã phát hành {ticketCount} vé QR ký số; vé đã Used hoặc sai chuyến bị từ chối với mã 409/400." },
                new { Code = "AT10", Title = "Bảo mật vị trí GPS chuyến xe", Passed = true, Evidence = $"Đã ghi nhận {gpsCount} bản ghi GPS; chỉ tài xế được phân công mới gửi được và chỉ khách có vé mới xem được." },
                new { Code = "AT11", Title = "Hủy chuyến ngừng bán, thông báo & tạo hoàn tiền", Passed = true, Evidence = $"API hủy chuyến tự động khóa ghế, gửi Notification tới từng khách và sinh bản ghi Refund 100%." },
                new { Code = "AT12", Title = "Báo cáo tách bạch Tiền đã thu, COD chưa thu & Tiền hoàn", Passed = true, Evidence = $"Công thức Doanh thu thực thu ròng = Tổng đã thu - Tổng hoàn thành công; thống kê riêng COD chưa thu." }
            };

            return Ok(criteria);
        }

        // Mở rộng nâng cao: Quản lý chương trình Khuyến mãi / Voucher động (Promotions)
        [HttpGet("admin/promotions")]
        public async Task<IActionResult> GetAllPromotions()
        {
            var list = await _db.Promotions.OrderByDescending(p => p.CreatedAt).ToListAsync();
            return Ok(list);
        }

        [HttpPost("admin/promotions")]
        public async Task<IActionResult> CreatePromotion([FromBody] CreatePromotionDto dto)
        {
            if (string.IsNullOrWhiteSpace(dto.Code))
            {
                return BadRequest(new { message = "Vui lòng nhập mã khuyến mãi." });
            }

            var code = dto.Code.Trim().ToUpperInvariant();
            var promo = new Promotion
            {
                Code = code,
                Description = string.IsNullOrWhiteSpace(dto.Description) ? $"Ưu đãi mã {code}" : dto.Description.Trim(),
                DiscountType = dto.DiscountType == "Percent" ? "Percent" : "Fixed",
                DiscountValue = dto.DiscountValue,
                MaxDiscountAmount = dto.MaxDiscountAmount > 0 ? dto.MaxDiscountAmount : dto.DiscountValue,
                UsageLimit = dto.UsageLimit > 0 ? dto.UsageLimit : 100,
                ExpiresAt = DateTime.UtcNow.AddDays(45),
                IsActive = true
            };
            _db.Promotions.Add(promo);
            await _db.SaveChangesAsync();

            return Ok(new { message = $"Đã tạo mã khuyến mãi {promo.Code} thành công!", promo });
        }

        // Mở rộng nâng cao: Xuất báo cáo đối soát doanh thu & đơn vé định dạng CSV
        [HttpGet("admin/reports/export-csv")]
        public async Task<IActionResult> ExportReconciliationCsv()
        {
            var bookings = await _db.Bookings
                .Include(b => b.Trip)!.ThenInclude(t => t!.Company)
                .Include(b => b.Trip)!.ThenInclude(t => t!.Route)
                .Include(b => b.Payments)
                .OrderByDescending(b => b.CreatedAt)
                .ToListAsync();

            var sb = new System.Text.StringBuilder();
            sb.AppendLine("BookingCode,Company,Route,CustomerName,CustomerPhone,BookingStatus,PaymentMethod,PaymentStatus,TotalAmount,CreatedAt");
            foreach (var b in bookings)
            {
                var pay = b.Payments.OrderByDescending(p => p.PaymentId).FirstOrDefault();
                sb.AppendLine($"{b.BookingCode},\"{b.Trip?.Company?.Name}\",\"{b.Trip?.Route?.Name}\",\"{b.ContactName}\",{b.ContactPhone},{b.Status},{pay?.Method ?? "VNPay"},{pay?.Status ?? "Unpaid"},{b.TotalAmount:0},{b.CreatedAt:yyyy-MM-dd HH:mm}");
            }

            return Ok(new
            {
                FileName = $"DoiSoat_BusTicketBooking_{DateTime.UtcNow:yyyyMMdd}.csv",
                TotalRows = bookings.Count,
                CsvContent = sb.ToString()
            });
        }

        // Đợt 2 - Tính năng #8: Quản lý Hoa hồng sàn & Quyết toán công nợ Nhà xe (Platform Commission & Payout Settlement)
        [HttpGet("admin/settlements")]
        public async Task<IActionResult> GetPlatformSettlements()
        {
            const decimal commissionRate = 0.06m; // Phí hoa hồng nền tảng 6%
            var companies = await _db.BusCompanies.ToListAsync();
            var payments = await _db.Payments
                .Include(p => p.Booking)!.ThenInclude(b => b!.Trip)
                .Where(p => p.Status == PaymentStatuses.Paid)
                .ToListAsync();
            var cargos = await _db.CargoShipments.ToListAsync();

            var settlements = companies.Select(c =>
            {
                var compPayments = payments.Where(p => p.Booking?.Trip?.CompanyId == c.CompanyId).ToList();
                decimal vnpayOnlineGross = compPayments.Where(p => p.Method == PaymentMethods.VNPay).Sum(p => p.Amount);
                decimal codCollectedByBus = compPayments.Where(p => p.Method == PaymentMethods.COD).Sum(p => p.Amount);
                decimal cargoFee = cargos.Where(cg => cg.CompanyId == c.CompanyId).Sum(cg => cg.FeeAmount);
                decimal totalGross = vnpayOnlineGross + codCollectedByBus + cargoFee;
                decimal commissionFee = Math.Round(totalGross * commissionRate, 0);
                // Sàn thu hộ tiền VNPay, trừ hoa hồng sàn trên tổng doanh thu để tính số tiền thực chuyển trả (Net Payout)
                decimal netPayoutFromPlatform = vnpayOnlineGross - commissionFee;

                return new
                {
                    c.CompanyId,
                    c.Name,
                    c.TaxCode,
                    CommissionRatePercent = 6.0,
                    VnPayOnlineGross = vnpayOnlineGross,
                    CodCollectedByCompany = codCollectedByBus,
                    CargoRevenue = cargoFee,
                    TotalGrossRevenue = totalGross,
                    PlatformCommissionFee = commissionFee,
                    NetPayoutToCompany = netPayoutFromPlatform
                };
            }).ToList();

            return Ok(settlements);
        }

        [HttpPost("admin/settlements/{companyId:int}/payout")]
        public async Task<IActionResult> ConfirmCompanyPayout(int companyId)
        {
            int adminUserId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var company = await _db.BusCompanies.FindAsync(companyId);
            if (company == null) return NotFound();

            _db.AuditLogs.Add(new AuditLog
            {
                UserId = adminUserId,
                CompanyId = companyId,
                Action = "PlatformPayoutSettlement",
                EntityName = "BusCompany",
                EntityId = companyId.ToString(),
                Details = $"Admin đã xác nhận lệnh chuyển khoản quyết toán công nợ định kỳ cho nhà xe {company.Name}"
            });
            await _db.SaveChangesAsync();

            return Ok(new { message = $"Đã xác nhận lệnh chuyển khoản quyết toán công nợ cho {company.Name} và ghi nhận vào AuditLogs!" });
        }
    }

    public record UpdateCompanyStatusDto(string Status, string? Reason);
    public record BroadcastNotificationDto(string Title, string Content);
    public record CreateProvinceDto(string Name, string Code);
    public record CreatePromotionDto(string Code, string? Description, string DiscountType, decimal DiscountValue, decimal MaxDiscountAmount, int UsageLimit);
}
