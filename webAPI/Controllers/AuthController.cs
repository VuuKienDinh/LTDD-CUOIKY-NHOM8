using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using webAPI.Data;
using webAPI.Models;
using webAPI.Services;

namespace webAPI.Controllers
{
    [ApiController]
    [Route("api")]
    public class AuthController : ControllerBase
    {
        private readonly BusBookingDbContext _db;
        private readonly IConfiguration _config;

        public AuthController(BusBookingDbContext db, IConfiguration config)
        {
            _db = db;
            _config = config;
        }

        [HttpGet("auth/demo-accounts")]
        public IActionResult GetDemoAccounts()
        {
            return Ok(new[]
            {
                new { Role = "Customer (Khách hàng)", Email = "customer@gmail.vn", Password = "123456", Description = "Tìm chuyến, chọn ghế, giữ chỗ, thanh toán VNPay/COD, xem vé QR, theo dõi GPS" },
                new { Role = "BusOperator (Nhà xe Phương Trang)", Email = "operator@phuongtrang.vn", Password = "123456", Description = "Quản lý xe, sơ đồ ghế, tuyến, tài xế, tạo chuyến, thu COD, xem báo cáo nhà xe" },
                new { Role = "Driver (Tài xế Phương Trang)", Email = "driver@phuongtrang.vn", Password = "123456", Description = "Xem chuyến được giao, đổi trạng thái chuyến, quét QR check-in, phát GPS, báo sự cố" },
                new { Role = "Staff (Nhân viên Phương Trang)", Email = "staff@phuongtrang.vn", Password = "123456", Description = "Quét vé QR, xác nhận thu tiền COD, tra cứu đơn đặt vé, xử lý hỗ trợ" },
                new { Role = "BusOperator (Nhà xe Thành Bưởi)", Email = "operator@thanhbuoi.vn", Password = "123456", Description = "Kiểm tra phân tách dữ liệu Multi-tenant (AT02)" },
                new { Role = "Admin (Quản trị nền tảng)", Email = "admin@busticket.vn", Password = "123456", Description = "Duyệt nhà xe (Kumho Samco đang chờ duyệt), hoàn tiền, khóa/mở user, báo cáo tổng, AuditLog" }
            });
        }

        [HttpPost("auth/register")]
        public async Task<IActionResult> Register([FromBody] RegisterDto dto)
        {
            if (string.IsNullOrWhiteSpace(dto.Email) || string.IsNullOrWhiteSpace(dto.Password) || string.IsNullOrWhiteSpace(dto.FullName))
            {
                return BadRequest(new { message = "Vui lòng nhập đầy đủ họ tên, email và mật khẩu." });
            }

            var normalizedEmail = dto.Email.Trim().ToLowerInvariant();
            if (await _db.Users.AnyAsync(u => u.Email == normalizedEmail))
            {
                return Conflict(new { message = "Email này đã được đăng ký (BR01)." });
            }

            var normalizedPhone = new string((dto.Phone ?? "").Where(char.IsDigit).ToArray());
            if (string.IsNullOrEmpty(normalizedPhone)) normalizedPhone = "0900000000";

            var user = new User
            {
                FullName = dto.FullName.Trim(),
                Email = normalizedEmail,
                Phone = normalizedPhone,
                PasswordHash = SecurityHelper.HashPassword(dto.Password),
                IsActive = true
            };

            _db.Users.Add(user);
            await _db.SaveChangesAsync();

            // AT01: Người dùng tự đăng ký luôn chỉ nhận quyền Customer, không tự nâng quyền
            var customerRole = await _db.Roles.FirstAsync(r => r.RoleName == RoleNames.Customer);
            _db.UserRoles.Add(new UserRole
            {
                UserId = user.UserId,
                RoleId = customerRole.RoleId
            });
            await _db.SaveChangesAsync();

            return await IssueAuthResponseAsync(user);
        }

