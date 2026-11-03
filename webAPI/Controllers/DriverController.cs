using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using webAPI.Data;
using webAPI.Hubs;
using webAPI.Models;
using webAPI.Services;

namespace webAPI.Controllers
{
    [Authorize]
    [ApiController]
    [Route("api")]
    public class DriverController : ControllerBase
    {
        private readonly BusBookingDbContext _db;
        private readonly IHubContext<TripTrackingHub> _hub;

        public DriverController(BusBookingDbContext db, IHubContext<TripTrackingHub> hub)
        {
            _db = db;
            _hub = hub;
        }

        [HttpGet("driver/trips")]
        public async Task<IActionResult> GetAssignedTrips()
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var roles = User.FindAll(ClaimTypes.Role).Select(c => c.Value).ToList();
            int? driverId = int.TryParse(User.FindFirstValue("driverId"), out int did) ? did : null;
            int? companyId = int.TryParse(User.FindFirstValue("companyId"), out int cid) ? cid : null;

            var query = _db.Trips
                .Include(t => t.Route)
                .Include(t => t.Bus)
                .Include(t => t.Company)
                .Include(t => t.DriverAssignments).ThenInclude(da => da.Driver)
                .AsQueryable();

            if (driverId.HasValue && !roles.Contains(RoleNames.Admin) && !roles.Contains(RoleNames.BusOperator))
            {
                // BR04: Driver chỉ thao tác chuyến có phân công hợp lệ
                query = query.Where(t => t.DriverAssignments.Any(da => da.DriverId == driverId.Value && da.ReleasedAt == null));
            }
            else if (companyId.HasValue && !roles.Contains(RoleNames.Admin))
            {
                query = query.Where(t => t.CompanyId == companyId.Value);
            }

            var trips = await query.OrderByDescending(t => t.DepartureAt).ToListAsync();
            var tripIds = trips.Select(t => t.TripId).ToList();

            var tickets = await _db.Tickets
                .Include(tk => tk.BookingDetail)!.ThenInclude(bd => bd!.Booking)!.ThenInclude(b => b!.Payments)
                .Include(tk => tk.BookingDetail)!.ThenInclude(bd => bd!.PickupStop)
                .Include(tk => tk.BookingDetail)!.ThenInclude(bd => bd!.DropoffStop)
                .Where(tk => tripIds.Contains(tk.TripId))
                .ToListAsync();

            var liveLocations = await _db.TripLiveLocations
                .Where(l => tripIds.Contains(l.TripId))
                .ToDictionaryAsync(l => l.TripId);

            var incidents = await _db.TripIncidents
                .Where(inc => tripIds.Contains(inc.TripId))
                .OrderByDescending(inc => inc.CreatedAt)
                .ToListAsync();

            var result = trips.Select(t =>
            {
                var tripTickets = tickets.Where(tk => tk.TripId == t.TripId).ToList();
                var tripIncidents = incidents.Where(inc => inc.TripId == t.TripId).ToList();
                liveLocations.TryGetValue(t.TripId, out var liveLoc);
                return new
                {
                    t.TripId,
                    RouteName = t.Route?.Name,
                    CompanyName = t.Company?.Name,
                    PlateNumber = t.Bus?.PlateNumber,
                    BusType = t.Bus?.BusType,
                    t.DepartureAt,
                    t.ArrivalEstimate,
                    t.DelayedArrivalEstimate,
                    t.DelayReason,
                    t.Status,
                    Drivers = t.DriverAssignments.Where(da => da.ReleasedAt == null && da.Driver != null).Select(da => da.Driver!.FullName).ToList(),
                    LiveLocation = liveLoc == null ? null : new { liveLoc.Latitude, liveLoc.Longitude, liveLoc.SpeedKmh, liveLoc.UpdatedAt },
                    Incidents = tripIncidents.Select(inc => new { inc.IncidentId, inc.Type, inc.Description, inc.CreatedAt }),
                    TotalTickets = tripTickets.Count,
                    CheckedInTickets = tripTickets.Count(tk => tk.Status == TicketStatuses.Used),
                    Passengers = tripTickets.Select(tk =>
                    {
                        var booking = tk.BookingDetail!.Booking!;
                        var payment = booking.Payments.OrderByDescending(p => p.PaymentId).FirstOrDefault();
                        return new
                        {
                            tk.TicketId,
                            tk.TicketCode,
                            tk.QRDisplayPayload,
                            TicketStatus = tk.Status,
                            SeatCode = tk.BookingDetail.SeatCode,
                            PassengerName = tk.BookingDetail.PassengerName,
                            PassengerPhone = tk.BookingDetail.PassengerPhone,
                            PickupStop = tk.BookingDetail.PickupStop?.StopName ?? "Tại bến",
                            DropoffStop = tk.BookingDetail.DropoffStop?.StopName ?? "Tại bến",
                            BookingId = booking.BookingId,
                            BookingCode = booking.BookingCode,
                            TotalAmount = booking.TotalAmount,
                            PaymentMethod = payment?.Method ?? "VNPay",
                            PaymentStatus = payment?.Status ?? PaymentStatuses.Unpaid
                        };
                    }).OrderBy(p => p.SeatCode).ToList()
                };
            });

