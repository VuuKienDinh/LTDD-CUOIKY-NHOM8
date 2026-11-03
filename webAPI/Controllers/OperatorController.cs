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
    [Route("api/operator")]
    public class OperatorController : ControllerBase
    {
        private readonly BusBookingDbContext _db;

        public OperatorController(BusBookingDbContext db)
        {
            _db = db;
        }

        private (int userId, int? companyId, bool isAdmin) GetOperatorContext()
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var roles = User.FindAll(ClaimTypes.Role).Select(c => c.Value).ToList();
            bool isAdmin = roles.Contains(RoleNames.Admin);
            int? companyId = int.TryParse(User.FindFirstValue("companyId"), out int cid) ? cid : null;
            return (userId, companyId, isAdmin);
        }

        // AT02, BR03: Operator chỉ xem dữ liệu thuộc CompanyId của mình
        [HttpGet("dashboard")]
        public async Task<IActionResult> GetDashboard([FromQuery] int? requestedCompanyId = null)
        {
            var (_, userCompanyId, isAdmin) = GetOperatorContext();
            if (!isAdmin && !userCompanyId.HasValue)
            {
                return StatusCode(403, new { message = "Tài khoản không thuộc nhà xe nào (BR03)." });
            }

            if (!isAdmin && requestedCompanyId.HasValue && requestedCompanyId.Value != userCompanyId!.Value)
            {
                return StatusCode(403, new { message = "Vi phạm phạm vi nhà xe: Bạn không được truy cập dữ liệu của nhà xe khác (AT02, BR03)." });
            }

            int companyId = isAdmin ? (requestedCompanyId ?? userCompanyId ?? 1) : userCompanyId!.Value;
            var company = await _db.BusCompanies.FindAsync(companyId);
            if (company == null) return NotFound();

            var buses = await _db.Buses
                .Where(b => b.CompanyId == companyId)
                .OrderByDescending(b => b.BusId)
                .ToListAsync();

            var drivers = await _db.Drivers
                .Where(d => d.CompanyId == companyId)
                .OrderByDescending(d => d.DriverId)
                .ToListAsync();

            var routes = await _db.Routes
                .Include(r => r.OriginProvince)
                .Include(r => r.DestinationProvince)
                .Include(r => r.Stops)
                .Where(r => r.CompanyId == companyId)
                .ToListAsync();

            var trips = await _db.Trips
                .Include(t => t.Route)
                .Include(t => t.Bus)
                .Include(t => t.TripSeats)
                .Include(t => t.DriverAssignments).ThenInclude(da => da.Driver)
                .Where(t => t.CompanyId == companyId)
                .OrderByDescending(t => t.DepartureAt)
                .ToListAsync();

            var bookings = await _db.Bookings
                .Include(b => b.Trip)!.ThenInclude(t => t!.Route)
                .Include(b => b.Details)
                .Include(b => b.Payments)
                .Where(b => b.Trip!.CompanyId == companyId)
                .OrderByDescending(b => b.CreatedAt)
                .Take(40)
                .ToListAsync();

            var supportRequests = await _db.SupportRequests
                .Include(s => s.User)
                .Where(s => s.CompanyId == companyId || s.CompanyId == null)
                .OrderByDescending(s => s.CreatedAt)
                .Take(30)
                .Select(s => new
                {
                    s.RequestId,
                    s.UserId,
                    CustomerName = s.User != null ? s.User.FullName : "Khách hàng",
                    CustomerPhone = s.User != null ? s.User.Phone : "",
                    s.BookingId,
                    s.Subject,
                    s.Content,
                    s.Status,
                    s.ReplyContent,
                    s.CreatedAt,
                    s.UpdatedAt
                })
                .ToListAsync();

            var staffMembers = await _db.CompanyMembers
                .Include(cm => cm.User)
                .Where(cm => cm.CompanyId == companyId)
                .Select(cm => new
                {
                    cm.CompanyMemberId,
                    cm.UserId,
                    FullName = cm.User != null ? cm.User.FullName : "",
                    Email = cm.User != null ? cm.User.Email : "",
                    Phone = cm.User != null ? cm.User.Phone : "",
                    cm.MemberRole,
                    cm.Status,
                    cm.JoinedAt
                })
                .ToListAsync();

            return Ok(new
            {
                Company = company,
                Buses = buses,
                Drivers = drivers,
                StaffMembers = staffMembers,
                Routes = routes.Select(r => new
                {
                    r.RouteId,
                    r.Name,
                    r.OriginProvinceId,
                    OriginProvince = r.OriginProvince?.Name,
                    r.DestinationProvinceId,
                    DestinationProvince = r.DestinationProvince?.Name,
                    r.DistanceKm,
                    r.EstimatedDurationMinutes,
                    Stops = r.Stops.OrderBy(s => s.Sequence).Select(s => new { s.RouteStopId, s.StopName, s.Address, s.StopType, s.OffsetMinutes, s.Surcharge })
                }),
                Trips = trips.Select(t => new
                {
                    t.TripId,
                    t.RouteId,
                    RouteName = t.Route?.Name,
                    t.BusId,
                    PlateNumber = t.Bus?.PlateNumber,
                    BusType = t.Bus?.BusType,
                    t.DepartureAt,
                    t.ArrivalEstimate,
                    t.BasePrice,
                    t.Status,
                    TotalSeats = t.TripSeats.Count,
                    BookedSeats = t.TripSeats.Count(ts => ts.SeatStatus == SeatStatuses.Booked),
                    AvailableSeats = t.TripSeats.Count(ts => ts.SeatStatus == SeatStatuses.Available),
                    Drivers = t.DriverAssignments.Where(da => da.ReleasedAt == null && da.Driver != null).Select(da => da.Driver!.FullName).ToList()
                }),
                Bookings = bookings.Select(b => new
                {
                    b.BookingId,
                    b.BookingCode,
                    b.TripId,
                    RouteName = b.Trip?.Route?.Name,
                    b.ContactName,
                    b.ContactPhone,
                    b.TotalAmount,
                    b.Status,
                    b.CreatedAt,
                    Seats = b.Details.Select(d => d.SeatCode).ToList(),
                    PaymentMethod = b.Payments.OrderByDescending(p => p.PaymentId).FirstOrDefault()?.Method ?? "VNPay",
                    PaymentStatus = b.Payments.OrderByDescending(p => p.PaymentId).FirstOrDefault()?.Status ?? PaymentStatuses.Unpaid
                }),
                SupportRequests = supportRequests
            });
        }

        // FR05, FR06, BR05: Thêm xe mới kèm sinh sơ đồ ghế
        [HttpPost("buses")]
        public async Task<IActionResult> CreateBus([FromBody] CreateBusDto dto)
        {
            var (_, userCompanyId, isAdmin) = GetOperatorContext();
            int companyId = isAdmin ? (dto.CompanyId ?? userCompanyId ?? 1) : (userCompanyId ?? 0);
            if (companyId <= 0) return StatusCode(403, new { message = "Không có quyền nhà xe." });

            var plate = dto.PlateNumber.Trim().ToUpperInvariant();
            if (await _db.Buses.AnyAsync(b => b.PlateNumber == plate))
            {
                return Conflict(new { message = $"Biển số xe {plate} đã tồn tại trên hệ thống (BR05)." });
            }

            int totalSeats = Math.Clamp(dto.TotalSeats <= 0 ? 20 : dto.TotalSeats, 4, 48);
            var bus = new Bus
            {
                CompanyId = companyId,
                PlateNumber = plate,
                BusType = string.IsNullOrWhiteSpace(dto.BusType) ? "Limousine Giường Nằm" : dto.BusType.Trim(),
                BrandModel = string.IsNullOrWhiteSpace(dto.BrandModel) ? "Thaco Mobihome" : dto.BrandModel.Trim(),
                TotalSeats = totalSeats,
                ManufactureYear = dto.ManufactureYear <= 2000 ? 2025 : dto.ManufactureYear,
                TurnaroundMinutes = 60,
                Status = BusStatuses.Active
            };
            _db.Buses.Add(bus);
            await _db.SaveChangesAsync();

            int perDeck = (totalSeats + 1) / 2;
            int created = 0;
            for (int deck = 1; deck <= 2; deck++)
            {
                string prefix = deck == 1 ? "A" : "B";
                for (int i = 1; i <= perDeck && created < totalSeats; i++)
                {
                    created++;
                    _db.BusSeats.Add(new BusSeat
                    {
                        BusId = bus.BusId,
                        SeatCode = $"{prefix}{i:D2}",
                        Deck = deck,
                        Row = (i - 1) / 2 + 1,
                        Column = (i - 1) % 2 + 1,
                        SeatType = i <= 4 ? "VIP" : "Standard",
                        PriceSurcharge = i <= 4 ? 20000 : 0,
                        IsActive = true
                    });
                }
            }
            await _db.SaveChangesAsync();

            return Ok(new { message = $"Đã thêm xe {bus.PlateNumber} và tạo sơ đồ {totalSeats} ghế.", bus.BusId, bus.PlateNumber });
        }

        // Section 5.3: Đổi trạng thái xe (Active / Maintenance / Inactive) & lưu lịch bảo trì
        [HttpPost("buses/{id:int}/status")]
        public async Task<IActionResult> UpdateBusStatus(int id, [FromBody] UpdateBusStatusDto dto)
        {
            var (_, userCompanyId, isAdmin) = GetOperatorContext();
            var bus = await _db.Buses.FindAsync(id);
            if (bus == null) return NotFound();
            if (!isAdmin && bus.CompanyId != userCompanyId)
            {
                return StatusCode(403, new { message = "Xe không thuộc nhà xe của bạn (AT02)." });
            }

            bus.Status = dto.Status;
            if (dto.Status == BusStatuses.Maintenance)
            {
                _db.BusMaintenances.Add(new BusMaintenance
                {
                    BusId = bus.BusId,
                    StartAt = DateTime.UtcNow,
                    EndAt = DateTime.UtcNow.AddDays(2),
                    Description = dto.Description ?? "Bảo dưỡng định kỳ",
                    Status = "InProgress"
                });
            }

            await _db.SaveChangesAsync();
            return Ok(new { message = $"Đã cập nhật trạng thái xe {bus.PlateNumber} sang {bus.Status}.", bus.BusId, bus.Status });
        }

        // UC18, FR06, BR27: Xem và cấu hình sơ đồ ghế của xe (chỉ áp dụng cho chuyến tạo mới, không làm sai lệch booking cũ)
        [HttpGet("buses/{id:int}/seats")]
        public async Task<IActionResult> GetBusSeats(int id)
        {
            var (_, userCompanyId, isAdmin) = GetOperatorContext();
            var bus = await _db.Buses.FindAsync(id);
            if (bus == null) return NotFound();
            if (!isAdmin && bus.CompanyId != userCompanyId)
            {
                return StatusCode(403, new { message = "Xe không thuộc nhà xe của bạn (AT02)." });
            }

            var seats = await _db.BusSeats
                .Where(bs => bs.BusId == id)
                .OrderBy(bs => bs.Deck)
                .ThenBy(bs => bs.Row)
                .ThenBy(bs => bs.Column)
                .ToListAsync();

            var maintenances = await _db.BusMaintenances
                .Where(m => m.BusId == id)
                .OrderByDescending(m => m.StartAt)
                .ToListAsync();

            return Ok(new { Bus = bus, Seats = seats, Maintenances = maintenances });
        }

        [HttpPut("buses/{busId:int}/seats/{busSeatId:int}")]
        public async Task<IActionResult> UpdateBusSeat(int busId, int busSeatId, [FromBody] UpdateBusSeatDto dto)
        {
            var (_, userCompanyId, isAdmin) = GetOperatorContext();
            var bus = await _db.Buses.FindAsync(busId);
            if (bus == null) return NotFound();
            if (!isAdmin && bus.CompanyId != userCompanyId)
            {
                return StatusCode(403, new { message = "Xe không thuộc nhà xe của bạn (AT02)." });
            }

            var seat = await _db.BusSeats.FirstOrDefaultAsync(bs => bs.BusSeatId == busSeatId && bs.BusId == busId);
            if (seat == null) return NotFound();

            // BR27: Cập nhật cấu hình BusSeat cho các chuyến tương lai, tuyệt đối không sửa BookingDetails đã phát sinh
            seat.SeatType = string.IsNullOrWhiteSpace(dto.SeatType) ? seat.SeatType : dto.SeatType;
            seat.PriceSurcharge = dto.PriceSurcharge;
            seat.IsActive = dto.IsActive;

            await _db.SaveChangesAsync();
            return Ok(new
            {
                message = $"Đã cập nhật ghế {seat.SeatCode} ({seat.SeatType}, phụ phí +{seat.PriceSurcharge:N0}đ). Áp dụng cho các chuyến tạo mới (BR27).",
                seat
            });
        }

        // Section 10.2: Xem và thêm giấy tờ pháp lý/chứng chỉ của tài xế (DriverDocuments)
        [HttpGet("drivers/{id:int}/documents")]
        public async Task<IActionResult> GetDriverDocuments(int id)
        {
            var (_, userCompanyId, isAdmin) = GetOperatorContext();
            var driver = await _db.Drivers.FindAsync(id);
            if (driver == null) return NotFound();
            if (!isAdmin && driver.CompanyId != userCompanyId)
            {
                return StatusCode(403, new { message = "Tài xế không thuộc nhà xe của bạn (AT02)." });
            }

            var docs = await _db.DriverDocuments
                .Where(d => d.DriverId == id)
                .OrderByDescending(d => d.DocumentId)
                .ToListAsync();

            return Ok(new { Driver = driver, Documents = docs });
        }

        [HttpPost("drivers/{id:int}/documents")]
        public async Task<IActionResult> AddDriverDocument(int id, [FromBody] AddDriverDocumentDto dto)
        {
            var (_, userCompanyId, isAdmin) = GetOperatorContext();
            var driver = await _db.Drivers.FindAsync(id);
            if (driver == null) return NotFound();
            if (!isAdmin && driver.CompanyId != userCompanyId)
            {
                return StatusCode(403, new { message = "Tài xế không thuộc nhà xe của bạn (AT02)." });
            }

            var doc = new DriverDocument
            {
                DriverId = id,
                Type = string.IsNullOrWhiteSpace(dto.Type) ? "Giấy khám sức khỏe định kỳ" : dto.Type.Trim(),
                FileUrl = string.IsNullOrWhiteSpace(dto.FileUrl) ? $"https://busticket.vn/docs/driver-{id}-{DateTime.UtcNow:yyyyMMdd}.pdf" : dto.FileUrl.Trim(),
                ExpiryDate = dto.ExpiryDate ?? DateTime.UtcNow.AddYears(1),
                Status = "Verified"
            };
            _db.DriverDocuments.Add(doc);
            await _db.SaveChangesAsync();

            return Ok(new { message = $"Đã thêm hồ sơ '{doc.Type}' cho tài xế {driver.FullName}.", doc });
        }

        // UC19, FR07: Thêm hồ sơ tài xế
        [HttpPost("drivers")]
        public async Task<IActionResult> CreateDriver([FromBody] CreateDriverDto dto)
        {
            var (_, userCompanyId, isAdmin) = GetOperatorContext();
            int companyId = isAdmin ? (dto.CompanyId ?? userCompanyId ?? 1) : (userCompanyId ?? 0);
            if (companyId <= 0) return StatusCode(403, new { message = "Không có quyền nhà xe." });

            if (string.IsNullOrWhiteSpace(dto.FullName) || string.IsNullOrWhiteSpace(dto.LicenseNumber))
            {
                return BadRequest(new { message = "Vui lòng nhập họ tên và số GPLX tài xế." });
            }

            var driver = new Driver
            {
                CompanyId = companyId,
                FullName = dto.FullName.Trim(),
                Phone = dto.Phone?.Trim() ?? "0900000000",
                LicenseNumber = dto.LicenseNumber.Trim(),
                LicenseClass = string.IsNullOrWhiteSpace(dto.LicenseClass) ? "E" : dto.LicenseClass.Trim().ToUpperInvariant(),
                LicenseExpiry = dto.LicenseExpiry ?? DateTime.UtcNow.AddYears(3),
                Status = "Active"
            };
            _db.Drivers.Add(driver);
            await _db.SaveChangesAsync();

            return Ok(new { message = $"Đã thêm tài xế {driver.FullName} (Hạng {driver.LicenseClass}).", driver.DriverId });
        }

        // UC20, FR08: Tạo tuyến đường kèm danh sách điểm đón/trả (RouteStops)
        [HttpPost("routes")]
        public async Task<IActionResult> CreateRoute([FromBody] CreateRouteDto dto)
        {
            var (_, userCompanyId, isAdmin) = GetOperatorContext();
            int companyId = isAdmin ? (dto.CompanyId ?? userCompanyId ?? 1) : (userCompanyId ?? 0);
            if (companyId <= 0) return StatusCode(403, new { message = "Không có quyền nhà xe." });

            var origin = await _db.Provinces.FindAsync(dto.OriginProvinceId);
            var dest = await _db.Provinces.FindAsync(dto.DestinationProvinceId);
            if (origin == null || dest == null)
            {
                return BadRequest(new { message = "Tỉnh/thành đi hoặc đến không hợp lệ." });
            }

            var routeName = string.IsNullOrWhiteSpace(dto.Name)
                ? $"{origin.Name} → {dest.Name}"
                : dto.Name.Trim();

            var route = new Models.Route
            {
                CompanyId = companyId,
                OriginProvinceId = origin.ProvinceId,
                DestinationProvinceId = dest.ProvinceId,
                Name = routeName,
                DistanceKm = dto.DistanceKm <= 0 ? 250 : dto.DistanceKm,
                EstimatedDurationMinutes = dto.EstimatedDurationMinutes <= 0 ? 300 : dto.EstimatedDurationMinutes,
                IsActive = true
            };
            _db.Routes.Add(route);
            await _db.SaveChangesAsync();

            var stops = new List<RouteStop>
            {
                new RouteStop
                {
                    RouteId = route.RouteId,
                    StopName = string.IsNullOrWhiteSpace(dto.DefaultPickupStopName) ? $"Bến xe trung tâm {origin.Name}" : dto.DefaultPickupStopName.Trim(),
                    Address = origin.Name,
                    Sequence = 1,
                    OffsetMinutes = 0,
                    Surcharge = 0,
                    Latitude = 10.80,
                    Longitude = 106.70,
                    StopType = StopTypes.Pickup
                },
                new RouteStop
                {
                    RouteId = route.RouteId,
                    StopName = string.IsNullOrWhiteSpace(dto.DefaultDropoffStopName) ? $"Bến xe trung tâm {dest.Name}" : dto.DefaultDropoffStopName.Trim(),
                    Address = dest.Name,
                    Sequence = 2,
                    OffsetMinutes = route.EstimatedDurationMinutes,
                    Surcharge = 0,
                    Latitude = 11.90,
                    Longitude = 108.40,
                    StopType = StopTypes.Dropoff
                }
            };
            _db.RouteStops.AddRange(stops);
            await _db.SaveChangesAsync();

            return Ok(new { message = $"Đã tạo tuyến '{route.Name}' kèm điểm đón/trả (UC20, FR08).", route.RouteId });
        }

        // UC20, FR08: Thêm điểm dừng đón/trả mới vào tuyến đường
        [HttpPost("routes/{id:int}/stops")]
        public async Task<IActionResult> AddRouteStop(int id, [FromBody] AddRouteStopDto dto)
        {
            var (_, userCompanyId, isAdmin) = GetOperatorContext();
            var route = await _db.Routes.Include(r => r.Stops).FirstOrDefaultAsync(r => r.RouteId == id);
            if (route == null) return NotFound();
            if (!isAdmin && route.CompanyId != userCompanyId)
            {
                return StatusCode(403, new { message = "Tuyến đường không thuộc nhà xe của bạn (AT02)." });
            }

            int nextSeq = route.Stops.Count > 0 ? route.Stops.Max(s => s.Sequence) + 1 : 1;
            var stop = new RouteStop
            {
                RouteId = id,
                StopName = dto.StopName.Trim(),
                Address = dto.Address?.Trim() ?? "",
                Sequence = nextSeq,
                OffsetMinutes = dto.OffsetMinutes,
                Surcharge = dto.Surcharge,
                Latitude = 11.20,
                Longitude = 107.50,
                StopType = string.IsNullOrWhiteSpace(dto.StopType) ? StopTypes.Both : dto.StopType
            };
            _db.RouteStops.Add(stop);
            await _db.SaveChangesAsync();

            return Ok(new { message = $"Đã thêm điểm dừng '{stop.StopName}' vào tuyến '{route.Name}'.", stop });
        }

        // UC16, FR07: Nhà xe tạo tài khoản nhân viên (Staff) và gán quyền theo phạm vi CompanyId
        [HttpPost("staff")]
        public async Task<IActionResult> CreateStaffMember([FromBody] CreateStaffDto dto)
        {
            var (userId, userCompanyId, isAdmin) = GetOperatorContext();
            int companyId = isAdmin ? (dto.CompanyId ?? userCompanyId ?? 1) : (userCompanyId ?? 0);
            if (companyId <= 0) return StatusCode(403, new { message = "Không có quyền nhà xe." });

            if (string.IsNullOrWhiteSpace(dto.Email) || string.IsNullOrWhiteSpace(dto.FullName))
            {
                return BadRequest(new { message = "Vui lòng nhập họ tên và email nhân viên." });
            }

            var email = dto.Email.Trim().ToLowerInvariant();
            if (await _db.Users.AnyAsync(u => u.Email == email))
            {
                return Conflict(new { message = "Email này đã tồn tại trên hệ thống (BR01)." });
            }

            var staffUser = new User
            {
                FullName = dto.FullName.Trim(),
                Email = email,
                Phone = dto.Phone?.Trim() ?? "0900000000",
                PasswordHash = Services.SecurityHelper.HashPassword(string.IsNullOrWhiteSpace(dto.Password) ? "123456" : dto.Password),
                IsActive = true
            };
            _db.Users.Add(staffUser);
            await _db.SaveChangesAsync();

            var staffRole = await _db.Roles.FirstAsync(r => r.RoleName == RoleNames.Staff);
            _db.UserRoles.Add(new UserRole
            {
                UserId = staffUser.UserId,
                RoleId = staffRole.RoleId,
                CompanyId = companyId
            });

            _db.CompanyMembers.Add(new CompanyMember
            {
                CompanyId = companyId,
                UserId = staffUser.UserId,
                MemberRole = RoleNames.Staff,
                Status = "Active"
            });

            _db.AuditLogs.Add(new AuditLog
            {
                UserId = userId,
                CompanyId = companyId,
                Action = "CreateStaffMember",
                EntityName = "CompanyMember",
                EntityId = staffUser.UserId.ToString(),
                Details = $"Tạo nhân viên {staffUser.FullName} ({staffUser.Email}) thuộc CompanyId #{companyId}"
            });

            await _db.SaveChangesAsync();
            return Ok(new { message = $"Đã tạo tài khoản nhân viên {staffUser.FullName} ({staffUser.Email}) cho nhà xe (UC16, FR07)!" });
        }

        // UC21, FR09, FR10, BR06, BR07, BR08, AT02, AT03: Nhà xe tạo chuyến xe mới có kiểm tra xung đột lịch & bằng lái
        [HttpPost("trips")]
        public async Task<IActionResult> CreateTrip([FromBody] CreateTripDto dto)
        {
            var (userId, userCompanyId, isAdmin) = GetOperatorContext();
            int companyId = isAdmin ? (dto.CompanyId ?? userCompanyId ?? 1) : (userCompanyId ?? 0);
            if (companyId <= 0) return StatusCode(403, new { message = "Không có quyền nhà xe (BR03)." });

            var company = await _db.BusCompanies.FindAsync(companyId);
            if (company == null || company.Status != CompanyStatuses.Active)
            {
                return BadRequest(new { message = "Nhà xe chưa được duyệt Active nên chưa thể mở bán chuyến (Mục 5.2)." });
            }

            var route = await _db.Routes.FirstOrDefaultAsync(r => r.RouteId == dto.RouteId && r.CompanyId == companyId);
            if (route == null)
            {
                return StatusCode(403, new { message = "Tuyến đường không tồn tại hoặc không thuộc nhà xe của bạn (AT02)." });
            }

            var bus = await _db.Buses
                .Include(b => b.Seats)
                .FirstOrDefaultAsync(b => b.BusId == dto.BusId && b.CompanyId == companyId);

            if (bus == null)
            {
                return StatusCode(403, new { message = "Xe không tồn tại hoặc không thuộc nhà xe của bạn (AT02)." });
            }
            if (bus.Status != BusStatuses.Active)
            {
                return BadRequest(new { message = "Xe đang bảo trì hoặc ngừng hoạt động, không thể gán chuyến (Mục 5.3)." });
            }

            var activeSeats = bus.Seats.Where(s => s.IsActive).ToList();
            if (activeSeats.Count == 0)
            {
                return BadRequest(new { message = "Xe chưa có sơ đồ ghế hợp lệ (BR06)." });
            }

            var departureAt = dto.DepartureAt;
            var arrivalAt = dto.ArrivalEstimate ?? departureAt.AddMinutes(route.EstimatedDurationMinutes);

            var bufferStart = departureAt.AddMinutes(-bus.TurnaroundMinutes);
            var bufferEnd = arrivalAt.AddMinutes(bus.TurnaroundMinutes);

            bool busConflict = await _db.Trips.AnyAsync(t =>
                t.BusId == bus.BusId &&
                t.Status != TripStatuses.Cancelled &&
                t.DepartureAt < bufferEnd &&
                t.ArrivalEstimate > bufferStart);

            if (busConflict)
            {
                return Conflict(new { message = $"Xe {bus.PlateNumber} bị trùng lịch chạy hoặc chưa đủ {bus.TurnaroundMinutes} phút đệm quay đầu (BR07, AT03)." });
            }

            Driver? driver = null;
            if (dto.DriverId.HasValue)
            {
                driver = await _db.Drivers.FirstOrDefaultAsync(d => d.DriverId == dto.DriverId.Value && d.CompanyId == companyId);
                if (driver == null)
                {
                    return StatusCode(403, new { message = "Tài xế không thuộc nhà xe của bạn (AT02)." });
                }
                if (driver.LicenseExpiry <= arrivalAt || (driver.LicenseClass != "E" && driver.LicenseClass != "D"))
                {
                    return BadRequest(new { message = $"Tài xế {driver.FullName} có GPLX hết hạn ({driver.LicenseExpiry:dd/MM/yyyy}) hoặc hạng không phù hợp (BR08, AT03)." });
                }

                bool driverConflict = await _db.DriverAssignments
                    .Include(da => da.Trip)
                    .AnyAsync(da =>
                        da.DriverId == driver.DriverId &&
                        da.ReleasedAt == null &&
                        da.Trip!.Status != TripStatuses.Cancelled &&
                        da.Trip.DepartureAt < bufferEnd &&
                        da.Trip.ArrivalEstimate > bufferStart);

                if (driverConflict)
                {
                    return Conflict(new { message = $"Tài xế {driver.FullName} bị trùng lịch phân công chuyến khác (AT03)." });
                }
            }

            var trip = new Trip
            {
                CompanyId = companyId,
                RouteId = route.RouteId,
                BusId = bus.BusId,
                DepartureAt = departureAt,
                ArrivalEstimate = arrivalAt,
                BasePrice = dto.BasePrice,
                Status = TripStatuses.Scheduled
            };
            _db.Trips.Add(trip);
            await _db.SaveChangesAsync();

            foreach (var bs in activeSeats)
            {
                _db.TripSeats.Add(new TripSeat
                {
                    TripId = trip.TripId,
                    BusSeatId = bs.BusSeatId,
                    SeatCode = bs.SeatCode,
                    Deck = bs.Deck,
                    Row = bs.Row,
                    Column = bs.Column,
                    SeatStatus = SeatStatuses.Available,
                    CurrentPrice = trip.BasePrice + bs.PriceSurcharge
                });
            }

            if (driver != null)
            {
                _db.DriverAssignments.Add(new DriverAssignment
                {
                    TripId = trip.TripId,
                    DriverId = driver.DriverId,
                    Role = "Primary"
                });
            }

            _db.TripStatusHistories.Add(new TripStatusHistory
            {
                TripId = trip.TripId,
                OldStatus = TripStatuses.Draft,
                NewStatus = TripStatuses.Scheduled,
                ChangedByUserId = userId,
                Reason = "Nhà xe tạo chuyến và mở bán"
            });

            _db.AuditLogs.Add(new AuditLog
            {
                UserId = userId,
                CompanyId = companyId,
                Action = "CreateTrip",
                EntityName = "Trip",
                EntityId = trip.TripId.ToString(),
                Details = $"Tạo chuyến {route.Name} - Xe {bus.PlateNumber} - Giá {trip.BasePrice:N0}đ"
            });

            await _db.SaveChangesAsync();

            return Ok(new
            {
                message = $"Tạo chuyến thành công và đã sinh {activeSeats.Count} ghế mở bán!",
                trip.TripId,
                trip.Status,
                TotalSeats = activeSeats.Count
            });
        }

        // UC22, Section 5.4, Section 13: Phân công / Thay tài xế cho chuyến (đóng phân công cũ, tạo mới, lưu lịch sử)
        [HttpPost("trips/{id:int}/reassign-driver")]
        public async Task<IActionResult> ReassignDriver(int id, [FromBody] ReassignDriverDto dto)
        {
            var (userId, userCompanyId, isAdmin) = GetOperatorContext();
            var trip = await _db.Trips.FindAsync(id);
            if (trip == null) return NotFound();
            if (!isAdmin && trip.CompanyId != userCompanyId)
            {
                return StatusCode(403, new { message = "Chuyến không thuộc nhà xe của bạn (AT02)." });
            }

            var newDriver = await _db.Drivers.FirstOrDefaultAsync(d => d.DriverId == dto.NewDriverId && d.CompanyId == trip.CompanyId);
            if (newDriver == null)
            {
                return BadRequest(new { message = "Tài xế mới không thuộc nhà xe này." });
            }
            if (newDriver.LicenseExpiry <= trip.ArrivalEstimate || (newDriver.LicenseClass != "E" && newDriver.LicenseClass != "D"))
            {
                return BadRequest(new { message = "Tài xế mới có GPLX hết hạn hoặc hạng không phù hợp (BR08)." });
            }

            var activeAssignments = await _db.DriverAssignments
                .Where(da => da.TripId == id && da.ReleasedAt == null)
                .ToListAsync();

            foreach (var old in activeAssignments)
            {
                old.ReleasedAt = DateTime.UtcNow;
                old.ReplaceReason = dto.Reason ?? "Điều động thay tài xế";
            }

            _db.DriverAssignments.Add(new DriverAssignment
            {
                TripId = id,
                DriverId = newDriver.DriverId,
                Role = "Primary",
                AssignedAt = DateTime.UtcNow
            });

            _db.AuditLogs.Add(new AuditLog
            {
                UserId = userId,
                CompanyId = trip.CompanyId,
                Action = "ReassignDriver",
                EntityName = "Trip",
                EntityId = id.ToString(),
                Details = $"Phân công tài xế {newDriver.FullName} cho chuyến #{id}. Lý do: {dto.Reason}"
            });

            await _db.SaveChangesAsync();
            return Ok(new { message = $"Đã phân công tài xế {newDriver.FullName} cho chuyến #{id} và lưu lịch sử thay đổi (UC22)." });
        }

        // Section 6.5, AT11: Hủy chuyến
        [HttpPost("trips/{id:int}/cancel")]
        public async Task<IActionResult> CancelTrip(int id, [FromBody] CancelBookingDto dto)
        {
            var (userId, userCompanyId, isAdmin) = GetOperatorContext();
            var trip = await _db.Trips
                .Include(t => t.Route)
                .Include(t => t.TripSeats)
                .FirstOrDefaultAsync(t => t.TripId == id);

            if (trip == null) return NotFound();
            if (!isAdmin && trip.CompanyId != userCompanyId)
            {
                return StatusCode(403, new { message = "Bạn không có quyền hủy chuyến của nhà xe khác (AT02)." });
            }

            string oldStatus = trip.Status;
            trip.Status = TripStatuses.Cancelled;

            _db.TripStatusHistories.Add(new TripStatusHistory
            {
                TripId = trip.TripId,
                OldStatus = oldStatus,
                NewStatus = TripStatuses.Cancelled,
                ChangedByUserId = userId,
                Reason = dto.Reason ?? "Nhà xe hủy chuyến"
            });

            var affectedBookings = await _db.Bookings
                .Include(b => b.Details).ThenInclude(d => d.Ticket)
                .Include(b => b.Payments)
                .Where(b => b.TripId == id && b.Status != BookingStatuses.Cancelled)
                .ToListAsync();

            int refundCreatedCount = 0;
            foreach (var b in affectedBookings)
            {
                b.Status = BookingStatuses.Cancelled;
                b.CancelReason = $"Nhà xe hủy chuyến: {dto.Reason ?? "Sự cố vận hành"}";

                foreach (var d in b.Details)
                {
                    d.IsActiveBooking = false;
                    if (d.Ticket != null) d.Ticket.Status = TicketStatuses.Cancelled;
                }

                var paidPayment = b.Payments.FirstOrDefault(p => p.Status == PaymentStatuses.Paid);
                if (paidPayment != null)
                {
                    paidPayment.Status = PaymentStatuses.RefundPending;
                    _db.Refunds.Add(new Refund
                    {
                        PaymentId = paidPayment.PaymentId,
                        BookingId = b.BookingId,
                        Amount = paidPayment.Amount,
                        Reason = b.CancelReason,
                        Status = "Pending"
                    });
                    refundCreatedCount++;
                }
                else
                {
                    foreach (var p in b.Payments) p.Status = PaymentStatuses.Cancelled;
                }

                _db.Notifications.Add(new Notification
                {
                    UserId = b.UserId,
                    Title = $"Thông báo hủy chuyến ({trip.Route?.Name})",
                    Content = $"Chuyến xe khởi hành {trip.DepartureAt:dd/MM HH:mm} đã bị hủy. Lý do: {dto.Reason}. Đơn {b.BookingCode} đã được xử lý hoàn tiền 100%.",
                    Type = "TripCancelled",
                    ReferenceId = b.BookingId
                });
            }

            foreach (var ts in trip.TripSeats)
            {
                ts.SeatStatus = SeatStatuses.Unavailable;
            }

            _db.AuditLogs.Add(new AuditLog
            {
                UserId = userId,
                CompanyId = trip.CompanyId,
                Action = "CancelTrip",
                EntityName = "Trip",
                EntityId = trip.TripId.ToString(),
                Details = $"Hủy chuyến #{trip.TripId}. Booking ảnh hưởng: {affectedBookings.Count}, Yêu cầu hoàn tiền: {refundCreatedCount}."
            });

            await _db.SaveChangesAsync();

            return Ok(new
            {
                message = $"Đã hủy chuyến, gửi thông báo cho {affectedBookings.Count} đơn và tạo {refundCreatedCount} yêu cầu hoàn tiền (AT11).",
                AffectedBookings = affectedBookings.Count,
                RefundRequestsCreated = refundCreatedCount
            });
        }

        // AT08, BR17, Section 6.2: Xác nhận đã thu tiền COD
        [HttpPost("bookings/{id:int}/collect-cod")]
        public async Task<IActionResult> CollectCodPayment(int id)
        {
            var (userId, userCompanyId, isAdmin) = GetOperatorContext();
            var booking = await _db.Bookings
                .Include(b => b.Trip)
                .Include(b => b.Payments)
                .FirstOrDefaultAsync(b => b.BookingId == id);

            if (booking == null) return NotFound();
            if (!isAdmin && booking.Trip!.CompanyId != userCompanyId)
            {
                return StatusCode(403, new { message = "Đơn đặt vé không thuộc nhà xe của bạn (AT02)." });
            }

            var payment = booking.Payments.FirstOrDefault(p => p.Method == PaymentMethods.COD);
            if (payment == null)
            {
                return BadRequest(new { message = "Đơn đặt vé này không phải đơn COD." });
            }

            if (payment.Status == PaymentStatuses.Paid)
            {
                return Ok(new { message = "Đơn COD này đã được ghi nhận thu tiền trước đó." });
            }

            payment.Status = PaymentStatuses.Paid;
            payment.CollectedByUserId = userId;
            payment.PaidAt = DateTime.UtcNow;

            _db.PaymentTransactions.Add(new PaymentTransaction
            {
                PaymentId = payment.PaymentId,
                ProviderRef = $"COD-USER-{userId}-{DateTime.UtcNow:yyyyMMddHHmmss}",
                TxnRef = booking.BookingCode,
                ResponseCode = "00",
                RawStatus = "COD_Collected",
                SignatureValid = true
            });

            _db.AuditLogs.Add(new AuditLog
            {
                UserId = userId,
                CompanyId = booking.Trip!.CompanyId,
                Action = "CollectCOD",
                EntityName = "Booking",
                EntityId = booking.BookingCode,
                Details = $"Xác nhận thu tiền COD {payment.Amount:N0}đ cho đơn {booking.BookingCode}"
            });

            await _db.SaveChangesAsync();

            return Ok(new
            {
                message = $"Đã xác nhận thu {payment.Amount:N0} đ tiền mặt (COD) cho đơn {booking.BookingCode} (AT08).",
                booking.BookingId,
                PaymentStatus = payment.Status
            });
        }

        // Section 6.2, Section 13: Ghi nhận khách không đến (No-show)
        [HttpPost("bookings/{id:int}/mark-noshow")]
        public async Task<IActionResult> MarkNoShow(int id)
        {
            var (_, userCompanyId, isAdmin) = GetOperatorContext();
            var booking = await _db.Bookings
                .Include(b => b.Trip)
                .Include(b => b.User)
                .Include(b => b.Details).ThenInclude(d => d.Ticket)
                .Include(b => b.Payments)
                .FirstOrDefaultAsync(b => b.BookingId == id);

            if (booking == null) return NotFound();
            if (!isAdmin && booking.Trip!.CompanyId != userCompanyId)
            {
                return StatusCode(403, new { message = "Không thuộc phạm vi nhà xe." });
            }

            booking.Status = BookingStatuses.NoShow;
            if (booking.User != null)
            {
                booking.User.NoShowCount += 1;
            }

            foreach (var d in booking.Details)
            {
                d.IsActiveBooking = false;
                if (d.Ticket != null) d.Ticket.Status = TicketStatuses.Expired;
            }

            await _db.SaveChangesAsync();
            return Ok(new { message = $"Đã ghi nhận khách vắng mặt (No-Show) cho đơn {booking.BookingCode}.", UserNoShowCount = booking.User?.NoShowCount });
        }

        // UC31: Phản hồi yêu cầu hỗ trợ của khách hàng
        [HttpPost("support-requests/{id:int}/reply")]
        public async Task<IActionResult> ReplySupportRequest(int id, [FromBody] ReplySupportDto dto)
        {
            var (userId, _, _) = GetOperatorContext();
            var req = await _db.SupportRequests.FindAsync(id);
            if (req == null) return NotFound();

            req.ReplyContent = dto.ReplyContent?.Trim();
            req.Status = "Resolved";
            req.HandledByUserId = userId;
            req.UpdatedAt = DateTime.UtcNow;

            _db.Notifications.Add(new Notification
            {
                UserId = req.UserId,
                Title = $"Phản hồi hỗ trợ: {req.Subject}",
                Content = req.ReplyContent ?? "Yêu cầu của bạn đã được xử lý.",
                Type = "SupportReply",
                ReferenceId = req.RequestId
            });

            await _db.SaveChangesAsync();
            return Ok(new { message = "Đã gửi phản hồi hỗ trợ cho khách hàng (UC31).", req });
        }

        // Section 10.3: Xem lịch sử bảo trì của từng xe (BusMaintenances)
        [HttpGet("buses/{busId:int}/maintenances")]
        public async Task<IActionResult> GetBusMaintenances(int busId)
        {
            var (_, userCompanyId, isAdmin) = GetOperatorContext();
            var bus = await _db.Buses.FirstOrDefaultAsync(b => b.BusId == busId);
            if (bus == null) return NotFound();
            if (!isAdmin && bus.CompanyId != userCompanyId)
            {
                return StatusCode(403, new { message = "Xe không thuộc nhà xe của bạn (AT02)." });
            }

            var list = await _db.BusMaintenances
                .Where(m => m.BusId == busId)
                .OrderByDescending(m => m.StartAt)
                .ToListAsync();
            return Ok(list);
        }

        // UC22, BR28, Section 10.4 & 10.6: Xem nhật ký vận hành chuyến (Lịch sử phân công tài xế, trạng thái chuyến, sự cố dọc đường)
        [HttpGet("trips/{tripId:int}/operational-logs")]
        public async Task<IActionResult> GetTripOperationalLogs(int tripId)
        {
            var (_, userCompanyId, isAdmin) = GetOperatorContext();
            var trip = await _db.Trips.FirstOrDefaultAsync(t => t.TripId == tripId);
            if (trip == null) return NotFound();
            if (!isAdmin && trip.CompanyId != userCompanyId)
            {
                return StatusCode(403, new { message = "Chuyến không thuộc nhà xe của bạn (AT02)." });
            }

            var assignments = await _db.DriverAssignments
                .Include(da => da.Driver)
                .Where(da => da.TripId == tripId)
                .OrderByDescending(da => da.AssignedAt)
                .Select(da => new
                {
                    da.AssignmentId,
                    da.DriverId,
                    DriverName = da.Driver != null ? da.Driver.FullName : "Tài xế",
                    DriverPhone = da.Driver != null ? da.Driver.Phone : "",
                    da.Role,
                    da.AssignedAt,
                    da.ReleasedAt,
                    da.ReplaceReason
                })
                .ToListAsync();

            var statusHistory = await _db.TripStatusHistories
                .Where(h => h.TripId == tripId)
                .OrderByDescending(h => h.ChangedAt)
                .ToListAsync();

            var incidents = await _db.TripIncidents
                .Include(i => i.Driver)
                .Where(i => i.TripId == tripId)
                .OrderByDescending(i => i.CreatedAt)
                .Select(i => new
                {
                    i.IncidentId,
                    i.Type,
                    i.Description,
                    DriverName = i.Driver != null ? i.Driver.FullName : "Tài xế",
                    i.CreatedAt
                })
                .ToListAsync();

            return Ok(new
            {
                TripId = tripId,
                DriverAssignments = assignments,
                StatusHistories = statusHistory,
                Incidents = incidents
            });
        }

        // UC13, UC26: Xem danh sách đánh giá của hành khách dành cho nhà xe
        [HttpGet("reviews")]
        public async Task<IActionResult> GetCompanyReviews([FromQuery] int? companyId)
        {
            var (_, userCompanyId, isAdmin) = GetOperatorContext();
            int? targetCompanyId = isAdmin ? (companyId ?? userCompanyId) : userCompanyId;
            if (!targetCompanyId.HasValue) return BadRequest(new { message = "Không xác định được nhà xe." });

            var reviews = await _db.Reviews
                .Include(r => r.User)
                .Include(r => r.Booking)
                .Where(r => r.CompanyId == targetCompanyId.Value)
                .OrderByDescending(r => r.CreatedAt)
                .Select(r => new
                {
                    r.ReviewId,
                    r.Rating,
                    r.Comment,
                    r.CreatedAt,
                    r.TripId,
                    BookingCode = r.Booking != null ? r.Booking.BookingCode : "",
                    CustomerName = r.User != null ? r.User.FullName : "Hành khách"
                })
                .ToListAsync();

            return Ok(reviews);
        }

        // UC26, FR23, BR26: Báo cáo doanh thu, COD và tỷ lệ lấp đầy ghế dành riêng cho Nhà xe
        [HttpGet("reports/summary")]
        public async Task<IActionResult> GetOperatorReportSummary([FromQuery] int? companyId)
        {
            var (_, userCompanyId, isAdmin) = GetOperatorContext();
            int? targetCompanyId = isAdmin ? (companyId ?? userCompanyId) : userCompanyId;
            if (!targetCompanyId.HasValue) return BadRequest(new { message = "Không xác định được nhà xe." });

            var trips = await _db.Trips
                .Include(t => t.Route)
                .Include(t => t.TripSeats)
                .Where(t => t.CompanyId == targetCompanyId.Value)
                .ToListAsync();

            var payments = await _db.Payments
                .Include(p => p.Booking)!.ThenInclude(b => b!.Trip)
                .Where(p => p.Booking!.Trip!.CompanyId == targetCompanyId.Value)
                .ToListAsync();

            var refunds = await _db.Refunds
                .Include(r => r.Payment)!.ThenInclude(p => p!.Booking)!.ThenInclude(b => b!.Trip)
                .Where(r => r.Payment!.Booking!.Trip!.CompanyId == targetCompanyId.Value)
                .ToListAsync();

            decimal collectedRevenue = payments.Where(p => p.Status == PaymentStatuses.Paid).Sum(p => p.Amount);
            decimal uncollectedCod = payments.Where(p => p.Method == PaymentMethods.COD && p.Status == PaymentStatuses.Unpaid).Sum(p => p.Amount);
            decimal totalRefunded = refunds.Where(r => r.Status == "Completed").Sum(r => r.Amount);
            decimal pendingRefund = refunds.Where(r => r.Status == "Pending").Sum(r => r.Amount);

            int totalSeatsOffered = trips.Where(t => t.Status != TripStatuses.Cancelled).Sum(t => t.TripSeats.Count);
            int totalSeatsBooked = trips.Where(t => t.Status != TripStatuses.Cancelled).Sum(t => t.TripSeats.Count(ts => ts.SeatStatus == SeatStatuses.Booked));
            double occupancyRate = totalSeatsOffered > 0 ? Math.Round(totalSeatsBooked * 100.0 / totalSeatsOffered, 1) : 0;

            return Ok(new
            {
                CompanyId = targetCompanyId.Value,
                TotalTrips = trips.Count,
                ActiveTrips = trips.Count(t => t.Status != TripStatuses.Cancelled),
                TotalSeatsOffered = totalSeatsOffered,
                TotalSeatsBooked = totalSeatsBooked,
                OccupancyRatePercent = occupancyRate,
                CollectedRevenue = collectedRevenue,
                UncollectedCodAmount = uncollectedCod,
                CompletedRefundAmount = totalRefunded,
                PendingRefundAmount = pendingRefund,
                NetRevenue = collectedRevenue - totalRefunded
            });
        }

        // Mở rộng nâng cao: Tạo lịch chạy tự động hàng loạt nhiều ngày liên tiếp (Recurring Trip Generator)
        [HttpPost("trips/bulk-generate")]
        public async Task<IActionResult> BulkGenerateTrips([FromBody] BulkCreateTripsDto dto)
        {
            var (userId, userCompanyId, isAdmin) = GetOperatorContext();
            int companyId = isAdmin ? (dto.CompanyId ?? userCompanyId ?? 1) : (userCompanyId ?? 0);

            var route = await _db.Routes.FirstOrDefaultAsync(r => r.RouteId == dto.RouteId && r.CompanyId == companyId);
            var bus = await _db.Buses.Include(b => b.Seats).FirstOrDefaultAsync(b => b.BusId == dto.BusId && b.CompanyId == companyId);
            if (route == null || bus == null) return BadRequest(new { message = "Tuyến hoặc xe không hợp lệ." });

            var activeSeats = bus.Seats.Where(s => s.IsActive).ToList();
            int days = Math.Clamp(dto.DaysCount, 1, 14);
            int createdCount = 0;

            for (int d = 0; d < days; d++)
            {
                var dep = dto.StartDepartureAt.AddDays(d);
                var arr = dep.AddMinutes(route.EstimatedDurationMinutes);
                var bufStart = dep.AddMinutes(-bus.TurnaroundMinutes);
                var bufEnd = arr.AddMinutes(bus.TurnaroundMinutes);

                bool conflict = await _db.Trips.AnyAsync(t =>
                    t.BusId == bus.BusId &&
                    t.Status != TripStatuses.Cancelled &&
                    t.DepartureAt < bufEnd &&
                    t.ArrivalEstimate > bufStart);

                if (conflict) continue;

                var trip = new Trip
                {
                    CompanyId = companyId,
                    RouteId = route.RouteId,
                    BusId = bus.BusId,
                    DepartureAt = dep,
                    ArrivalEstimate = arr,
                    BasePrice = dto.BasePrice,
                    Status = TripStatuses.Scheduled
                };
                _db.Trips.Add(trip);
                await _db.SaveChangesAsync();

                foreach (var bs in activeSeats)
                {
                    _db.TripSeats.Add(new TripSeat
                    {
                        TripId = trip.TripId,
                        BusSeatId = bs.BusSeatId,
                        SeatCode = bs.SeatCode,
                        Deck = bs.Deck,
                        Row = bs.Row,
                        Column = bs.Column,
                        SeatStatus = SeatStatuses.Available,
                        CurrentPrice = trip.BasePrice + bs.PriceSurcharge
                    });
                }

                if (dto.DriverId.HasValue)
                {
                    _db.DriverAssignments.Add(new DriverAssignment
                    {
                        TripId = trip.TripId,
                        DriverId = dto.DriverId.Value,
                        Role = "Primary"
                    });
                }

                await _db.SaveChangesAsync();
                createdCount++;
            }

            return Ok(new
            {
                message = $"Đã tạo tự động {createdCount}/{days} chuyến xe liên tiếp cho tuyến {route.Name} (tự động bỏ qua các ca bị trùng lịch xe)!",
                CreatedCount = createdCount
            });
        }

        // Mở rộng nâng cao: Đặt vé trực tiếp tại quầy / qua điện thoại cho Nhân viên Nhà xe (Counter POS Booking)
        [HttpPost("pos-booking")]
        public async Task<IActionResult> CreateCounterPosBooking([FromBody] CounterPosBookingDto dto)
        {
            var (userId, userCompanyId, isAdmin) = GetOperatorContext();
            var trip = await _db.Trips
                .Include(t => t.Route)
                .FirstOrDefaultAsync(t => t.TripId == dto.TripId);

            if (trip == null) return NotFound();
            if (!isAdmin && trip.CompanyId != userCompanyId)
            {
                return StatusCode(403, new { message = "Chuyến không thuộc nhà xe của bạn (AT02)." });
            }

            TripSeat? seat = null;
            if (dto.TripSeatId.HasValue)
            {
                seat = await _db.TripSeats.FirstOrDefaultAsync(ts => ts.TripSeatId == dto.TripSeatId.Value && ts.TripId == dto.TripId);
            }
            else
            {
                seat = await _db.TripSeats
                    .Where(ts => ts.TripId == dto.TripId && ts.SeatStatus == SeatStatuses.Available)
                    .OrderBy(ts => ts.SeatCode)
                    .FirstOrDefaultAsync();
            }

            if (seat == null || seat.SeatStatus != SeatStatuses.Available)
            {
                return Conflict(new { message = "Ghế đã chọn không còn trống hoặc chuyến xe đã hết ghế." });
            }

            var now = DateTime.UtcNow;
            var bookingCode = $"POS-{now:yyyyMMdd}-{Random.Shared.Next(1000, 9999)}";
            var booking = new Booking
            {
                UserId = userId,
                TripId = trip.TripId,
                BookingCode = bookingCode,
                ContactName = string.IsNullOrWhiteSpace(dto.PassengerName) ? "Khách mua tại quầy" : dto.PassengerName.Trim(),
                ContactPhone = string.IsNullOrWhiteSpace(dto.PassengerPhone) ? "0900000000" : dto.PassengerPhone.Trim(),
                SubTotal = seat.CurrentPrice,
                SurchargeTotal = 0,
                DiscountAmount = 0,
                TotalAmount = seat.CurrentPrice,
                Status = BookingStatuses.Confirmed,
                CreatedAt = now,
                ExpiresAt = now.AddHours(2)
            };
            _db.Bookings.Add(booking);
            await _db.SaveChangesAsync();

            seat.SeatStatus = SeatStatuses.Booked;
            var detail = new BookingDetail
            {
                BookingId = booking.BookingId,
                TripSeatId = seat.TripSeatId,
                SeatCode = seat.SeatCode,
                PassengerName = booking.ContactName,
                PassengerPhone = booking.ContactPhone,
                UnitPrice = seat.CurrentPrice,
                Surcharge = 0,
                IsActiveBooking = true
            };
            _db.BookingDetails.Add(detail);
            await _db.SaveChangesAsync();

            var payment = new Payment
            {
                BookingId = booking.BookingId,
                Method = PaymentMethods.COD,
                Amount = seat.CurrentPrice,
                Status = PaymentStatuses.Paid,
                CollectedByUserId = userId,
                PaidAt = now,
                CreatedAt = now
            };
            _db.Payments.Add(payment);
            await _db.SaveChangesAsync();

            var ticketCode = $"TKT-{trip.TripId}-{seat.SeatCode}-{booking.BookingId}";
            var qrPayload = $"BTB|{ticketCode}|{trip.TripId}|{seat.SeatCode}|POS";
            _db.Tickets.Add(new Ticket
            {
                BookingDetailId = detail.BookingDetailId,
                TripId = trip.TripId,
                TicketCode = ticketCode,
                QRDisplayPayload = qrPayload,
                QRTokenHash = Guid.NewGuid().ToString("N"),
                Status = TicketStatuses.Active
            });

            await _db.SaveChangesAsync();

            return Ok(new
            {
                message = $"Đã xuất vé tại quầy (POS) thành công! Mã đơn: {bookingCode} • Ghế {seat.SeatCode} ({seat.CurrentPrice:N0} đ - Đã thu tiền mặt).",
                booking.BookingCode,
                seat.SeatCode,
                TicketCode = ticketCode
            });
        }

        // Mở rộng nâng cao: Quản lý Hàng hóa ký gửi theo chuyến xe (CargoShipments)
        [HttpGet("parcels")]
        public async Task<IActionResult> GetCargoShipments([FromQuery] int? tripId)
        {
            var (_, userCompanyId, isAdmin) = GetOperatorContext();
            var query = _db.CargoShipments.AsQueryable();
            if (!isAdmin && userCompanyId.HasValue)
            {
                query = query.Where(c => c.CompanyId == userCompanyId.Value);
            }
            if (tripId.HasValue)
            {
                query = query.Where(c => c.TripId == tripId.Value);
            }

            var list = await query.OrderByDescending(c => c.CreatedAt).ToListAsync();
            return Ok(list);
        }

        [HttpPost("parcels")]
        public async Task<IActionResult> CreateCargoShipment([FromBody] CreateCargoShipmentDto dto)
        {
            var (userId, userCompanyId, isAdmin) = GetOperatorContext();
            var trip = await _db.Trips.FirstOrDefaultAsync(t => t.TripId == dto.TripId);
            if (trip == null) return NotFound(new { message = "Không tìm thấy chuyến xe." });
            if (!isAdmin && trip.CompanyId != userCompanyId)
            {
                return StatusCode(403, new { message = "Chuyến không thuộc nhà xe của bạn." });
            }

            var item = new CargoShipment
            {
                TripId = trip.TripId,
                CompanyId = trip.CompanyId,
                TrackingCode = $"PKG-{DateTime.UtcNow:yyyyMMdd}-{Random.Shared.Next(100, 999)}",
                SenderName = dto.SenderName.Trim(),
                SenderPhone = dto.SenderPhone.Trim(),
                ReceiverName = dto.ReceiverName.Trim(),
                ReceiverPhone = dto.ReceiverPhone.Trim(),
                Description = dto.Description.Trim(),
                WeightKg = dto.WeightKg > 0 ? dto.WeightKg : 1.0,
                FeeAmount = dto.FeeAmount > 0 ? dto.FeeAmount : 50000,
                Status = "Received"
            };
            _db.CargoShipments.Add(item);
            _db.AuditLogs.Add(new AuditLog
            {
                UserId = userId,
                CompanyId = trip.CompanyId,
                Action = "CreateCargoShipment",
                EntityName = "CargoShipment",
                EntityId = item.TrackingCode,
                Details = $"Nhận ký gửi hàng hóa {item.TrackingCode} trên chuyến #{trip.TripId} ({item.FeeAmount:N0}đ)"
            });

            await _db.SaveChangesAsync();
            return Ok(new { message = $"Đã tạo phiếu gửi hàng {item.TrackingCode} ({item.FeeAmount:N0} đ)!", item });
        }

        [HttpPost("parcels/{id:int}/status")]
        public async Task<IActionResult> UpdateCargoShipmentStatus(int id, [FromBody] UpdateCargoStatusDto dto)
        {
            var item = await _db.CargoShipments.FindAsync(id);
            if (item == null) return NotFound();
            item.Status = dto.Status;
            await _db.SaveChangesAsync();
            return Ok(new { message = $"Đã cập nhật trạng thái kiện hàng {item.TrackingCode} sang {item.Status}.", item });
        }

        // Đợt 2 - Tính năng #5: Sổ chi phí chuyến đi & Quyết toán lợi nhuận ròng theo chuyến (TripExpenses)
        [HttpGet("trips/{tripId:int}/expenses")]
        public async Task<IActionResult> GetTripExpensesAndProfit(int tripId)
        {
            var trip = await _db.Trips.Include(t => t.Route).FirstOrDefaultAsync(t => t.TripId == tripId);
            if (trip == null) return NotFound();

            var expenses = await _db.TripExpenses
                .Where(e => e.TripId == tripId)
                .OrderByDescending(e => e.CreatedAt)
                .ToListAsync();

            var ticketRev = await _db.Bookings
                .Where(b => b.TripId == tripId && (b.Status == BookingStatuses.Confirmed || b.Status == BookingStatuses.Completed))
                .SumAsync(b => (decimal?)b.TotalAmount) ?? 0m;

            var cargoRev = await _db.CargoShipments
                .Where(c => c.TripId == tripId)
                .SumAsync(c => (decimal?)c.FeeAmount) ?? 0m;

            var totalExp = expenses.Sum(e => e.Amount);
            var netProfit = ticketRev + cargoRev - totalExp;

            return Ok(new
            {
                TripId = tripId,
                RouteName = trip.Route?.Name,
                TicketRevenue = ticketRev,
                CargoRevenue = cargoRev,
                TotalExpense = totalExp,
                NetTripProfit = netProfit,
                Expenses = expenses
            });
        }

        [HttpPost("trips/{tripId:int}/expenses")]
        public async Task<IActionResult> AddTripExpense(int tripId, [FromBody] CreateTripExpenseDto dto)
        {
            var (userId, _, _) = GetOperatorContext();
            var trip = await _db.Trips.FirstOrDefaultAsync(t => t.TripId == tripId);
            if (trip == null) return NotFound();

            var exp = new TripExpense
            {
                TripId = tripId,
                CompanyId = trip.CompanyId,
                Category = string.IsNullOrWhiteSpace(dto.Category) ? "Fuel" : dto.Category.Trim(),
                Amount = dto.Amount,
                Note = string.IsNullOrWhiteSpace(dto.Note) ? "Chi phí vận hành chuyến" : dto.Note.Trim(),
                RecordedByUserId = userId,
                CreatedAt = DateTime.UtcNow
            };
            _db.TripExpenses.Add(exp);
            await _db.SaveChangesAsync();

            return Ok(new { message = $"Đã ghi nhận khoản chi '{exp.Category}' ({exp.Amount:N0} đ) cho chuyến #{tripId}!", expense = exp });
        }

        // Đợt 2 - Tính năng #6: Danh sách đón khách xe trung chuyển & Điều phối xe trung chuyển (Shuttle Pickup Manifest)
        [HttpGet("shuttles")]
        public async Task<IActionResult> GetShuttleManifest([FromQuery] int? tripId)
        {
            var (_, userCompanyId, isAdmin) = GetOperatorContext();
            var query = _db.ShuttleRequests.AsQueryable();
            if (!isAdmin && userCompanyId.HasValue)
            {
                query = query.Where(s => s.CompanyId == userCompanyId.Value);
            }
            if (tripId.HasValue)
            {
                query = query.Where(s => s.TripId == tripId.Value);
            }

            var list = await query.OrderByDescending(s => s.CreatedAt).ToListAsync();
            return Ok(list);
        }

        [HttpPost("shuttles/{id:int}/assign")]
        public async Task<IActionResult> AssignShuttleStatus(int id, [FromBody] AssignShuttleDto dto)
        {
            var shuttle = await _db.ShuttleRequests.FindAsync(id);
            if (shuttle == null) return NotFound();
            if (!string.IsNullOrWhiteSpace(dto.ShuttlePlate))
            {
                shuttle.ShuttlePlate = dto.ShuttlePlate.Trim();
            }
            if (!string.IsNullOrWhiteSpace(dto.Status))
            {
                shuttle.Status = dto.Status.Trim();
            }
            await _db.SaveChangesAsync();
            return Ok(new { message = $"Đã cập nhật điều phối xe trung chuyển ({shuttle.ShuttlePlate} - {shuttle.Status})!", shuttle });
        }
    }

    public record CreateBusDto(int? CompanyId, string PlateNumber, string BusType, string BrandModel, int TotalSeats, int ManufactureYear);
    public record UpdateBusStatusDto(string Status, string? Description);
    public record CreateDriverDto(int? CompanyId, string FullName, string Phone, string LicenseNumber, string LicenseClass, DateTime? LicenseExpiry);
    public record CreateRouteDto(int? CompanyId, int OriginProvinceId, int DestinationProvinceId, string? Name, int DistanceKm, int EstimatedDurationMinutes, string? DefaultPickupStopName, string? DefaultDropoffStopName);
    public record CreateTripDto(int? CompanyId, int RouteId, int BusId, int? DriverId, DateTime DepartureAt, DateTime? ArrivalEstimate, decimal BasePrice);
    public record ReassignDriverDto(int NewDriverId, string? Reason);
    public record ReplySupportDto(string ReplyContent);
    public record AddRouteStopDto(string StopName, string? Address, string StopType, int OffsetMinutes, decimal Surcharge);
    public record CreateStaffDto(int? CompanyId, string FullName, string Email, string? Phone, string? Password);
    public record UpdateBusSeatDto(string SeatType, decimal PriceSurcharge, bool IsActive);
    public record AddDriverDocumentDto(string Type, string? FileUrl, DateTime? ExpiryDate);
    public record BulkCreateTripsDto(int? CompanyId, int RouteId, int BusId, int? DriverId, DateTime StartDepartureAt, int DaysCount, decimal BasePrice);
    public record CounterPosBookingDto(int TripId, int? TripSeatId, string PassengerName, string PassengerPhone);
    public record CreateCargoShipmentDto(int TripId, string SenderName, string SenderPhone, string ReceiverName, string ReceiverPhone, string Description, double WeightKg, decimal FeeAmount);
    public record UpdateCargoStatusDto(string Status);
    public record CreateTripExpenseDto(string Category, decimal Amount, string? Note);
    public record AssignShuttleDto(string? ShuttlePlate, string? Status);
}