        [HttpPost("auth/login")]
        public async Task<IActionResult> Login([FromBody] LoginDto dto)
        {
            var normalizedEmail = (dto.Email ?? "").Trim().ToLowerInvariant();
            var user = await _db.Users
                .FirstOrDefaultAsync(u => u.Email == normalizedEmail);

            if (user == null || !SecurityHelper.VerifyPassword(dto.Password ?? "", user.PasswordHash))
            {
                return Unauthorized(new { message = "Email hoặc mật khẩu không chính xác." });
            }

            if (!user.IsActive)
            {
                return StatusCode(403, new { message = "Tài khoản đã bị khóa bởi quản trị viên." });
            }

            return await IssueAuthResponseAsync(user);
        }

        [Authorize]
        [HttpPost("auth/logout")]
        public async Task<IActionResult> Logout()
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var activeTokens = await _db.RefreshTokens
                .Where(t => t.UserId == userId && t.RevokedAt == null)
                .ToListAsync();
            foreach (var t in activeTokens)
            {
                t.RevokedAt = DateTime.UtcNow;
            }
            await _db.SaveChangesAsync();
            return Ok(new { message = "Đã đăng xuất và thu hồi refresh token." });
        }

        [Authorize]
        [HttpGet("auth/me")]
        public async Task<IActionResult> GetMe()
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var user = await _db.Users.FindAsync(userId);
            if (user == null) return NotFound();

            var userRoles = await _db.UserRoles
                .Include(ur => ur.Role)
                .Include(ur => ur.Company)
                .Where(ur => ur.UserId == userId)
                .ToListAsync();

            var driver = await _db.Drivers.FirstOrDefaultAsync(d => d.UserId == userId);