            return Ok(result);
        }

        // Tra cứu thông tin vé & trạng thái thu tiền/lên xe (Dành cho Nhân viên Soát vé)
        [HttpPost("tickets/inspect")]
        public async Task<IActionResult> InspectTicket([FromBody] CheckInDto dto)
        {
            var rawInput = (dto.QrOrTicketCode ?? "").Trim();
            if (string.IsNullOrEmpty(rawInput))
            {
                return BadRequest(new { message = "Mã vé hoặc chuỗi QR không được để trống." });
            }

            var hashInput = SecurityHelper.ComputeSha256(rawInput);
            var ticket = await _db.Tickets
                .Include(t => t.BookingDetail)!.ThenInclude(bd => bd!.Booking)!.ThenInclude(b => b!.Payments)
                .Include(t => t.BookingDetail)!.ThenInclude(bd => bd!.Booking)!.ThenInclude(b => b!.Trip)!.ThenInclude(tr => tr!.Route)
                .Include(t => t.BookingDetail)!.ThenInclude(bd => bd!.Booking)!.ThenInclude(b => b!.Trip)!.ThenInclude(tr => tr!.Bus)
                .Include(t => t.BookingDetail)!.ThenInclude(bd => bd!.Booking)!.ThenInclude(b => b!.Trip)!.ThenInclude(tr => tr!.Company)
                .Include(t => t.BookingDetail)!.ThenInclude(bd => bd!.PickupStop)
                .Include(t => t.BookingDetail)!.ThenInclude(bd => bd!.DropoffStop)
                .Include(t => t.CheckIns)
                .FirstOrDefaultAsync(t =>
                    t.QRTokenHash == hashInput ||
                    t.QRDisplayPayload == rawInput ||
                    t.TicketCode == rawInput ||
                    rawInput.Contains(t.TicketCode) ||
                    t.TicketCode.Contains(rawInput));

            if (ticket == null)
            {
                return NotFound(new { Result = "NotFound", message = "Không tìm thấy vé trong hệ thống với mã QR này!" });
            }

            var booking = ticket.BookingDetail!.Booking!;
            var trip = booking.Trip!;
            var payment = booking.Payments.OrderByDescending(p => p.PaymentId).FirstOrDefault();
            var lastSuccessCheckIn = ticket.CheckIns.Where(c => c.Result == "Success").OrderByDescending(c => c.CheckedAt).FirstOrDefault();

            bool isBoarded = ticket.Status == TicketStatuses.Used;
            bool isPaid = payment != null && payment.Status == PaymentStatuses.Paid;
            bool isCodUnpaid = payment != null && payment.Method == PaymentMethods.COD && payment.Status == PaymentStatuses.Unpaid;
            bool isWrongTrip = dto.TripId.HasValue && dto.TripId.Value > 0 && ticket.TripId != dto.TripId.Value;

            return Ok(new
            {
                Result = "Success",
                TicketId = ticket.TicketId,
                TicketCode = ticket.TicketCode,
                QRDisplayPayload = ticket.QRDisplayPayload,
                TicketStatus = ticket.Status,
                IsBoarded = isBoarded,
                BoardedAt = lastSuccessCheckIn?.CheckedAt,
                SeatCode = ticket.BookingDetail.SeatCode,
                PassengerName = ticket.BookingDetail.PassengerName,
                PassengerPhone = ticket.BookingDetail.PassengerPhone,
                BookingId = booking.BookingId,
                BookingCode = booking.BookingCode,
                TotalAmount = booking.TotalAmount,
                PaymentMethod = payment?.Method ?? "VNPay",
                PaymentStatus = payment?.Status ?? "Unpaid",
                IsPaid = isPaid,
                IsCodUnpaid = isCodUnpaid,
                CodAmountToCollect = isCodUnpaid ? booking.TotalAmount : 0m,
                TripId = trip.TripId,
                IsWrongTrip = isWrongTrip,
                RouteName = trip.Route?.Name,
                CompanyName = trip.Company?.Name,
                PlateNumber = trip.Bus?.PlateNumber,
                BusType = trip.Bus?.BusType,
                DepartureAt = trip.DepartureAt,
                TripStatus = trip.Status,
                PickupStop = ticket.BookingDetail.PickupStop?.StopName ?? "Tại bến",
                DropoffStop = ticket.BookingDetail.DropoffStop?.StopName ?? "Tại bến"
            });
        }

