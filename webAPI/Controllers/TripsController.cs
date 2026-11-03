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
    public class TripsController : ControllerBase
    {
        private readonly BusBookingDbContext _db;
        private readonly CallSignalingService _callSignaling;

        public TripsController(BusBookingDbContext db, CallSignalingService callSignaling)
        {
            _db = db;
            _callSignaling = callSignaling;
        }

        [HttpGet("provinces")]
        public async Task<IActionResult> GetProvinces()
        {
            var provinces = await _db.Provinces.OrderBy(p => p.ProvinceId).ToListAsync();
            return Ok(provinces);
        }

        [HttpGet("trips/search")]
        public async Task<IActionResult> SearchTrips(
            [FromQuery] int? originProvinceId,
            [FromQuery] int? destinationProvinceId,
            [FromQuery] DateTime? date,
            [FromQuery] int passengers = 1,
            [FromQuery] string? busType = null,
            [FromQuery] int? companyId = null)
        {
            // Release expired holds first so available seat count is 100% accurate (AT05)
            await SeatHoldCleanupService.ReleaseExpiredHoldsInDbAsync(_db);

            var query = _db.Trips
                .Include(t => t.Company)
                .Include(t => t.Route)!.ThenInclude(r => r!.OriginProvince)
                .Include(t => t.Route)!.ThenInclude(r => r!.DestinationProvince)
                .Include(t => t.Route)!.ThenInclude(r => r!.Stops)
                .Include(t => t.Bus)
                .Include(t => t.TripSeats)
                .Where(t => t.Company!.Status == CompanyStatuses.Active &&
                            t.Bus!.Status == BusStatuses.Active &&
                            (t.Status == TripStatuses.Scheduled || t.Status == TripStatuses.Boarding || t.Status == TripStatuses.Delayed));

            if (originProvinceId.HasValue && originProvinceId.Value > 0)
            {
                query = query.Where(t => t.Route!.OriginProvinceId == originProvinceId.Value);
            }
            if (destinationProvinceId.HasValue && destinationProvinceId.Value > 0)
            {
                query = query.Where(t => t.Route!.DestinationProvinceId == destinationProvinceId.Value);
            }
            if (date.HasValue)
            {
                var start = date.Value.Date;
                var end = start.AddDays(1);
                query = query.Where(t => t.DepartureAt >= start && t.DepartureAt < end);
            }
            if (!string.IsNullOrWhiteSpace(busType))
            {
                query = query.Where(t => t.Bus!.BusType.Contains(busType));
            }
            if (companyId.HasValue && companyId.Value > 0)
            {
                query = query.Where(t => t.CompanyId == companyId.Value);
            }

            var trips = await query.OrderBy(t => t.DepartureAt).ToListAsync();

            var result = trips
                .Select(t => new
                {
                    t.TripId,
                    t.CompanyId,
                    CompanyName = t.Company!.Name,
                    t.Company.AllowCod,
                    t.Company.MaxCodSeatsPerBooking,
                    t.RouteId,
                    RouteName = t.Route!.Name,
                    OriginProvince = t.Route.OriginProvince!.Name,
                    DestinationProvince = t.Route.DestinationProvince!.Name,
                    t.Route.DistanceKm,
                    t.Route.EstimatedDurationMinutes,
                    t.BusId,
                    t.Bus!.PlateNumber,
                    t.Bus.BusType,
                    t.Bus.BrandModel,
                    t.Bus.TotalSeats,
                    t.DepartureAt,
                    t.ArrivalEstimate,
                    t.DelayedArrivalEstimate,
                    t.DelayReason,
                    t.BasePrice,
                    t.Status,
                    AvailableSeats = t.TripSeats.Count(ts => ts.SeatStatus == SeatStatuses.Available),
                    PickupStops = t.Route.Stops
                        .Where(s => s.StopType == StopTypes.Pickup || s.StopType == StopTypes.Both)
                        .OrderBy(s => s.Sequence)
                        .Select(s => new { s.RouteStopId, s.StopName, s.Address, s.OffsetMinutes, s.Surcharge }),
                    DropoffStops = t.Route.Stops
                        .Where(s => s.StopType == StopTypes.Dropoff || s.StopType == StopTypes.Both)
                        .OrderBy(s => s.Sequence)
                        .Select(s => new { s.RouteStopId, s.StopName, s.Address, s.OffsetMinutes, s.Surcharge })
                })
                .Where(t => t.AvailableSeats >= Math.Max(1, passengers))
                .ToList();

            return Ok(result);
        }

        [HttpGet("trips/{id:int}")]
        public async Task<IActionResult> GetTripDetail(int id)
        {
            await SeatHoldCleanupService.ReleaseExpiredHoldsInDbAsync(_db);

            var t = await _db.Trips
                .Include(x => x.Company)
                .Include(x => x.Route)!.ThenInclude(r => r!.OriginProvince)
                .Include(x => x.Route)!.ThenInclude(r => r!.DestinationProvince)
                .Include(x => x.Route)!.ThenInclude(r => r!.Stops)
                .Include(x => x.Bus)
                .Include(x => x.TripSeats)
                .Include(x => x.DriverAssignments).ThenInclude(da => da.Driver)
                .FirstOrDefaultAsync(x => x.TripId == id);

            if (t == null) return NotFound(new { message = "Không tìm thấy chuyến xe." });

            var reviews = await _db.Reviews
                .Include(r => r.User)
                .Where(r => r.CompanyId == t.CompanyId)
                .OrderByDescending(r => r.CreatedAt)
                .Take(10)
                .Select(r => new { r.ReviewId, UserName = r.User!.FullName, r.Rating, r.Comment, r.CreatedAt })
                .ToListAsync();

            return Ok(new
            {
                t.TripId,
                t.CompanyId,
                CompanyName = t.Company!.Name,
                CompanyPhone = t.Company.Phone,
                t.Company.AllowCod,
                t.Company.MaxCodSeatsPerBooking,
                t.Company.SeatHoldMinutes,
                t.RouteId,
                RouteName = t.Route!.Name,
                OriginProvince = t.Route.OriginProvince!.Name,
                DestinationProvince = t.Route.DestinationProvince!.Name,
                t.Route.DistanceKm,
                t.Route.EstimatedDurationMinutes,
                t.BusId,
                t.Bus!.PlateNumber,
                t.Bus.BusType,
                t.Bus.BrandModel,
                t.Bus.TotalSeats,
                t.DepartureAt,
                t.ArrivalEstimate,
                t.DelayedArrivalEstimate,
                t.DelayReason,
                t.BasePrice,
                t.Status,
                Drivers = t.DriverAssignments
                    .Where(da => da.ReleasedAt == null && da.Driver != null)
                    .Select(da => new { da.Driver!.DriverId, da.Driver.FullName, da.Driver.Phone, da.Role }),
                AvailableSeats = t.TripSeats.Count(ts => ts.SeatStatus == SeatStatuses.Available),
                Stops = t.Route.Stops.OrderBy(s => s.Sequence).Select(s => new
                {
                    s.RouteStopId,
                    s.StopName,
                    s.Address,
                    s.Sequence,
                    s.OffsetMinutes,
                    s.Surcharge,
                    s.Latitude,
                    s.Longitude,
                    s.StopType
                }),
                Reviews = reviews
            });
        }

        [HttpGet("trips/{id:int}/seats")]
        public async Task<IActionResult> GetTripSeats(int id)
        {
            await SeatHoldCleanupService.ReleaseExpiredHoldsInDbAsync(_db);

            var seats = await _db.TripSeats
                .Include(ts => ts.BusSeat)
                .Where(ts => ts.TripId == id)
                .OrderBy(ts => ts.Deck)
                .ThenBy(ts => ts.Row)
                .ThenBy(ts => ts.Column)
                .Select(ts => new
                {
                    ts.TripSeatId,
                    ts.TripId,
                    ts.SeatCode,
                    ts.Deck,
                    ts.Row,
                    ts.Column,
                    SeatType = ts.BusSeat != null ? ts.BusSeat.SeatType : "Standard",
                    ts.SeatStatus,
                    ts.CurrentPrice
                })
                .ToListAsync();

            return Ok(seats);
        }

        // BR22, AT10: Chỉ người có vé/booking hợp lệ của chuyến, tài xế được giao, nhân sự nhà xe hoặc Admin mới xem được GPS chuyến
        [Authorize]
        [HttpGet("trips/{id:int}/tracking")]
        public async Task<IActionResult> GetTripTracking(int id)
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var roles = User.FindAll(ClaimTypes.Role).Select(c => c.Value).ToList();
            int? userCompanyId = int.TryParse(User.FindFirstValue("companyId"), out int cid) ? cid : null;
            int? userDriverId = int.TryParse(User.FindFirstValue("driverId"), out int did) ? did : null;

            var trip = await _db.Trips
                .Include(t => t.Route)!.ThenInclude(r => r!.Stops)
                .Include(t => t.Bus)
                .FirstOrDefaultAsync(t => t.TripId == id);
            if (trip == null) return NotFound();

            bool isAuthorized = roles.Contains(RoleNames.Admin)
                || (userCompanyId.HasValue && userCompanyId.Value == trip.CompanyId)
                || (userDriverId.HasValue && await _db.DriverAssignments.AnyAsync(da => da.TripId == id && da.DriverId == userDriverId.Value && da.ReleasedAt == null))
                || await _db.Bookings.AnyAsync(b => b.TripId == id && b.UserId == userId && (b.Status == BookingStatuses.Confirmed || b.Status == BookingStatuses.Completed));

            if (!isAuthorized)
            {
                return StatusCode(403, new { message = "Chỉ hành khách có vé hợp lệ của chuyến mới được xem vị trí GPS trực tiếp (BR22, AT10)." });
            }

            var live = await _db.TripLiveLocations.FirstOrDefaultAsync(l => l.TripId == id);
            var history = await _db.TripLocations
                .Where(l => l.TripId == id)
                .OrderByDescending(l => l.RecordedAt)
                .Take(20)
                .ToListAsync();

            var statusHistory = await _db.TripStatusHistories
                .Where(h => h.TripId == id)
                .OrderByDescending(h => h.ChangedAt)
                .ToListAsync();

            return Ok(new
            {
                trip.TripId,
                trip.Status,
                trip.DepartureAt,
                trip.ArrivalEstimate,
                trip.DelayedArrivalEstimate,
                trip.DelayReason,
                trip.Bus!.PlateNumber,
                RouteName = trip.Route!.Name,
                LiveLocation = live,
                RecentLocations = history,
                StatusHistory = statusHistory,
                Stops = trip.Route.Stops.OrderBy(s => s.Sequence).Select(s => new { s.StopName, s.Address, s.Latitude, s.Longitude, s.OffsetMinutes })
            });
        }

        // Mở rộng nâng cao: Nút SOS Khẩn cấp từ hành khách trên chuyến xe (Gửi tọa độ GPS hiện tại & cảnh báo tới Nhà xe / Admin)
        [Authorize]
        [HttpPost("trips/{id:int}/sos")]
        public async Task<IActionResult> TriggerPassengerSos(int id, [FromBody] SosAlertDto dto)
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var user = await _db.Users.FindAsync(userId);
            var trip = await _db.Trips
                .Include(t => t.Route)
                .Include(t => t.Bus)
                .Include(t => t.DriverAssignments)
                .FirstOrDefaultAsync(t => t.TripId == id);
            if (trip == null) return NotFound();

            var liveLoc = await _db.TripLiveLocations.FirstOrDefaultAsync(l => l.TripId == id);
            int driverId = trip.DriverAssignments.FirstOrDefault(da => da.ReleasedAt == null)?.DriverId
                ?? await _db.Drivers.Where(d => d.CompanyId == trip.CompanyId).Select(d => d.DriverId).FirstOrDefaultAsync();

            string locText = liveLoc != null ? $"Lat {liveLoc.Latitude}, Lng {liveLoc.Longitude}" : "Chưa có tọa độ GPS";
            string note = string.IsNullOrWhiteSpace(dto.Message) ? "Hành khách cần hỗ trợ y tế / an toàn khẩn cấp trên xe!" : dto.Message.Trim();

            if (driverId > 0)
            {
                _db.TripIncidents.Add(new TripIncident
                {
                    TripId = id,
                    DriverId = driverId,
                    Type = "SOS KHẨN CẤP TỪ HÀNH KHÁCH",
                    Description = $"Khách {user?.FullName} ({user?.Phone}): {note} [Vị trí xe: {locText}]",
                    CreatedAt = DateTime.UtcNow
                });
            }

            _db.SupportRequests.Add(new SupportRequest
            {
                UserId = userId,
                CompanyId = trip.CompanyId,
                Subject = $"[SOS KHẨN CẤP] Chuyến #{id} ({trip.Bus?.PlateNumber})",
                Content = $"{note} — Tọa độ xe: {locText}",
                Status = "Open",
                CreatedAt = DateTime.UtcNow
            });

            _db.AuditLogs.Add(new AuditLog
            {
                UserId = userId,
                CompanyId = trip.CompanyId,
                Action = "PassengerSOS",
                EntityName = "Trip",
                EntityId = id.ToString(),
                Details = $"Cảnh báo SOS từ hành khách {user?.FullName} ({user?.Phone}) trên chuyến #{id}: {note}"
            });

            await _db.SaveChangesAsync();

            return Ok(new
            {
                message = $"Đã phát tín hiệu SOS khẩn cấp kèm tọa độ xe ({locText}) tới Trung tâm điều hành Nhà xe và Admin!",
                ShareTripText = $"[Hành trình BusTicketBooking] Tôi đang đi trên xe {trip.Bus?.PlateNumber} ({trip.Route?.Name}), khởi hành {trip.DepartureAt:dd/MM HH:mm}. Tọa độ GPS hiện tại: {locText}."
            });
        }

        // Đợt 2 - Tính năng #1: Danh sách chờ tự động khi chuyến xe hết ghế hoặc săn ghế trống (Trip Waitlist & Auto-Alert)
        [Authorize]
        [HttpGet("trips/{id:int}/waitlist")]
        public async Task<IActionResult> GetTripWaitlist(int id)
        {
            var list = await _db.TripWaitlists
                .Where(w => w.TripId == id)
                .OrderByDescending(w => w.CreatedAt)
                .ToListAsync();
            return Ok(list);
        }

        [Authorize]
        [HttpPost("trips/{id:int}/waitlist")]
        public async Task<IActionResult> JoinTripWaitlist(int id, [FromBody] JoinWaitlistDto dto)
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var user = await _db.Users.FindAsync(userId);
            var trip = await _db.Trips.Include(t => t.Route).FirstOrDefaultAsync(t => t.TripId == id);
            if (trip == null) return NotFound(new { message = "Không tìm thấy chuyến xe." });

            var entry = new TripWaitlist
            {
                TripId = id,
                UserId = userId,
                CustomerName = string.IsNullOrWhiteSpace(dto.CustomerName) ? (user?.FullName ?? "Hành khách") : dto.CustomerName.Trim(),
                CustomerPhone = string.IsNullOrWhiteSpace(dto.CustomerPhone) ? (user?.Phone ?? "0900000000") : dto.CustomerPhone.Trim(),
                SeatCountRequested = Math.Max(1, dto.SeatCountRequested),
                Status = "Waiting",
                CreatedAt = DateTime.UtcNow
            };
            _db.TripWaitlists.Add(entry);
            await _db.SaveChangesAsync();

            return Ok(new
            {
                message = $"Đã đăng ký danh sách chờ ({entry.SeatCountRequested} ghế) cho chuyến {trip.Route?.Name}. Hệ thống sẽ tự động báo ngay khi có ghế trống!",
                entry
            });
        }

        // Lấy thông tin liên lạc tài xế & nhà xe của chuyến để gọi điện / nhắn tin
        [HttpGet("trips/{id:int}/driver-contact")]
        public async Task<IActionResult> GetDriverContact(int id)
        {
            var trip = await _db.Trips
                .Include(t => t.Company)
                .Include(t => t.Bus)
                .Include(t => t.Route)
                .FirstOrDefaultAsync(t => t.TripId == id);

            if (trip == null) return NotFound(new { message = "Không tìm thấy chuyến xe." });

            var assignment = await _db.DriverAssignments
                .Include(da => da.Driver)
                .Where(da => da.TripId == id)
                .OrderByDescending(da => da.Role == "Primary")
                .FirstOrDefaultAsync();

            var driver = assignment?.Driver;
            string driverName = driver?.FullName ?? "Nguyễn Văn Tài (Tài xế chính)";
            string driverPhone = driver?.Phone ?? "0901000004";

            return Ok(new
            {
                TripId = trip.TripId,
                DriverName = driverName,
                DriverPhone = driverPhone,
                PlateNumber = trip.Bus?.PlateNumber ?? "51B-288.99",
                BusType = trip.Bus?.BusType ?? "Sleeper40",
                CompanyName = trip.Company?.Name ?? "Phương Trang (FUTA Bus Lines)",
                CompanyHotline = trip.Company?.Phone ?? "19006067",
                RouteName = trip.Route?.Name ?? "TP. Hồ Chí Minh -> Đà Lạt",
                TripStatus = trip.Status
            });
        }

        // Lấy tin nhắn trao đổi giữa khách và tài xế/nhà xe trên chuyến
        [HttpGet("trips/{id:int}/messages")]
        public async Task<IActionResult> GetTripMessages(int id, [FromQuery] int? bookingId = null)
        {
            var query = _db.TripMessages
                .Where(m => m.TripId == id);

            if (bookingId.HasValue && bookingId.Value > 0)
            {
                query = query.Where(m => m.BookingId == null || m.BookingId == bookingId.Value);
            }

            var messages = await query
                .OrderBy(m => m.CreatedAt)
                .Take(100)
                .Select(m => new
                {
                    m.MessageId,
                    m.TripId,
                    m.BookingId,
                    m.SenderUserId,
                    m.SenderName,
                    m.SenderRole,
                    m.Content,
                    m.IsRead,
                    m.CreatedAt
                })
                .ToListAsync();

            return Ok(messages);
        }

        // Gửi tin nhắn giữa hành khách và tài xế/nhân viên
        [Authorize]
        [HttpPost("trips/{id:int}/messages")]
        public async Task<IActionResult> SendTripMessage(int id, [FromBody] SendTripMessageDto dto)
        {
            if (string.IsNullOrWhiteSpace(dto.Content))
            {
                return BadRequest(new { message = "Nội dung tin nhắn không được để trống." });
            }

            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var roles = User.FindAll(ClaimTypes.Role).Select(c => c.Value).ToList();
            var user = await _db.Users.FindAsync(userId);

            var trip = await _db.Trips
                .Include(t => t.Route)
                .Include(t => t.Bus)
                .FirstOrDefaultAsync(t => t.TripId == id);
            if (trip == null) return NotFound(new { message = "Không tìm thấy chuyến xe." });

            bool isDriverOrStaff = roles.Contains(RoleNames.Driver) || roles.Contains(RoleNames.Staff) || roles.Contains(RoleNames.BusOperator);
            string role = isDriverOrStaff ? "Driver" : "Customer";
            string senderName = user?.FullName ?? (isDriverOrStaff ? "Tài xế chuyến xe" : "Hành khách");

            var msg = new TripMessage
            {
                TripId = id,
                BookingId = dto.BookingId,
                SenderUserId = userId,
                SenderName = senderName,
                SenderRole = role,
                Content = dto.Content.Trim(),
                IsRead = false,
                CreatedAt = DateTime.UtcNow
            };

            _db.TripMessages.Add(msg);

            // Bắn Notification thông báo tin nhắn mới
            if (isDriverOrStaff)
            {
                // Tài xế gửi -> Thông báo cho hành khách
                var passengerUserIds = await _db.Bookings
                    .Where(b => b.TripId == id && b.Status == BookingStatuses.Confirmed)
                    .Select(b => b.UserId)
                    .Distinct()
                    .ToListAsync();

                foreach (var pUid in passengerUserIds)
                {
                    _db.Notifications.Add(new Notification
                    {
                        UserId = pUid,
                        Title = $"💬 Tin nhắn từ Tài xế {senderName}",
                        Content = msg.Content,
                        Type = "ChatMessage",
                        ReferenceId = id,
                        CreatedAt = DateTime.UtcNow
                    });
                }
            }
            else
            {
                // Hành khách gửi -> Thông báo cho tài xế/nhà xe
                var driverAssignment = await _db.DriverAssignments
                    .Include(da => da.Driver)
                    .FirstOrDefaultAsync(da => da.TripId == id);

                if (driverAssignment?.Driver?.UserId != null)
                {
                    _db.Notifications.Add(new Notification
                    {
                        UserId = driverAssignment.Driver.UserId.Value,
                        Title = $"💬 Tin nhắn từ Khách {senderName}",
                        Content = msg.Content,
                        Type = "ChatMessage",
                        ReferenceId = id,
                        CreatedAt = DateTime.UtcNow
                    });
                }
            }

            await _db.SaveChangesAsync();
            return Ok(new
            {
                message = "Đã gửi tin nhắn thành công.",
                data = new
                {
                    msg.MessageId,
                    msg.TripId,
                    msg.BookingId,
                    msg.SenderUserId,
                    msg.SenderName,
                    msg.SenderRole,
                    msg.Content,
                    msg.IsRead,
                    msg.CreatedAt
                }
            });
        }

        // Tài xế/Nhà xe phát Thông báo Đẩy khi xe đang tới gần điểm đón của khách (Push Notification / Bus Approaching)
        [Authorize]
        [HttpPost("trips/{id:int}/notify-approaching")]
        public async Task<IActionResult> NotifyBusApproaching(int id, [FromBody] NotifyBusApproachingDto dto)
        {
            var trip = await _db.Trips
                .Include(t => t.Route)
                .Include(t => t.Bus)
                .Include(t => t.Company)
                .FirstOrDefaultAsync(t => t.TripId == id);

            if (trip == null) return NotFound(new { message = "Không tìm thấy chuyến xe." });

            var assignment = await _db.DriverAssignments.Include(da => da.Driver).FirstOrDefaultAsync(da => da.TripId == id);
            string driverName = assignment?.Driver?.FullName ?? "Nguyễn Văn Tài";
            string plate = trip.Bus?.PlateNumber ?? "51B-288.99";
            string stopName = string.IsNullOrWhiteSpace(dto.StopName) ? "Điểm đón của bạn" : dto.StopName.Trim();
            int mins = dto.EstimatedMinutes > 0 ? dto.EstimatedMinutes : 10;

            string title = "🚌 Chuyến xe của bạn đang tới gần!";
            string body = $"Tài xế {driverName} (Xe {plate}) đang di chuyển tới {stopName}. Dự kiến tới trong khoảng {mins} phút nữa. Quý khách vui lòng chuẩn bị hành lý và đứng tại điểm đón!";
            if (!string.IsNullOrWhiteSpace(dto.Note))
            {
                body += $"\nLời nhắn từ tài xế: {dto.Note.Trim()}";
            }

            // Tìm toàn bộ hành khách của chuyến có vé confirmed
            var passengerUserIds = await _db.Bookings
                .Where(b => b.TripId == id && (b.Status == BookingStatuses.Confirmed || b.Status == BookingStatuses.PendingPayment))
                .Select(b => b.UserId)
                .Distinct()
                .ToListAsync();

            foreach (var uid in passengerUserIds)
            {
                _db.Notifications.Add(new Notification
                {
                    UserId = uid,
                    Title = title,
                    Content = body,
                    Type = "BusApproaching",
                    ReferenceId = id,
                    CreatedAt = DateTime.UtcNow
                });
            }

            // Ghi nhận thêm 1 tin nhắn tự động từ tài xế vào luồng chat chuyến
            _db.TripMessages.Add(new TripMessage
            {
                TripId = id,
                SenderUserId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!),
                SenderName = $"Tài xế {driverName}",
                SenderRole = "Driver",
                Content = $"[HỆ THỐNG PHÁT THÔNG BÁO ĐẨY] {body}",
                CreatedAt = DateTime.UtcNow
            });

            await _db.SaveChangesAsync();

            return Ok(new
            {
                message = $"Đã phát thông báo đẩy xe sắp tới gần tới {passengerUserIds.Count} hành khách trên chuyến #{id}!",
                title,
                body,
                notifiedCount = passengerUserIds.Count
            });
        }

        // Bắt đầu cuộc gọi thoại nội bộ qua App (In-App VoIP Call)
        [Authorize]
        [HttpPost("trips/{id:int}/calls/initiate")]
        public async Task<IActionResult> InitiateCall(int id, [FromBody] InitiateCallDto dto)
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var roles = User.FindAll(ClaimTypes.Role).Select(c => c.Value).ToList();
            var user = await _db.Users.FindAsync(userId);
            bool isDriverOrStaff = roles.Contains(RoleNames.Driver) || roles.Contains(RoleNames.Staff) || roles.Contains(RoleNames.BusOperator);
            string role = isDriverOrStaff ? "Driver" : "Customer";
            string callerName = user?.FullName ?? (isDriverOrStaff ? "Tài xế chuyến xe" : "Hành khách");
            string targetName = string.IsNullOrWhiteSpace(dto.TargetName) ? (isDriverOrStaff ? "Hành khách" : "Bác tài") : dto.TargetName.Trim();

            var session = _callSignaling.InitiateCall(id, userId, callerName, role, targetName, dto.OfferSdp);

            // Bắn Notification cuộc gọi đến
            if (isDriverOrStaff)
            {
                var passengerUserIds = await _db.Bookings
                    .Where(b => b.TripId == id && (b.Status == BookingStatuses.Confirmed || b.Status == BookingStatuses.PendingPayment))
                    .Select(b => b.UserId)
                    .Distinct()
                    .ToListAsync();

                foreach (var pUid in passengerUserIds)
                {
                    _db.Notifications.Add(new Notification
                    {
                        UserId = pUid,
                        Title = $"📞 Cuộc gọi thoại qua App từ {callerName}",
                        Content = $"Bác tài đang gọi thoại qua ứng dụng cho bạn trên chuyến xe #{id}.",
                        Type = "IncomingCall",
                        ReferenceId = id,
                        CreatedAt = DateTime.UtcNow
                    });
                }
            }
            else
            {
                var assignment = await _db.DriverAssignments
                    .Include(da => da.Driver)
                    .FirstOrDefaultAsync(da => da.TripId == id);

                if (assignment?.Driver?.UserId != null)
                {
                    _db.Notifications.Add(new Notification
                    {
                        UserId = assignment.Driver.UserId.Value,
                        Title = $"📞 Cuộc gọi thoại qua App từ {callerName}",
                        Content = $"Hành khách đang gọi thoại qua ứng dụng cho bạn về chuyến xe #{id}.",
                        Type = "IncomingCall",
                        ReferenceId = id,
                        CreatedAt = DateTime.UtcNow
                    });
                }
            }

            await _db.SaveChangesAsync();

            return Ok(new
            {
                message = "Đang đổ chuông cuộc gọi thoại qua app...",
                session
            });
        }

        // Lấy trạng thái cuộc gọi hiện tại trên chuyến xe
        [HttpGet("trips/{id:int}/calls/active")]
        public IActionResult GetActiveCall(int id)
        {
            var session = _callSignaling.GetActiveCall(id);
            return Ok(session);
        }

        // Trả lời / Chấp nhận cuộc gọi thoại qua app (Kèm WebRTC Answer SDP)
        [Authorize]
        [HttpPost("trips/{id:int}/calls/{callId}/answer")]
        public IActionResult AnswerCall(int id, string callId, [FromBody] AnswerCallDto? dto)
        {
            var session = _callSignaling.AnswerCall(id, callId, dto?.AnswerSdp);
            if (session == null) return NotFound(new { message = "Cuộc gọi không tồn tại hoặc đã kết thúc." });
            return Ok(new { message = "Đã kết nối cuộc gọi thoại thành công.", session });
        }

        // Trao đổi WebRTC ICE Candidates giữa 2 máy
        [Authorize]
        [HttpPost("trips/{id:int}/calls/{callId}/ice-candidate")]
        public IActionResult AddIceCandidate(int id, string callId, [FromBody] AddIceCandidateDto dto)
        {
            bool ok = _callSignaling.AddIceCandidate(id, callId, dto.Candidate, dto.IsCaller);
            return Ok(new { success = ok });
        }

        // Kết thúc / Từ chối cuộc gọi thoại qua app
        [Authorize]
        [HttpPost("trips/{id:int}/calls/{callId}/end")]
        public async Task<IActionResult> EndCall(int id, string callId, [FromQuery] bool reject = false)
        {
            var session = _callSignaling.EndCall(id, callId, reject);
            if (session != null)
            {
                int duration = session.DurationSeconds;
                string durStr = $"{duration / 60:D2}:{duration % 60:D2}";
                string statusText = reject ? "Cuộc gọi bị từ chối" : $"Cuộc gọi thoại qua app kết thúc ({durStr})";

                _db.TripMessages.Add(new TripMessage
                {
                    TripId = id,
                    SenderUserId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!),
                    SenderName = session.CallerName,
                    SenderRole = session.CallerRole,
                    Content = $"📞 [THOẠI QUA APP] {statusText}",
                    CreatedAt = DateTime.UtcNow
                });
                await _db.SaveChangesAsync();
            }
            return Ok(new { message = "Cuộc gọi đã kết thúc.", session });
        }
    }

    public record SosAlertDto(string? Message);
    public record JoinWaitlistDto(string? CustomerName, string? CustomerPhone, int SeatCountRequested = 1);
    public record SendTripMessageDto(string Content, int? BookingId = null);
    public record NotifyBusApproachingDto(string? StopName = null, int EstimatedMinutes = 10, string? Note = null);
    public record InitiateCallDto(string? TargetName = null, string? OfferSdp = null);
    public record AnswerCallDto(string? AnswerSdp = null);
    public record AddIceCandidateDto(string Candidate, bool IsCaller);
}