            return Ok(new
            {
                user.UserId,
                user.FullName,
                user.Email,
                user.Phone,
                user.NoShowCount,
                user.CreatedAt,
                Roles = userRoles.Select(ur => ur.Role!.RoleName).Distinct().ToList(),
                CompanyId = userRoles.FirstOrDefault(ur => ur.CompanyId.HasValue)?.CompanyId,
                CompanyName = userRoles.FirstOrDefault(ur => ur.Company != null)?.Company?.Name,
                DriverId = driver?.DriverId
            });
        }

        [Authorize]
        [HttpPut("auth/profile")]
        public async Task<IActionResult> UpdateProfile([FromBody] UpdateProfileDto dto)
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var user = await _db.Users.FindAsync(userId);
            if (user == null) return NotFound();

            if (!string.IsNullOrWhiteSpace(dto.FullName))
                user.FullName = dto.FullName.Trim();
            if (!string.IsNullOrWhiteSpace(dto.Phone))
                user.Phone = new string(dto.Phone.Where(char.IsDigit).ToArray());

            await _db.SaveChangesAsync();
            return Ok(new { message = "Cập nhật hồ sơ cá nhân thành công (FR02).", user.FullName, user.Phone });
        }

        [Authorize]
        [HttpPost("auth/change-password")]
        public async Task<IActionResult> ChangePassword([FromBody] ChangePasswordDto dto)
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var user = await _db.Users.FindAsync(userId);
            if (user == null) return NotFound();

            if (!SecurityHelper.VerifyPassword(dto.CurrentPassword ?? "", user.PasswordHash))
            {
                return BadRequest(new { message = "Mật khẩu hiện tại không chính xác." });
            }
            if (string.IsNullOrWhiteSpace(dto.NewPassword) || dto.NewPassword.Length < 6)
            {
                return BadRequest(new { message = "Mật khẩu mới phải có ít nhất 6 ký tự." });
            }

            user.PasswordHash = SecurityHelper.HashPassword(dto.NewPassword);
            await _db.SaveChangesAsync();
            return Ok(new { message = "Đổi mật khẩu thành công (FR01)!" });
        }

        // Section 10.1, FR01: Cấp mới AccessToken bằng RefreshToken (Token Rotation)
        [HttpPost("auth/refresh")]
        public async Task<IActionResult> RefreshAccessToken([FromBody] RefreshTokenRequestDto dto)
        {
            if (string.IsNullOrWhiteSpace(dto.RefreshToken))
            {
                return BadRequest(new { message = "Thiếu RefreshToken." });
            }

            var hash = SecurityHelper.ComputeSha256(dto.RefreshToken.Trim());
            var tokenRecord = await _db.RefreshTokens
                .Include(rt => rt.User)
                .FirstOrDefaultAsync(rt => rt.TokenHash == hash && rt.RevokedAt == null && rt.ExpiresAt > DateTime.UtcNow);

            if (tokenRecord == null || tokenRecord.User == null || !tokenRecord.User.IsActive)
            {
                return Unauthorized(new { message = "RefreshToken không hợp lệ hoặc đã hết hạn." });
            }

            tokenRecord.RevokedAt = DateTime.UtcNow;
            await _db.SaveChangesAsync();

            return await IssueAuthResponseAsync(tokenRecord.User);
        }

        // Section 10.1: Quản lý thiết bị nhận thông báo đẩy (UserDevices)
        [Authorize]
        [HttpGet("auth/devices")]
        public async Task<IActionResult> GetMyDevices()
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var devices = await _db.UserDevices
                .Where(d => d.UserId == userId)
                .OrderByDescending(d => d.LastSeenAt)
                .ToListAsync();
            return Ok(devices);
        }

        [Authorize]
        [HttpPost("auth/devices")]
        public async Task<IActionResult> RegisterDevice([FromBody] RegisterDeviceDto dto)
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var fcm = string.IsNullOrWhiteSpace(dto.FcmToken) ? $"FCM-ANDROID-{userId}-{DateTime.UtcNow:yyyyMMdd}" : dto.FcmToken.Trim();
            var platform = string.IsNullOrWhiteSpace(dto.DevicePlatform) ? "Android" : dto.DevicePlatform.Trim();

            var existing = await _db.UserDevices.FirstOrDefaultAsync(d => d.UserId == userId && d.FcmToken == fcm);
            if (existing != null)
            {
                existing.DevicePlatform = platform;
                existing.LastSeenAt = DateTime.UtcNow;
            }
            else
            {
                _db.UserDevices.Add(new UserDevice
                {
                    UserId = userId,
                    FcmToken = fcm,
                    DevicePlatform = platform,
                    LastSeenAt = DateTime.UtcNow
                });
            }

            await _db.SaveChangesAsync();
            return Ok(new { message = "Đã đồng bộ thiết bị nhận thông báo đẩy (UserDevices)." });
        }

        // UC14, FR03: Đăng ký hồ sơ nhà xe mới (trạng thái Pending chờ Admin duyệt)
        [Authorize]
        [HttpPost("operator/register-company")]
        public async Task<IActionResult> RegisterBusCompany([FromBody] RegisterCompanyDto dto)
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            if (string.IsNullOrWhiteSpace(dto.Name) || string.IsNullOrWhiteSpace(dto.TaxCode))
            {
                return BadRequest(new { message = "Vui lòng nhập tên nhà xe và mã số thuế." });
            }

            var company = new BusCompany
            {
                Name = dto.Name.Trim(),
                TaxCode = dto.TaxCode.Trim(),
                Address = dto.Address?.Trim() ?? "",
                Phone = dto.Phone?.Trim() ?? "",
                Email = dto.Email?.Trim(),
                RepresentativeName = dto.RepresentativeName?.Trim(),
                Description = dto.Description?.Trim(),
                Status = CompanyStatuses.Pending,
                AllowCod = true,
                MaxCodSeatsPerBooking = 4,
                SeatHoldMinutes = 10
            };
            _db.BusCompanies.Add(company);
            await _db.SaveChangesAsync();

            var opRole = await _db.Roles.FirstAsync(r => r.RoleName == RoleNames.BusOperator);
            bool alreadyHasRole = await _db.UserRoles.AnyAsync(ur => ur.UserId == userId && ur.RoleId == opRole.RoleId && ur.CompanyId == company.CompanyId);
            if (!alreadyHasRole)
            {
                _db.UserRoles.Add(new UserRole
                {
                    UserId = userId,
                    RoleId = opRole.RoleId,
                    CompanyId = company.CompanyId
                });
            }

            _db.CompanyMembers.Add(new CompanyMember
            {
                CompanyId = company.CompanyId,
                UserId = userId,
                MemberRole = RoleNames.BusOperator,
                Status = "Active"
            });

            _db.AuditLogs.Add(new AuditLog
            {
                UserId = userId,
                CompanyId = company.CompanyId,
                Action = "RegisterBusCompany",
                EntityName = "BusCompany",
                EntityId = company.CompanyId.ToString(),
                Details = $"Đăng ký hồ sơ nhà xe mới '{company.Name}' (MST: {company.TaxCode}) ở trạng thái Pending chờ Admin duyệt."
            });

            await _db.SaveChangesAsync();
            return Ok(new
            {
                message = $"Đã gửi hồ sơ đăng ký nhà xe '{company.Name}'. Trạng thái hiện tại: Pending (Chờ Admin duyệt - UC14, FR03).",
                company
            });
        }

        // UC31, Section 5.13: Khách hàng gửi và xem yêu cầu hỗ trợ (SupportRequests)
        [Authorize]
        [HttpGet("support-requests/my")]
        public async Task<IActionResult> GetMySupportRequests()
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var list = await _db.SupportRequests
                .Where(s => s.UserId == userId)
                .OrderByDescending(s => s.CreatedAt)
                .ToListAsync();
            return Ok(list);
        }

        [Authorize]
        [HttpPost("support-requests")]
        public async Task<IActionResult> CreateSupportRequest([FromBody] CreateSupportRequestDto dto)
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            if (string.IsNullOrWhiteSpace(dto.Subject) || string.IsNullOrWhiteSpace(dto.Content))
            {
                return BadRequest(new { message = "Vui lòng nhập tiêu đề và nội dung cần hỗ trợ." });
            }

            int? companyId = dto.CompanyId;
            if (dto.BookingId.HasValue && !companyId.HasValue)
            {
                var booking = await _db.Bookings.Include(b => b.Trip).FirstOrDefaultAsync(b => b.BookingId == dto.BookingId.Value);
                companyId = booking?.Trip?.CompanyId;
            }

            var req = new SupportRequest
            {
                UserId = userId,
                CompanyId = companyId,
                BookingId = dto.BookingId,
                Subject = dto.Subject.Trim(),
                Content = dto.Content.Trim(),
                Status = "Open",
                CreatedAt = DateTime.UtcNow
            };
            _db.SupportRequests.Add(req);
            await _db.SaveChangesAsync();

            return Ok(new { message = "Đã gửi yêu cầu hỗ trợ thành công (UC31).", req });
        }

        // Mở rộng nâng cao: Tích điểm Thành viên & Hạng thẻ (Loyalty Points & Tier)
        [Authorize]
        [HttpGet("auth/loyalty")]
        public async Task<IActionResult> GetMyLoyaltyProfile()
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var validBookings = await _db.Bookings
                .Include(b => b.Details)
                .Where(b => b.UserId == userId && (b.Status == BookingStatuses.Confirmed || b.Status == BookingStatuses.Completed))
                .ToListAsync();

            decimal totalSpent = validBookings.Sum(b => b.TotalAmount);
            int totalTickets = validBookings.Sum(b => b.Details.Count);
            int points = (int)Math.Floor(totalSpent / 1000m); // 1.000đ = 1 điểm thưởng

            string tier = points >= 2000 ? "Kim Cương (Diamond)"
                : points >= 800 ? "Vàng (Gold)"
                : points >= 300 ? "Bạc (Silver)"
                : "Thành viên Thân thiết (Member)";

            int nextTierPoints = points >= 2000 ? 2000 : points >= 800 ? 2000 : points >= 300 ? 800 : 300;
            var activePromos = await _db.Promotions
                .Where(p => p.IsActive && p.ExpiresAt > DateTime.UtcNow && p.UsedCount < p.UsageLimit)
                .OrderByDescending(p => p.DiscountValue)
                .ToListAsync();

            return Ok(new
            {
                UserId = userId,
                TotalBookings = validBookings.Count,
                TotalTickets = totalTickets,
                TotalSpent = totalSpent,
                LoyaltyPoints = points,
                NextTierPoints = nextTierPoints,
                TierName = tier,
                AvailablePromotions = activePromos
            });
        }

        // Đợt 2 - Tính năng #3: Danh bạ Hành khách thường đi (Saved Companions / Quick Fill)
        [Authorize]
        [HttpGet("auth/companions")]
        public async Task<IActionResult> GetMyCompanions()
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var list = await _db.SavedCompanions
                .Where(c => c.UserId == userId)
                .OrderByDescending(c => c.CreatedAt)
                .ToListAsync();
            return Ok(list);
        }

        [Authorize]
        [HttpPost("auth/companions")]
        public async Task<IActionResult> AddCompanion([FromBody] CreateCompanionDto dto)
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            if (string.IsNullOrWhiteSpace(dto.FullName) || string.IsNullOrWhiteSpace(dto.Phone))
            {
                return BadRequest(new { message = "Vui lòng nhập họ tên và số điện thoại người đi cùng." });
            }

            var comp = new SavedCompanion
            {
                UserId = userId,
                FullName = dto.FullName.Trim(),
                Phone = dto.Phone.Trim(),
                Relationship = string.IsNullOrWhiteSpace(dto.Relationship) ? "Gia đình" : dto.Relationship.Trim(),
                CreatedAt = DateTime.UtcNow
            };
            _db.SavedCompanions.Add(comp);
            await _db.SaveChangesAsync();
            return Ok(new { message = $"Đã lưu '{comp.FullName}' vào danh bạ hành khách thường đi!", companion = comp });
        }

        [Authorize]
        [HttpDelete("auth/companions/{id:int}")]
        public async Task<IActionResult> DeleteCompanion(int id)
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var comp = await _db.SavedCompanions.FirstOrDefaultAsync(c => c.CompanionId == id && c.UserId == userId);
            if (comp == null) return NotFound();
            _db.SavedCompanions.Remove(comp);
            await _db.SaveChangesAsync();
            return Ok(new { message = "Đã xóa khỏi danh bạ hành khách thường đi." });
        }

        private async Task<IActionResult> IssueAuthResponseAsync(User user)
        {
            var userRoles = await _db.UserRoles
                .Include(ur => ur.Role)
                .Include(ur => ur.Company)
                .Where(ur => ur.UserId == user.UserId)
                .ToListAsync();

            var roleNames = userRoles.Select(ur => ur.Role!.RoleName).Distinct().ToList();
            if (roleNames.Count == 0) roleNames.Add(RoleNames.Customer);

            int? companyId = userRoles.FirstOrDefault(ur => ur.CompanyId.HasValue)?.CompanyId;
            string? companyName = userRoles.FirstOrDefault(ur => ur.Company != null)?.Company?.Name;
            var driver = await _db.Drivers.FirstOrDefaultAsync(d => d.UserId == user.UserId);
            if (!companyId.HasValue && driver != null)
            {
                companyId = driver.CompanyId;
            }

            var accessToken = SecurityHelper.GenerateJwtToken(user, roleNames, companyId, driver?.DriverId, _config);
            var rawRefresh = Guid.NewGuid().ToString("N") + Guid.NewGuid().ToString("N");

            _db.RefreshTokens.Add(new RefreshToken
            {
                UserId = user.UserId,
                TokenHash = SecurityHelper.ComputeSha256(rawRefresh),
                ExpiresAt = DateTime.UtcNow.AddDays(14)
            });
            await _db.SaveChangesAsync();

            return Ok(new
            {
                AccessToken = accessToken,
                RefreshToken = rawRefresh,
                User = new
                {
                    user.UserId,
                    user.FullName,
                    user.Email,
                    user.Phone,
                    user.NoShowCount,
                    Roles = roleNames,
                    CompanyId = companyId,
                    CompanyName = companyName,
                    DriverId = driver?.DriverId
                }
            });
        }
    }

    public record RegisterDto(string FullName, string Email, string Phone, string Password);
    public record LoginDto(string Email, string Password);
    public record UpdateProfileDto(string FullName, string Phone);
    public record ChangePasswordDto(string CurrentPassword, string NewPassword);
    public record RegisterCompanyDto(string Name, string TaxCode, string? Address, string? Phone, string? Email, string? RepresentativeName, string? Description);
    public record CreateSupportRequestDto(int? BookingId, int? CompanyId, string Subject, string Content);
    public record RefreshTokenRequestDto(string RefreshToken);
    public record RegisterDeviceDto(string? FcmToken, string? DevicePlatform);
    public record CreateCompanionDto(string FullName, string Phone, string? Relationship);
}