        // UC24, FR18, BR18, AT09: Quét QR Check-in nguyên tử, chống quét lặp/vé sai chuyến/vé đã hủy
        [HttpPost("tickets/check-in")]
        public async Task<IActionResult> CheckInTicket([FromBody] CheckInDto dto)
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var roles = User.FindAll(ClaimTypes.Role).Select(c => c.Value).ToList();
            int? driverId = int.TryParse(User.FindFirstValue("driverId"), out int did) ? did : null;
            int? companyId = int.TryParse(User.FindFirstValue("companyId"), out int cid) ? cid : null;

            if (!roles.Contains(RoleNames.Driver) && !roles.Contains(RoleNames.Staff) && !roles.Contains(RoleNames.BusOperator) && !roles.Contains(RoleNames.Admin))
            {
                return StatusCode(403, new { message = "Chỉ nhân viên hoặc tài xế được cấp quyền mới được check-in vé QR (BR02)." });
            }

            var rawInput = (dto.QrOrTicketCode ?? "").Trim();
            if (string.IsNullOrEmpty(rawInput))
            {
                return BadRequest(new { message = "Mã vé hoặc chuỗi QR không được để trống." });
            }

            using var tx = await _db.Database.BeginTransactionAsync(IsolationLevel.Serializable);
            var hashInput = SecurityHelper.ComputeSha256(rawInput);

            var ticket = await _db.Tickets
                .Include(t => t.BookingDetail)!.ThenInclude(bd => bd!.Booking)!.ThenInclude(b => b!.Payments)
                .Include(t => t.BookingDetail)!.ThenInclude(bd => bd!.Booking)!.ThenInclude(b => b!.Trip)
                .FirstOrDefaultAsync(t =>
                    t.QRTokenHash == hashInput ||
                    t.QRDisplayPayload == rawInput ||
                    t.TicketCode == rawInput ||
                    rawInput.Contains(t.TicketCode) ||
                    t.TicketCode.Contains(rawInput));

            if (ticket == null)
            {
                return NotFound(new { Result = "InvalidTicket", message = "Không tìm thấy vé hợp lệ với mã QR này (AT09)." });
            }

            var trip = ticket.BookingDetail!.Booking!.Trip!;

            // Kiểm tra phạm vi nhà xe hoặc phân công tài xế
            if (!roles.Contains(RoleNames.Admin))
            {
                if (companyId.HasValue && trip.CompanyId != companyId.Value)
                {
                    return StatusCode(403, new { Result = "ForbiddenCompany", message = "Vé này thuộc nhà xe khác (AT02)." });
                }
                if (roles.Contains(RoleNames.Driver) && !roles.Contains(RoleNames.Staff) && !roles.Contains(RoleNames.BusOperator) && driverId.HasValue)
                {
                    bool isAssigned = await _db.DriverAssignments.AnyAsync(da => da.TripId == trip.TripId && da.DriverId == driverId.Value && da.ReleasedAt == null);
                    if (!isAssigned)
                    {
                        return StatusCode(403, new { Result = "NotAssignedTrip", message = "Bạn không được phân công phụ trách chuyến xe của vé này (BR04)." });
                    }
                }
            }

            // AT09: Kiểm tra vé đúng chuyến nếu người quét chọn chuyến cụ thể
            if (dto.TripId.HasValue && dto.TripId.Value > 0 && ticket.TripId != dto.TripId.Value)
            {
                _db.TicketCheckIns.Add(new TicketCheckIn
                {
                    TicketId = ticket.TicketId,
                    CheckedByUserId = userId,
                    DeviceInfo = dto.DeviceInfo ?? "Flutter Scanner",
                    Result = "WrongTrip",
                    Note = $"Vé thuộc chuyến #{ticket.TripId} nhưng quét ở chuyến #{dto.TripId}"
                });
                await _db.SaveChangesAsync();
                await tx.CommitAsync();
                return BadRequest(new { Result = "WrongTrip", message = $"Vé thuộc chuyến #{ticket.TripId}, không khớp với chuyến đang kiểm tra #{dto.TripId} (AT09)." });
            }

            // AT09, BR18: Vé đã hủy hoặc hết hạn bị từ chối
            if (ticket.Status == TicketStatuses.Cancelled || ticket.Status == TicketStatuses.Expired)
            {
                _db.TicketCheckIns.Add(new TicketCheckIn
                {
                    TicketId = ticket.TicketId,
                    CheckedByUserId = userId,
                    DeviceInfo = dto.DeviceInfo ?? "Flutter Scanner",
                    Result = "CancelledTicket",
                    Note = $"Vé ở trạng thái {ticket.Status}"
                });
                await _db.SaveChangesAsync();
                await tx.CommitAsync();
                return BadRequest(new { Result = "CancelledTicket", message = $"Vé đã bị hủy hoặc hết hiệu lực ({ticket.Status}) (AT09)." });
            }

            // AT09, BR18: Chống check-in lặp 2 lần
            if (ticket.Status == TicketStatuses.Used)
            {
                _db.TicketCheckIns.Add(new TicketCheckIn
                {
                    TicketId = ticket.TicketId,
                    CheckedByUserId = userId,
                    DeviceInfo = dto.DeviceInfo ?? "Flutter Scanner",
                    Result = "AlreadyCheckedIn",
                    Note = "Quét trùng vé đã lên xe"
                });
                await _db.SaveChangesAsync();
                await tx.CommitAsync();
                return Conflict(new
                {
                    Result = "AlreadyCheckedIn",
                    message = $"Vé {ticket.TicketCode} (Ghế {ticket.BookingDetail.SeatCode} - {ticket.BookingDetail.PassengerName}) ĐÃ CHECK-IN trước đó! Từ chối quét lặp (AT09, BR18)."
                });
            }

            // Check-in hợp lệ
            ticket.Status = TicketStatuses.Used;
            _db.TicketCheckIns.Add(new TicketCheckIn
            {
                TicketId = ticket.TicketId,
                CheckedByUserId = userId,
                DeviceInfo = dto.DeviceInfo ?? "Flutter Scanner",
                Result = "Success",
                Note = "Check-in lên xe hợp lệ"
            });

            var booking = ticket.BookingDetail.Booking!;
            var payment = booking.Payments.OrderByDescending(p => p.PaymentId).FirstOrDefault();

            // Nếu người quét chọn thu tiền COD luôn khi lên xe
            if (dto.CollectCodNow && payment != null && payment.Method == PaymentMethods.COD && payment.Status == PaymentStatuses.Unpaid)
            {
                payment.Status = PaymentStatuses.Paid;
                payment.CollectedByUserId = userId;
                payment.PaidAt = DateTime.UtcNow;
                _db.PaymentTransactions.Add(new PaymentTransaction
                {
                    PaymentId = payment.PaymentId,
                    ProviderRef = $"COD-CHECKIN-{userId}",
                    TxnRef = booking.BookingCode,
                    ResponseCode = "00",
                    RawStatus = "COD_Collected_At_Boarding",
                    SignatureValid = true
                });
            }

            _db.AuditLogs.Add(new AuditLog
            {
                UserId = userId,
                CompanyId = trip.CompanyId,
                Action = "TicketCheckIn",
                EntityName = "Ticket",
                EntityId = ticket.TicketCode,
                Details = $"Check-in thành công ghế {ticket.BookingDetail.SeatCode} ({ticket.BookingDetail.PassengerName})"
            });

            await _db.SaveChangesAsync();
            await tx.CommitAsync();

            return Ok(new
            {
                Result = "Success",
                message = $"Check-in thành công! Ghế {ticket.BookingDetail.SeatCode} - Hành khách: {ticket.BookingDetail.PassengerName}",
                ticket.TicketCode,
                SeatCode = ticket.BookingDetail.SeatCode,
                PassengerName = ticket.BookingDetail.PassengerName,
                BookingCode = booking.BookingCode,
                PaymentMethod = payment?.Method,
                PaymentStatus = payment?.Status,
                Amount = booking.TotalAmount
            });
        }

        // UC25, BR04, BR28: Tài xế/Nhân viên cập nhật trạng thái chuyến (Boarding, Departed, Delayed, Arrived)
        [HttpPost("driver/trips/{id:int}/status")]
        public async Task<IActionResult> UpdateTripStatus(int id, [FromBody] UpdateTripStatusDto dto)
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var roles = User.FindAll(ClaimTypes.Role).Select(c => c.Value).ToList();
            int? driverId = int.TryParse(User.FindFirstValue("driverId"), out int did) ? did : null;
            int? companyId = int.TryParse(User.FindFirstValue("companyId"), out int cid) ? cid : null;

            var trip = await _db.Trips
                .Include(t => t.Route)
                .FirstOrDefaultAsync(t => t.TripId == id);
            if (trip == null) return NotFound();

            if (!roles.Contains(RoleNames.Admin))
            {
                if (roles.Contains(RoleNames.Driver) && !roles.Contains(RoleNames.BusOperator) && !roles.Contains(RoleNames.Staff))
                {
                    bool assigned = driverId.HasValue && await _db.DriverAssignments.AnyAsync(da => da.TripId == id && da.DriverId == driverId.Value && da.ReleasedAt == null);
                    if (!assigned)
                    {
                        return StatusCode(403, new { message = "Tài xế chỉ được cập nhật trạng thái chuyến được phân công hợp lệ (BR04)." });
                    }
                }
                else if (companyId != trip.CompanyId)
                {
                    return StatusCode(403, new { message = "Không thuộc phạm vi nhà xe (BR03)." });
                }
            }

            string oldStatus = trip.Status;
            trip.Status = dto.NewStatus;

            // BR28: Delayed lưu giờ dự kiến mới và lý do; không phải trạng thái kết thúc
            if (dto.NewStatus == TripStatuses.Delayed)
            {
                trip.DelayedArrivalEstimate = dto.DelayedArrivalEstimate ?? trip.ArrivalEstimate.AddMinutes(45);
                trip.DelayReason = string.IsNullOrWhiteSpace(dto.Reason) ? "Mật độ giao thông cao trên tuyến" : dto.Reason;
            }

            // Khi chuyến Arrived -> hoàn tất các Booking Confirmed để khách có thể đánh giá (UC13)
            if (dto.NewStatus == TripStatuses.Arrived)
            {
                var confirmedBookings = await _db.Bookings
                    .Where(b => b.TripId == id && b.Status == BookingStatuses.Confirmed)
                    .ToListAsync();
                foreach (var b in confirmedBookings)
                {
                    b.Status = BookingStatuses.Completed;
                }
            }

            _db.TripStatusHistories.Add(new TripStatusHistory
            {
                TripId = id,
                OldStatus = oldStatus,
                NewStatus = dto.NewStatus,
                ChangedByUserId = userId,
                Reason = dto.Reason ?? $"Chuyển trạng thái sang {dto.NewStatus}"
            });

            // BR25: Thông báo cho hành khách khi chuyến đổi trạng thái hoặc bị trễ
            var passengerUserIds = await _db.Bookings
                .Where(b => b.TripId == id && (b.Status == BookingStatuses.Confirmed || b.Status == BookingStatuses.Completed))
                .Select(b => b.UserId)
                .Distinct()
                .ToListAsync();

            foreach (var pUserId in passengerUserIds)
            {
                _db.Notifications.Add(new Notification
                {
                    UserId = pUserId,
                    Title = $"Cập nhật chuyến xe {trip.Route?.Name}: {dto.NewStatus}",
                    Content = dto.NewStatus == TripStatuses.Delayed
                        ? $"Chuyến xe bị trễ. Giờ đến dự kiến mới: {trip.DelayedArrivalEstimate:HH:mm dd/MM}. Lý do: {trip.DelayReason}"
                        : $"Chuyến xe #{trip.TripId} đã chuyển sang trạng thái {dto.NewStatus}.",
                    Type = "TripStatusChanged",
                    ReferenceId = trip.TripId
                });
            }

            await _db.SaveChangesAsync();

            await _hub.Clients.Group($"trip-{id}").SendAsync("TripStatusUpdated", new
            {
                TripId = id,
                OldStatus = oldStatus,
                NewStatus = trip.Status,
                trip.DelayedArrivalEstimate,
                trip.DelayReason,
                UpdatedAt = DateTime.UtcNow
            });

            return Ok(new
            {
                message = $"Đã cập nhật trạng thái chuyến sang {trip.Status}.",
                trip.TripId,
                trip.Status,
                trip.DelayedArrivalEstimate,
                trip.DelayReason
            });
        }

        // UC26, FR20, BR23, AT10: Chỉ tài xế được phân công và chuyến đang vận hành mới gửi vị trí GPS
        [HttpPost("driver/trips/{id:int}/locations")]
        public async Task<IActionResult> SendGpsLocation(int id, [FromBody] SendGpsDto dto)
        {
            var roles = User.FindAll(ClaimTypes.Role).Select(c => c.Value).ToList();
            int? driverId = int.TryParse(User.FindFirstValue("driverId"), out int did) ? did : null;

            var trip = await _db.Trips.FindAsync(id);
            if (trip == null) return NotFound();

            // Section 5.12: Kết thúc/hủy chuyến thì dừng gửi vị trí trực tiếp
            if (trip.Status == TripStatuses.Arrived || trip.Status == TripStatuses.Cancelled)
            {
                return BadRequest(new { message = $"Chuyến xe đã kết thúc ({trip.Status}), dừng nhận dữ liệu GPS trực tiếp (Mục 5.12)." });
            }

            int effectiveDriverId = driverId ?? 0;
            if (!roles.Contains(RoleNames.Admin))
            {
                bool isAssigned = effectiveDriverId > 0 && await _db.DriverAssignments.AnyAsync(
                    da => da.TripId == id && da.DriverId == effectiveDriverId && da.ReleasedAt == null);

                if (!isAssigned)
                {
                    return StatusCode(403, new { message = "Chỉ tài xế được phân công hợp lệ cho chuyến mới được gửi vị trí GPS (AT10, BR23)." });
                }
            }
            else if (effectiveDriverId == 0)
            {
                var firstAssignment = await _db.DriverAssignments.FirstOrDefaultAsync(da => da.TripId == id && da.ReleasedAt == null);
                effectiveDriverId = firstAssignment?.DriverId ?? 1;
            }

            var now = DateTime.UtcNow;
            _db.TripLocations.Add(new TripLocation
            {
                TripId = id,
                DriverId = effectiveDriverId,
                Latitude = dto.Latitude,
                Longitude = dto.Longitude,
                SpeedKmh = dto.SpeedKmh,
                Accuracy = dto.Accuracy,
                RecordedAt = now
            });

            var live = await _db.TripLiveLocations.FirstOrDefaultAsync(l => l.TripId == id);
            if (live == null)
            {
                live = new TripLiveLocation
                {
                    TripId = id,
                    DriverId = effectiveDriverId,
                    Latitude = dto.Latitude,
                    Longitude = dto.Longitude,
                    SpeedKmh = dto.SpeedKmh,
                    Accuracy = dto.Accuracy,
                    UpdatedAt = now
                };
                _db.TripLiveLocations.Add(live);
            }
            else
            {
                live.DriverId = effectiveDriverId;
                live.Latitude = dto.Latitude;
                live.Longitude = dto.Longitude;
                live.SpeedKmh = dto.SpeedKmh;
                live.Accuracy = dto.Accuracy;
                live.UpdatedAt = now;
            }

            await _db.SaveChangesAsync();

            await _hub.Clients.Group($"trip-{id}").SendAsync("LocationUpdated", new
            {
                TripId = id,
                dto.Latitude,
                dto.Longitude,
                dto.SpeedKmh,
                dto.Accuracy,
                UpdatedAt = now
            });

            return Ok(new
            {
                message = "Đã cập nhật tọa độ GPS trực tiếp và phát qua SignalR.",
                TripId = id,
                dto.Latitude,
                dto.Longitude,
                dto.SpeedKmh,
                UpdatedAt = now
            });
        }

        // Section 6.4, Section 10.6: Tài xế báo cáo sự cố hành trình (TripIncidents)
        [HttpPost("driver/trips/{id:int}/incidents")]
        public async Task<IActionResult> ReportIncident(int id, [FromBody] ReportIncidentDto dto)
        {
            int? driverId = int.TryParse(User.FindFirstValue("driverId"), out int did) ? did : null;
            var trip = await _db.Trips.FindAsync(id);
            if (trip == null) return NotFound();

            int effectiveDriverId = driverId ?? 1;
            var incident = new TripIncident
            {
                TripId = id,
                DriverId = effectiveDriverId,
                Type = string.IsNullOrWhiteSpace(dto.Type) ? "Sự cố giao thông" : dto.Type.Trim(),
                Description = string.IsNullOrWhiteSpace(dto.Description) ? "Đang xử lý trên tuyến" : dto.Description.Trim(),
                CreatedAt = DateTime.UtcNow
            };
            _db.TripIncidents.Add(incident);
            await _db.SaveChangesAsync();

            return Ok(new { message = $"Đã ghi nhận báo cáo sự cố '{incident.Type}' cho chuyến #{id}.", incident });
        }

        // Section 5.11, Section 10.5: Lịch sử quét vé QR Check-in của chuyến (TicketCheckIns)
        [HttpGet("driver/trips/{id:int}/check-ins")]
        public async Task<IActionResult> GetTripCheckInHistory(int id)
        {
            var logs = await _db.TicketCheckIns
                .Include(ci => ci.Ticket)!.ThenInclude(t => t!.BookingDetail)
                .Where(ci => ci.Ticket!.TripId == id)
                .OrderByDescending(ci => ci.CheckedAt)
                .Take(40)
                .Select(ci => new
                {
                    ci.CheckInId,
                    ci.TicketId,
                    TicketCode = ci.Ticket!.TicketCode,
                    SeatCode = ci.Ticket.BookingDetail != null ? ci.Ticket.BookingDetail.SeatCode : "",
                    PassengerName = ci.Ticket.BookingDetail != null ? ci.Ticket.BookingDetail.PassengerName : "",
                    ci.CheckedByUserId,
                    ci.DeviceInfo,
                    ci.CheckedAt,
                    ci.Result,
                    ci.Note
                })
                .ToListAsync();

            return Ok(logs);
        }

        // Đợt 2 - Tính năng #7: Bảng kiểm tra an toàn kỹ thuật trước giờ khởi hành (Pre-Departure Safety Checklist)
        [HttpGet("driver/trips/{id:int}/safety-check")]
        public async Task<IActionResult> GetTripSafetyCheck(int id)
        {
            var latest = await _db.TripSafetyChecks
                .Where(s => s.TripId == id)
                .OrderByDescending(s => s.CheckedAt)
                .FirstOrDefaultAsync();
            return Ok(new { safetyCheck = latest });
        }

        [HttpPost("driver/trips/{id:int}/safety-check")]
        public async Task<IActionResult> SubmitTripSafetyCheck(int id, [FromBody] SubmitSafetyCheckDto dto)
        {
            int? driverId = int.TryParse(User.FindFirstValue("driverId"), out int did) ? did : null;
            var check = new TripSafetyCheck
            {
                TripId = id,
                DriverId = driverId ?? 1,
                BrakesOk = dto.BrakesOk,
                TiresOk = dto.TiresOk,
                FireExtinguisherOk = dto.FireExtinguisherOk,
                DashcamOk = dto.DashcamOk,
                ZeroAlcoholConfirmed = dto.ZeroAlcoholConfirmed,
                Note = string.IsNullOrWhiteSpace(dto.Note) ? "Đạt tiêu chuẩn an toàn kỹ thuật xuất bến" : dto.Note.Trim(),
                CheckedAt = DateTime.UtcNow
            };
            _db.TripSafetyChecks.Add(check);
            await _db.SaveChangesAsync();

            return Ok(new
            {
                message = "Đã lưu Biên bản kiểm tra an toàn kỹ thuật & nồng độ cồn trước giờ khởi hành!",
                safetyCheck = check
            });
        }
    }

    public record CheckInDto(string QrOrTicketCode, int? TripId, bool CollectCodNow = false, string? DeviceInfo = null);
    public record UpdateTripStatusDto(string NewStatus, string? Reason, DateTime? DelayedArrivalEstimate = null);
    public record SendGpsDto(double Latitude, double Longitude, double SpeedKmh = 55.0, double Accuracy = 5.0);
    public record ReportIncidentDto(string Type, string Description);
    public record SubmitSafetyCheckDto(bool BrakesOk, bool TiresOk, bool FireExtinguisherOk, bool DashcamOk, bool ZeroAlcoholConfirmed, string? Note);
}

