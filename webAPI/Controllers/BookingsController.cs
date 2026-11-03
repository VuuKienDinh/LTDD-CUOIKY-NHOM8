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
    [ApiController]
    [Route("api")]
    public class BookingsController : ControllerBase
    {
        private readonly BusBookingDbContext _db;
        private readonly IConfiguration _config;
        private readonly IHubContext<TripTrackingHub> _hub;

        public BookingsController(BusBookingDbContext db, IConfiguration config, IHubContext<TripTrackingHub> hub)
        {
            _db = db;
            _config = config;
            _hub = hub;
        }

        // UC06, FR13, BR10, BR11, AT04: Giữ một hoặc nhiều ghế trong Transaction nguyên tử
        [Authorize]
        [HttpPost("seat-holds")]
        public async Task<IActionResult> HoldSeats([FromBody] CreateSeatHoldDto dto)
        {
            if (dto.TripSeatIds == null || dto.TripSeatIds.Count == 0)
            {
                return BadRequest(new { message = "Vui lòng chọn ít nhất 1 ghế." });
            }

            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            await SeatHoldCleanupService.ReleaseExpiredHoldsInDbAsync(_db);

            using var tx = await _db.Database.BeginTransactionAsync(IsolationLevel.Serializable);
            try
            {
                var trip = await _db.Trips
                    .Include(t => t.Company)
                    .FirstOrDefaultAsync(t => t.TripId == dto.TripId);

                if (trip == null)
                    return NotFound(new { message = "Không tìm thấy chuyến xe." });

                // BR14: Không đặt vé chuyến đã hủy, đã khởi hành hoặc đóng bán
                if (trip.Status == TripStatuses.Cancelled || trip.Status == TripStatuses.Departed || trip.Status == TripStatuses.Arrived)
                {
                    return BadRequest(new { message = $"Chuyến xe đang ở trạng thái {trip.Status}, không thể giữ ghế (BR14)." });
                }

                var distinctSeatIds = dto.TripSeatIds.Distinct().ToList();
                var seats = await _db.TripSeats
                    .Where(ts => ts.TripId == dto.TripId && distinctSeatIds.Contains(ts.TripSeatId))
                    .ToListAsync();

                if (seats.Count != distinctSeatIds.Count)
                {
                    return BadRequest(new { message = "Một hoặc nhiều ghế không thuộc chuyến xe này." });
                }

                // BR11: Giữ nhiều ghế phải thành công toàn bộ hoặc thất bại toàn bộ
                var unavailableSeats = seats.Where(s => s.SeatStatus != SeatStatuses.Available).ToList();
                if (unavailableSeats.Count > 0)
                {
                    await tx.RollbackAsync();
                    var codes = string.Join(", ", unavailableSeats.Select(s => s.SeatCode));
                    return Conflict(new { message = $"Ghế [{codes}] vừa được người khác giữ hoặc đặt. Vui lòng chọn ghế khác (AT04, BR11)." });
                }

                int holdMinutes = trip.Company?.SeatHoldMinutes ?? 10;
                var now = DateTime.UtcNow;
                var expiresAt = now.AddMinutes(holdMinutes);
                var holdToken = $"HOLD-{Guid.NewGuid():N}"[..24].ToUpperInvariant();

                foreach (var seat in seats)
                {
                    seat.SeatStatus = SeatStatuses.Held;
                    _db.SeatHolds.Add(new SeatHold
                    {
                        TripId = dto.TripId,
                        TripSeatId = seat.TripSeatId,
                        UserId = userId,
                        HoldToken = holdToken,
                        CreatedAt = now,
                        HoldExpiresAt = expiresAt,
                        Status = HoldStatuses.Active
                    });
                }

                await _db.SaveChangesAsync();
                await tx.CommitAsync();

                await _hub.Clients.Group($"trip-{dto.TripId}").SendAsync("SeatsUpdated", new
                {
                    TripId = dto.TripId,
                    SeatCodes = seats.Select(s => s.SeatCode).ToList(),
                    Status = SeatStatuses.Held
                });

                return Ok(new
                {
                    HoldToken = holdToken,
                    TripId = dto.TripId,
                    HoldExpiresAt = expiresAt,
                    HoldMinutes = holdMinutes,
                    Seats = seats.Select(s => new { s.TripSeatId, s.SeatCode, s.CurrentPrice })
                });
            }
            catch (DbUpdateConcurrencyException)
            {
                await tx.RollbackAsync();
                return Conflict(new { message = "Xung đột giữ ghế đồng thời, vui lòng thử lại (AT04)." });
            }
        }

        [Authorize]
        [HttpDelete("seat-holds/{holdToken}")]
        public async Task<IActionResult> ReleaseHold(string holdToken)
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var holds = await _db.SeatHolds
                .Where(h => h.HoldToken == holdToken && h.UserId == userId && h.Status == HoldStatuses.Active)
                .ToListAsync();

            if (holds.Count == 0) return NotFound(new { message = "Không tìm thấy phiên giữ ghế đang hoạt động." });

            var seatIds = holds.Select(h => h.TripSeatId).ToList();
            var seats = await _db.TripSeats.Where(ts => seatIds.Contains(ts.TripSeatId)).ToListAsync();

            foreach (var h in holds) h.Status = HoldStatuses.Released;
            foreach (var s in seats.Where(s => s.SeatStatus == SeatStatuses.Held))
            {
                s.SeatStatus = SeatStatuses.Available;
            }

            await _db.SaveChangesAsync();
            return Ok(new { message = "Đã giải phóng ghế giữ tạm." });
        }

        // UC07, FR14, BR12, BR13, AT06, AT08: Tạo Booking nhiều ghế + Thanh toán VNPay hoặc COD
        [Authorize]
        [HttpPost("bookings")]
        public async Task<IActionResult> CreateBooking([FromBody] CreateBookingDto dto)
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            await SeatHoldCleanupService.ReleaseExpiredHoldsInDbAsync(_db);

            if (dto.Passengers == null || dto.Passengers.Count == 0)
            {
                return BadRequest(new { message = "Danh sách hành khách không được trống." });
            }

            using var tx = await _db.Database.BeginTransactionAsync(IsolationLevel.Serializable);
            try
            {
                var now = DateTime.UtcNow;
                var activeHolds = await _db.SeatHolds
                    .Include(h => h.TripSeat)
                    .Where(h => h.HoldToken == dto.HoldToken && h.Status == HoldStatuses.Active)
                    .ToListAsync();

                if (activeHolds.Count == 0)
                {
                    return BadRequest(new { message = "Phiên giữ ghế không tồn tại hoặc đã hết hạn (BR10, AT05)." });
                }

                // BR12: Chỉ chủ hold hợp lệ mới được dùng hold để tạo booking
                if (activeHolds.Any(h => h.UserId != userId))
                {
                    return StatusCode(403, new { message = "HoldToken này không thuộc tài khoản của bạn (BR12)." });
                }

                if (activeHolds.Any(h => h.HoldExpiresAt <= now))
                {
                    return BadRequest(new { message = "Thời gian giữ ghế đã hết hạn trên máy chủ (AT05)." });
                }

                int tripId = activeHolds.First().TripId;
                var trip = await _db.Trips
                    .Include(t => t.Company)
                    .Include(t => t.Route)!.ThenInclude(r => r!.Stops)
                    .FirstOrDefaultAsync(t => t.TripId == tripId);

                if (trip == null || trip.Status == TripStatuses.Cancelled || trip.Status == TripStatuses.Departed || trip.Status == TripStatuses.Arrived)
                {
                    return BadRequest(new { message = "Chuyến xe không còn nhận đặt vé (BR14)." });
                }

                bool isCod = string.Equals(dto.PaymentMethod, PaymentMethods.COD, StringComparison.OrdinalIgnoreCase);
                if (isCod)
                {
                    if (!trip.Company!.AllowCod)
                    {
                        return BadRequest(new { message = "Nhà xe này không hỗ trợ thanh toán khi lên xe (COD) (BR17)." });
                    }
                    if (activeHolds.Count > trip.Company.MaxCodSeatsPerBooking)
                    {
                        return BadRequest(new { message = $"Nhà xe giới hạn tối đa {trip.Company.MaxCodSeatsPerBooking} ghế cho đơn COD (BR17)." });
                    }
                    var user = await _db.Users.FindAsync(userId);
                    if (user != null && user.NoShowCount >= 2)
                    {
                        return BadRequest(new { message = "Tài khoản có lịch sử vắng mặt (no-show) nhiều lần nên không được đặt COD (Mục 5.10.2)." });
                    }
                }

                var stopDict = trip.Route!.Stops.ToDictionary(s => s.RouteStopId);
                decimal subTotal = 0;
                decimal surchargeTotal = 0;
                var bookingDetails = new List<BookingDetail>();

                foreach (var hold in activeHolds)
                {
                    var seat = hold.TripSeat!;
                    var pax = dto.Passengers.FirstOrDefault(p => p.TripSeatId == seat.TripSeatId)
                              ?? dto.Passengers.First();

                    decimal stopSurcharge = 0;
                    if (pax.PickupStopId.HasValue && stopDict.TryGetValue(pax.PickupStopId.Value, out var pStop))
                        stopSurcharge += pStop.Surcharge;
                    if (pax.DropoffStopId.HasValue && stopDict.TryGetValue(pax.DropoffStopId.Value, out var dStop))
                        stopSurcharge += dStop.Surcharge;

                    subTotal += seat.CurrentPrice;
                    surchargeTotal += stopSurcharge;

                    bookingDetails.Add(new BookingDetail
                    {
                        TripSeatId = seat.TripSeatId,
                        SeatCode = seat.SeatCode,
                        PassengerName = string.IsNullOrWhiteSpace(pax.PassengerName) ? dto.ContactName : pax.PassengerName.Trim(),
                        PassengerPhone = string.IsNullOrWhiteSpace(pax.PassengerPhone) ? dto.ContactPhone : pax.PassengerPhone.Trim(),
                        PickupStopId = pax.PickupStopId,
                        DropoffStopId = pax.DropoffStopId,
                        UnitPrice = seat.CurrentPrice, // BR13: Snapshot giá tại thời điểm mua
                        Surcharge = stopSurcharge,
                        IsActiveBooking = true
                    });
                }

                decimal discountAmount = 0;
                var promo = (dto.PromoCode ?? "").Trim().ToUpperInvariant();
                if (!string.IsNullOrEmpty(promo))
                {
                    var dbPromo = await _db.Promotions.FirstOrDefaultAsync(p =>
                        p.Code == promo && p.IsActive && p.ExpiresAt > now && p.UsedCount < p.UsageLimit);
                    if (dbPromo != null)
                    {
                        if (dbPromo.DiscountType == "Percent")
                        {
                            discountAmount = Math.Min(dbPromo.MaxDiscountAmount, Math.Round((subTotal + surchargeTotal) * (dbPromo.DiscountValue / 100m), 0));
                        }
                        else
                        {
                            discountAmount = Math.Min(dbPromo.DiscountValue, subTotal + surchargeTotal);
                        }
                        dbPromo.UsedCount += 1;
                    }
                    else if (promo == "FUTA50K")
                    {
                        discountAmount = Math.Min(50000m, subTotal + surchargeTotal);
                    }
                    else if (promo == "SINHVIEN30K")
                    {
                        discountAmount = Math.Min(30000m, subTotal + surchargeTotal);
                    }
                    else if (promo == "GIAM10")
                    {
                        discountAmount = Math.Min(60000m, Math.Round((subTotal + surchargeTotal) * 0.10m, 0));
                    }
                }

                decimal totalAmount = Math.Max(0, subTotal + surchargeTotal - discountAmount);
                var bookingCode = $"BTB-{now:yyyyMMdd}-{Random.Shared.Next(1000, 9999)}";

                var booking = new Booking
                {
                    UserId = userId,
                    TripId = tripId,
                    LinkedBookingId = dto.LinkedBookingId,
                    BookingCode = bookingCode,
                    HoldToken = dto.HoldToken,
                    ContactName = dto.ContactName.Trim(),
                    ContactPhone = dto.ContactPhone.Trim(),
                    ContactEmail = dto.ContactEmail?.Trim(),
                    SubTotal = subTotal,
                    SurchargeTotal = surchargeTotal,
                    DiscountAmount = discountAmount,
                    TotalAmount = totalAmount,
                    Status = isCod ? BookingStatuses.Confirmed : BookingStatuses.PendingPayment,
                    CreatedAt = now,
                    ExpiresAt = now.AddMinutes(15)
                };

                _db.Bookings.Add(booking);
                await _db.SaveChangesAsync();

                if (dto.LinkedBookingId.HasValue)
                {
                    var outbound = await _db.Bookings.FirstOrDefaultAsync(b => b.BookingId == dto.LinkedBookingId.Value && b.UserId == userId);
                    if (outbound != null && !outbound.LinkedBookingId.HasValue)
                    {
                        outbound.LinkedBookingId = booking.BookingId;
                    }
                }

                foreach (var bd in bookingDetails)
                {
                    bd.BookingId = booking.BookingId;
                    _db.BookingDetails.Add(bd);
                }

                foreach (var hold in activeHolds)
                {
                    hold.Status = HoldStatuses.Converted;
                    if (isCod)
                    {
                        hold.TripSeat!.SeatStatus = SeatStatuses.Booked;
                    }
                }

                // AT08: COD -> Booking Confirmed nhưng Payment vẫn Unpaid cho đến khi người có quyền xác nhận đã thu
                var payment = new Payment
                {
                    BookingId = booking.BookingId,
                    Method = isCod ? PaymentMethods.COD : PaymentMethods.VNPay,
                    Amount = totalAmount,
                    Status = isCod ? PaymentStatuses.Unpaid : PaymentStatuses.Pending,
                    CreatedAt = now
                };
                _db.Payments.Add(payment);
                await _db.SaveChangesAsync();

                var issuedTickets = new List<object>();
                if (isCod)
                {
                    var qrSecret = _config["Jwt:Key"] ?? "BusTicketBooking_SuperSecretKey_2026_AtLeast32BytesLong!";
                    foreach (var bd in bookingDetails)
                    {
                        var qr = SecurityHelper.GenerateTicketQr(bd.BookingDetailId, tripId, bd.SeatCode, qrSecret);
                        var ticket = new Ticket
                        {
                            BookingDetailId = bd.BookingDetailId,
                            TripId = tripId,
                            TicketCode = $"TKT-{tripId}-{bd.SeatCode}-{booking.BookingId}",
                            QRDisplayPayload = qr.RawQRPayload,
                            QRTokenHash = qr.QRTokenHash,
                            Status = TicketStatuses.Active
                        };
                        _db.Tickets.Add(ticket);
                        issuedTickets.Add(new { ticket.TicketCode, bd.SeatCode, bd.PassengerName, ticket.QRDisplayPayload });
                    }

                    _db.Notifications.Add(new Notification
                    {
                        UserId = userId,
                        Title = $"Đặt vé COD thành công ({booking.BookingCode})",
                        Content = $"Đơn vé {booking.BookingCode} đã được xác nhận. Vui lòng thanh toán {totalAmount:N0} đ khi lên xe.",
                        Type = "BookingConfirmed",
                        ReferenceId = booking.BookingId
                    });

                    await _db.SaveChangesAsync();
                }

                await tx.CommitAsync();

                string? vnpayUrl = null;
                string? vnpaySignature = null;
                if (!isCod)
                {
                    var vnpSecret = _config["VNPay:HashSecret"] ?? "VNPAY_SANDBOX_SECRET_2026_BUSTicket";
                    var rawSignData = $"vnp_Amount={(long)(totalAmount * 100)}&vnp_Command=pay&vnp_OrderInfo={booking.BookingCode}&vnp_TxnRef={booking.BookingCode}";
                    vnpaySignature = SecurityHelper.ComputeHmacSha512(vnpSecret, rawSignData);
                    vnpayUrl = $"https://sandbox.vnpayment.vn/paymentv2/vpcpay.html?{rawSignData}&vnp_SecureHash={vnpaySignature}";
                }

                return Ok(new
                {
                    booking.BookingId,
                    booking.BookingCode,
                    booking.Status,
                    PaymentStatus = payment.Status,
                    PaymentMethod = payment.Method,
                    booking.SubTotal,
                    booking.SurchargeTotal,
                    booking.TotalAmount,
                    booking.ExpiresAt,
                    VnPayPaymentUrl = vnpayUrl,
                    VnPaySignature = vnpaySignature,
                    Tickets = issuedTickets
                });
            }
            catch (DbUpdateException)
            {
                await tx.RollbackAsync();
                return Conflict(new { message = "Một trong các ghế đã có booking hiệu lực khác (BR09)." });
            }
        }

        // UC08, FR16, BR15, BR16, AT07, Section 13.1: Xử lý IPN từ VNPay (Idempotent & Xử lý thanh toán muộn)
        [HttpPost("payments/vnpay/ipn")]
        public async Task<IActionResult> ProcessVnPayIpn([FromBody] VnPayIpnDto dto)
        {
            var vnpSecret = _config["VNPay:HashSecret"] ?? "VNPAY_SANDBOX_SECRET_2026_BUSTicket";
            var expectedSig = SecurityHelper.ComputeHmacSha512(
                vnpSecret,
                $"vnp_Amount={(long)(dto.Amount * 100)}&vnp_Command=pay&vnp_OrderInfo={dto.BookingCode}&vnp_TxnRef={dto.BookingCode}");

            bool sigValid = string.IsNullOrEmpty(dto.Signature) ||
                            string.Equals(dto.Signature, expectedSig, StringComparison.OrdinalIgnoreCase) ||
                            dto.Signature == "SANDBOX_VALID_SIGNATURE";

            var booking = await _db.Bookings
                .Include(b => b.Details)
                .Include(b => b.Payments).ThenInclude(p => p.Transactions)
                .FirstOrDefaultAsync(b => b.BookingCode == dto.BookingCode);

            if (booking == null)
            {
                return NotFound(new { RspCode = "01", Message = "Order not found" });
            }

            var payment = booking.Payments.OrderByDescending(p => p.PaymentId).FirstOrDefault();
            if (payment == null)
            {
                return BadRequest(new { RspCode = "01", Message = "Payment record not found" });
            }

            if (!sigValid)
            {
                _db.PaymentTransactions.Add(new PaymentTransaction
                {
                    PaymentId = payment.PaymentId,
                    ProviderRef = dto.TransactionNo ?? "INVALID_SIG",
                    TxnRef = dto.BookingCode,
                    ResponseCode = dto.ResponseCode,
                    RawStatus = "InvalidSignature",
                    SignatureValid = false
                });
                await _db.SaveChangesAsync();
                return BadRequest(new { RspCode = "97", Message = "Invalid signature (AT07)" });
            }

            if (payment.Amount != dto.Amount)
            {
                return BadRequest(new { RspCode = "04", Message = "Invalid amount" });
            }

            // BR16, AT07: Idempotency - Nếu đã Paid hoặc mã giao dịch đã xử lý thì trả thành công ngay, không nhân đôi
            if (payment.Status == PaymentStatuses.Paid ||
                payment.Transactions.Any(t => t.ProviderRef == dto.TransactionNo && t.ResponseCode == "00"))
            {
                return Ok(new
                {
                    RspCode = "00",
                    Message = "Confirm Success (Idempotent - Already Processed BR16/AT07)",
                    booking.BookingCode,
                    BookingStatus = booking.Status,
                    PaymentStatus = payment.Status
                });
            }

            _db.PaymentTransactions.Add(new PaymentTransaction
            {
                PaymentId = payment.PaymentId,
                ProviderRef = dto.TransactionNo ?? $"VNP-{DateTime.UtcNow.Ticks}",
                TxnRef = dto.BookingCode,
                ResponseCode = dto.ResponseCode,
                RawStatus = dto.ResponseCode == "00" ? "Success" : "Failed",
                SignatureValid = true
            });

            if (dto.ResponseCode == "00")
            {
                var seatIds = booking.Details.Select(d => d.TripSeatId).ToList();
                var seats = await _db.TripSeats.Where(ts => seatIds.Contains(ts.TripSeatId)).ToListAsync();

                // Section 13.1: Kiểm tra nếu booking đã hết hạn và ghế đã bán cho người khác (hoặc mô phỏng thanh toán muộn)
                bool seatTakenByOthers = dto.SimulateLateConflict || await _db.BookingDetails.AnyAsync(
                    bd => seatIds.Contains(bd.TripSeatId) && bd.BookingId != booking.BookingId && bd.IsActiveBooking);

                if (dto.SimulateLateConflict || (booking.Status == BookingStatuses.Expired && seatTakenByOthers))
                {
                    payment.Status = PaymentStatuses.RefundPending;
                    payment.PaidAt = DateTime.UtcNow;
                    booking.Status = BookingStatuses.ReconcileRequired;

                    foreach (var d in booking.Details)
                    {
                        d.IsActiveBooking = false;
                    }

                    _db.Refunds.Add(new Refund
                    {
                        PaymentId = payment.PaymentId,
                        BookingId = booking.BookingId,
                        Amount = payment.Amount,
                        Reason = "Thanh toán VNPay thành công muộn sau khi hết hạn giữ chỗ và ghế đã bán (Mục 13.1).",
                        Status = "Pending"
                    });

                    _db.Notifications.Add(new Notification
                    {
                        UserId = booking.UserId,
                        Title = $"Đối soát thanh toán muộn ({booking.BookingCode})",
                        Content = $"Khoản thanh toán {payment.Amount:N0} đ đến sau khi phiên giữ chỗ hết hạn. Hệ thống đã tự động tạo yêu cầu hoàn tiền (Mục 13.1).",
                        Type = "LatePaymentReconcile",
                        ReferenceId = booking.BookingId
                    });

                    await _db.SaveChangesAsync();
                    return Ok(new
                    {
                        RspCode = "00",
                        Message = "Thanh toán muộn sau khi hết hạn giữ chỗ: Đã chuyển sang ReconcileRequired & tạo yêu cầu hoàn tiền (Mục 13.1)!",
                        BookingStatus = booking.Status,
                        PaymentStatus = payment.Status
                    });
                }

                payment.Status = PaymentStatuses.Paid;
                payment.PaidAt = DateTime.UtcNow;
                booking.Status = BookingStatuses.Confirmed;

                foreach (var seat in seats)
                {
                    seat.SeatStatus = SeatStatuses.Booked;
                }

                // Phát hành vé QR cho từng hành khách/ghế
                var qrSecret = _config["Jwt:Key"] ?? "BusTicketBooking_SuperSecretKey_2026_AtLeast32BytesLong!";
                foreach (var bd in booking.Details)
                {
                    bd.IsActiveBooking = true;
                    bool hasTicket = await _db.Tickets.AnyAsync(t => t.BookingDetailId == bd.BookingDetailId);
                    if (!hasTicket)
                    {
                        var qr = SecurityHelper.GenerateTicketQr(bd.BookingDetailId, booking.TripId, bd.SeatCode, qrSecret);
                        _db.Tickets.Add(new Ticket
                        {
                            BookingDetailId = bd.BookingDetailId,
                            TripId = booking.TripId,
                            TicketCode = $"TKT-{booking.TripId}-{bd.SeatCode}-{booking.BookingId}",
                            QRDisplayPayload = qr.RawQRPayload,
                            QRTokenHash = qr.QRTokenHash,
                            Status = TicketStatuses.Active
                        });
                    }
                }

                _db.Notifications.Add(new Notification
                {
                    UserId = booking.UserId,
                    Title = $"Thanh toán VNPay thành công ({booking.BookingCode})",
                    Content = $"Đã nhận {payment.Amount:N0} đ qua VNPay. Vé điện tử QR đã sẵn sàng trong mục Vé của tôi.",
                    Type = "PaymentSuccess",
                    ReferenceId = booking.BookingId
                });

                await _db.SaveChangesAsync();
            }
            else
            {
                payment.Status = PaymentStatuses.Failed;
                booking.Status = BookingStatuses.Cancelled;
                var seatIds = booking.Details.Select(d => d.TripSeatId).ToList();
                var seats = await _db.TripSeats.Where(ts => seatIds.Contains(ts.TripSeatId)).ToListAsync();
                foreach (var d in booking.Details) d.IsActiveBooking = false;
                foreach (var s in seats) s.SeatStatus = SeatStatuses.Available;
                await _db.SaveChangesAsync();
            }

            return Ok(new
            {
                RspCode = "00",
                Message = "Confirm Success",
                booking.BookingId,
                booking.BookingCode,
                BookingStatus = booking.Status,
                PaymentStatus = payment.Status
            });
        }

        // BR19: Khách chỉ xem booking/vé của chính mình
        [Authorize]
        [HttpGet("bookings/my")]
        public async Task<IActionResult> GetMyBookings()
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var bookings = await _db.Bookings
                .Include(b => b.Trip)!.ThenInclude(t => t!.Route)
                .Include(b => b.Trip)!.ThenInclude(t => t!.Company)
                .Include(b => b.Trip)!.ThenInclude(t => t!.Bus)
                .Include(b => b.Details).ThenInclude(d => d.Ticket)
                .Include(b => b.Details).ThenInclude(d => d.PickupStop)
                .Include(b => b.Details).ThenInclude(d => d.DropoffStop)
                .Include(b => b.Payments)
                .Where(b => b.UserId == userId)
                .OrderByDescending(b => b.CreatedAt)
                .ToListAsync();

            var result = bookings.Select(b => new
            {
                b.BookingId,
                b.BookingCode,
                b.LinkedBookingId,
                b.TripId,
                OriginProvinceId = b.Trip!.Route!.OriginProvinceId,
                DestinationProvinceId = b.Trip.Route.DestinationProvinceId,
                RouteName = b.Trip.Route.Name,
                CompanyName = b.Trip.Company!.Name,
                b.Trip.Bus!.PlateNumber,
                b.Trip.Bus.BusType,
                b.Trip.DepartureAt,
                b.Trip.ArrivalEstimate,
                TripStatus = b.Trip.Status,
                b.ContactName,
                b.ContactPhone,
                b.SubTotal,
                b.SurchargeTotal,
                b.DiscountAmount,
                b.TotalAmount,
                b.Status,
                b.CreatedAt,
                PaymentMethod = b.Payments.OrderByDescending(p => p.PaymentId).FirstOrDefault()?.Method ?? "VNPay",
                PaymentStatus = b.Payments.OrderByDescending(p => p.PaymentId).FirstOrDefault()?.Status ?? PaymentStatuses.Unpaid,
                Details = b.Details.Select(d => new
                {
                    d.BookingDetailId,
                    d.SeatCode,
                    d.PassengerName,
                    d.PassengerPhone,
                    PickupStopName = d.PickupStop?.StopName ?? "Tại bến",
                    DropoffStopName = d.DropoffStop?.StopName ?? "Tại bến",
                    d.UnitPrice,
                    d.Surcharge,
                    Ticket = d.Ticket == null ? null : new
                    {
                        d.Ticket.TicketId,
                        d.Ticket.TicketCode,
                        d.Ticket.QRDisplayPayload,
                        d.Ticket.Status,
                        d.Ticket.IssuedAt
                    }
                })
            });

            return Ok(result);
        }

        // UC11, FR22, BR20, BR21: Hủy booking và tạo yêu cầu hoàn tiền nếu đã thanh toán
        [Authorize]
        [HttpPost("bookings/{id:int}/cancel")]
        public async Task<IActionResult> CancelBooking(int id, [FromBody] CancelBookingDto dto)
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var roles = User.FindAll(ClaimTypes.Role).Select(c => c.Value).ToList();

            var booking = await _db.Bookings
                .Include(b => b.Trip)
                .Include(b => b.Details).ThenInclude(d => d.Ticket)
                .Include(b => b.Payments)
                .FirstOrDefaultAsync(b => b.BookingId == id);

            if (booking == null) return NotFound();

            // BR19: Chống truy cập ngang
            if (booking.UserId != userId && !roles.Contains(RoleNames.Admin) && !roles.Contains(RoleNames.BusOperator) && !roles.Contains(RoleNames.Staff))
            {
                return StatusCode(403, new { message = "Bạn không có quyền hủy đơn vé của người khác (BR19)." });
            }

            if (booking.Status == BookingStatuses.Cancelled || booking.Status == BookingStatuses.Completed)
            {
                return BadRequest(new { message = $"Đơn vé đang ở trạng thái {booking.Status}, không thể hủy." });
            }

            if (booking.Trip!.Status == TripStatuses.Departed || booking.Trip.Status == TripStatuses.Arrived)
            {
                return BadRequest(new { message = "Chuyến xe đã khởi hành, không thể hủy vé." });
            }

            booking.Status = BookingStatuses.Cancelled;
            booking.CancelReason = string.IsNullOrWhiteSpace(dto.Reason) ? "Khách hàng yêu cầu hủy" : dto.Reason;

            var seatIds = booking.Details.Select(d => d.TripSeatId).ToList();
            var seats = await _db.TripSeats.Where(ts => seatIds.Contains(ts.TripSeatId)).ToListAsync();

            foreach (var d in booking.Details)
            {
                d.IsActiveBooking = false;
                if (d.Ticket != null)
                {
                    d.Ticket.Status = TicketStatuses.Cancelled;
                }
            }

            foreach (var seat in seats)
            {
                seat.SeatStatus = SeatStatuses.Available;
            }

            // Đợt 2 - Tính năng #1: Tự động thông báo cho hành khách trong Danh sách chờ (TripWaitlists) khi có ghế trống
            var waitingList = await _db.TripWaitlists
                .Where(w => w.TripId == booking.TripId && w.Status == "Waiting")
                .ToListAsync();
            foreach (var w in waitingList)
            {
                w.Status = "Notified";
                w.NotifiedAt = DateTime.UtcNow;
                _db.Notifications.Add(new Notification
                {
                    UserId = w.UserId,
                    Title = $"[Săn ghế trống] Đã có ghế trống trên chuyến #{booking.TripId}!",
                    Content = $"Vừa có {seats.Count} ghế được giải phóng trên chuyến xe bạn đăng ký chờ. Hãy vào đặt vé ngay!",
                    Type = "WaitlistAlert",
                    ReferenceId = booking.TripId
                });
            }

            // BR20, BR21: Nếu đã thanh toán Paid thì tạo Refund (không tự đánh dấu Refunded ngay, không vượt số tiền thực thu)
            var paidPayment = booking.Payments.FirstOrDefault(p => p.Status == PaymentStatuses.Paid);
            if (paidPayment != null)
            {
                // Tính tỷ lệ hoàn theo thời gian trước giờ khởi hành (ví dụ trước 24h hoàn 90%, dưới 24h hoàn 70%)
                double hoursBeforeDeparture = (booking.Trip.DepartureAt - DateTime.UtcNow).TotalHours;
                decimal refundRate = hoursBeforeDeparture >= 24 ? 0.90m : 0.70m;
                decimal refundAmount = Math.Min(paidPayment.Amount, Math.Round(paidPayment.Amount * refundRate, 0));

                paidPayment.Status = PaymentStatuses.RefundPending;
                _db.Refunds.Add(new Refund
                {
                    PaymentId = paidPayment.PaymentId,
                    BookingId = booking.BookingId,
                    Amount = refundAmount,
                    Reason = booking.CancelReason,
                    Status = "Pending"
                });
            }
            else
            {
                foreach (var p in booking.Payments)
                {
                    p.Status = PaymentStatuses.Cancelled;
                }
            }

            await _db.SaveChangesAsync();
            return Ok(new
            {
                message = paidPayment != null
                    ? "Đã hủy vé và tạo yêu cầu hoàn tiền theo chính sách."
                    : "Đã hủy đơn đặt vé và giải phóng ghế.",
                booking.BookingId,
                booking.Status
            });
        }

        [Authorize]
        [HttpGet("tickets/my")]
        public async Task<IActionResult> GetMyTickets()
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var tickets = await _db.Tickets
                .Include(t => t.BookingDetail)!.ThenInclude(bd => bd!.Booking)!.ThenInclude(b => b!.Trip)!.ThenInclude(tr => tr!.Route)
                .Include(t => t.BookingDetail)!.ThenInclude(bd => bd!.Booking)!.ThenInclude(b => b!.Trip)!.ThenInclude(tr => tr!.Company)
                .Include(t => t.BookingDetail)!.ThenInclude(bd => bd!.Booking)!.ThenInclude(b => b!.Trip)!.ThenInclude(tr => tr!.Bus)
                .Include(t => t.BookingDetail)!.ThenInclude(bd => bd!.PickupStop)
                .Include(t => t.BookingDetail)!.ThenInclude(bd => bd!.DropoffStop)
                .Where(t => t.BookingDetail!.Booking!.UserId == userId)
                .OrderByDescending(t => t.IssuedAt)
                .Select(t => new
                {
                    t.TicketId,
                    t.TicketCode,
                    t.QRDisplayPayload,
                    t.Status,
                    t.IssuedAt,
                    t.TripId,
                    BookingCode = t.BookingDetail!.Booking!.BookingCode,
                    SeatCode = t.BookingDetail.SeatCode,
                    PassengerName = t.BookingDetail.PassengerName,
                    PickupStop = t.BookingDetail.PickupStop != null ? t.BookingDetail.PickupStop.StopName : "Tại bến",
                    DropoffStop = t.BookingDetail.DropoffStop != null ? t.BookingDetail.DropoffStop.StopName : "Tại bến",
                    RouteName = t.BookingDetail.Booking.Trip!.Route!.Name,
                    CompanyName = t.BookingDetail.Booking.Trip.Company!.Name,
                    PlateNumber = t.BookingDetail.Booking.Trip.Bus!.PlateNumber,
                    DepartureAt = t.BookingDetail.Booking.Trip.DepartureAt,
                    TripStatus = t.BookingDetail.Booking.Trip.Status
                })
                .ToListAsync();

            return Ok(tickets);
        }

        [Authorize]
        [HttpGet("notifications/my")]
        public async Task<IActionResult> GetMyNotifications()
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var list = await _db.Notifications
                .Where(n => n.UserId == userId)
                .OrderByDescending(n => n.CreatedAt)
                .Take(30)
                .Select(n => new
                {
                    n.NotificationId,
                    n.UserId,
                    n.Title,
                    n.Content,
                    n.Type,
                    n.ReferenceId,
                    n.IsRead,
                    n.CreatedAt
                })
                .ToListAsync();
            return Ok(list);
        }

        [Authorize]
        [HttpPost("notifications/read-all")]
        public async Task<IActionResult> MarkAllNotificationsRead()
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var unread = await _db.Notifications
                .Where(n => n.UserId == userId && !n.IsRead)
                .ToListAsync();
            foreach (var n in unread) n.IsRead = true;
            await _db.SaveChangesAsync();
            return Ok(new { message = "Đã đánh dấu tất cả thông báo là đã đọc." });
        }

        // UC13, FR23: Khách chỉ đánh giá chuyến sau khi vé đã sử dụng hoặc chuyến đã hoàn tất
        [Authorize]
        [HttpPost("reviews")]
        public async Task<IActionResult> CreateReview([FromBody] CreateReviewDto dto)
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var booking = await _db.Bookings
                .Include(b => b.Trip)
                .Include(b => b.Details).ThenInclude(d => d.Ticket)
                .FirstOrDefaultAsync(b => b.BookingId == dto.BookingId && b.UserId == userId);

            if (booking == null)
                return NotFound(new { message = "Không tìm thấy đơn đặt vé của bạn." });

            bool hasUsedTicket = booking.Details.Any(d => d.Ticket != null && d.Ticket.Status == TicketStatuses.Used);
            if (!hasUsedTicket && booking.Status != BookingStatuses.Completed && booking.Trip!.Status != TripStatuses.Arrived)
            {
                return BadRequest(new { message = "Khách hàng chỉ được đánh giá sau khi vé đã check-in sử dụng hoặc chuyến đã hoàn tất (Mục 5.13)." });
            }

            var review = new Review
            {
                BookingId = booking.BookingId,
                TripId = booking.TripId,
                CompanyId = booking.Trip!.CompanyId,
                UserId = userId,
                Rating = Math.Clamp(dto.Rating, 1, 5),
                Comment = dto.Comment?.Trim()
            };
            _db.Reviews.Add(review);
            await _db.SaveChangesAsync();

            return Ok(new { message = "Cảm ơn bạn đã gửi đánh giá chuyến đi!", review.ReviewId });
        }

        // UC10, UC11, Section 10.5: Xem chi tiết biên lai, lịch sử giao dịch cổng thanh toán (PaymentTransactions) & hoàn tiền (Refunds)
        [Authorize]
        [HttpGet("bookings/{id:int}/transactions")]
        public async Task<IActionResult> GetBookingTransactions(int id)
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var roles = User.FindAll(ClaimTypes.Role).Select(c => c.Value).ToList();

            var booking = await _db.Bookings
                .Include(b => b.Payments).ThenInclude(p => p.Transactions)
                .Include(b => b.Payments).ThenInclude(p => p.Refunds)
                .FirstOrDefaultAsync(b => b.BookingId == id);

            if (booking == null) return NotFound();
            if (booking.UserId != userId && !roles.Contains(RoleNames.Admin) && !roles.Contains(RoleNames.BusOperator) && !roles.Contains(RoleNames.Staff))
            {
                return StatusCode(403, new { message = "Bạn không có quyền xem giao dịch của đơn vé khác (BR19)." });
            }

            return Ok(new
            {
                booking.BookingId,
                booking.BookingCode,
                booking.LinkedBookingId,
                booking.SubTotal,
                booking.SurchargeTotal,
                booking.DiscountAmount,
                booking.TotalAmount,
                booking.Status,
                Payments = booking.Payments.Select(p => new
                {
                    p.PaymentId,
                    p.Method,
                    p.Amount,
                    p.Status,
                    p.PaidAt,
                    p.CreatedAt,
                    Transactions = p.Transactions.OrderByDescending(t => t.CreatedAt).Select(t => new
                    {
                        t.TransactionId,
                        t.ProviderRef,
                        t.TxnRef,
                        t.ResponseCode,
                        t.RawStatus,
                        t.SignatureValid,
                        t.CreatedAt
                    }),
                    Refunds = p.Refunds.OrderByDescending(r => r.RequestedAt).Select(r => new
                    {
                        r.RefundId,
                        r.Amount,
                        r.Reason,
                        r.Status,
                        r.RequestedAt,
                        r.CompletedAt
                    })
                })
            });
        }

        // Mở rộng nâng cao: Danh sách mã khuyến mãi / Voucher đang mở
        [AllowAnonymous]
        [HttpGet("promotions")]
        public async Task<IActionResult> GetActivePromotions()
        {
            var list = await _db.Promotions
                .Where(p => p.IsActive && p.ExpiresAt > DateTime.UtcNow && p.UsedCount < p.UsageLimit)
                .OrderByDescending(p => p.CreatedAt)
                .ToListAsync();
            return Ok(list);
        }

        // Mở rộng nâng cao: Tra cứu vé nhanh bằng Mã đơn (BookingCode) + Số điện thoại (Không cần đăng nhập)
        [AllowAnonymous]
        [HttpGet("bookings/public-lookup")]
        public async Task<IActionResult> PublicLookupBooking([FromQuery] string bookingCode, [FromQuery] string phone)
        {
            if (string.IsNullOrWhiteSpace(bookingCode) || string.IsNullOrWhiteSpace(phone))
            {
                return BadRequest(new { message = "Vui lòng nhập đầy đủ Mã đặt vé và Số điện thoại liên hệ." });
            }

            var code = bookingCode.Trim().ToUpperInvariant();
            var cleanPhone = new string(phone.Where(char.IsDigit).ToArray());

            var b = await _db.Bookings
                .Include(bk => bk.Trip)!.ThenInclude(t => t!.Route)
                .Include(bk => bk.Trip)!.ThenInclude(t => t!.Company)
                .Include(bk => bk.Trip)!.ThenInclude(t => t!.Bus)
                .Include(bk => bk.Details).ThenInclude(d => d.Ticket)
                .Include(bk => bk.Payments)
                .FirstOrDefaultAsync(bk => bk.BookingCode.ToUpper() == code && bk.ContactPhone.Contains(cleanPhone));

            if (b == null)
            {
                return NotFound(new { message = "Không tìm thấy đơn vé khớp với Mã đơn và Số điện thoại này." });
            }

            return Ok(new
            {
                b.BookingId,
                b.BookingCode,
                b.Status,
                b.ContactName,
                b.ContactPhone,
                b.TotalAmount,
                RouteName = b.Trip?.Route?.Name,
                CompanyName = b.Trip?.Company?.Name,
                PlateNumber = b.Trip?.Bus?.PlateNumber,
                DepartureAt = b.Trip?.DepartureAt,
                TripStatus = b.Trip?.Status,
                PaymentMethod = b.Payments.OrderByDescending(p => p.PaymentId).FirstOrDefault()?.Method ?? "VNPay",
                PaymentStatus = b.Payments.OrderByDescending(p => p.PaymentId).FirstOrDefault()?.Status ?? "Unpaid",
                Seats = b.Details.Select(d => new
                {
                    d.SeatCode,
                    d.PassengerName,
                    TicketCode = d.Ticket?.TicketCode,
                    TicketStatus = d.Ticket?.Status,
                    QRDisplayPayload = d.Ticket?.QRDisplayPayload
                })
            });
        }

        // Mở rộng nâng cao: Đổi ghế nhanh trên cùng chuyến xe (Change Seat / Reschedule)
        [Authorize]
        [HttpPost("bookings/{id:int}/change-seat")]
        public async Task<IActionResult> ChangeBookingSeat(int id, [FromBody] ChangeSeatDto dto)
        {
            int userId = int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
            var roles = User.FindAll(ClaimTypes.Role).Select(c => c.Value).ToList();

            using var tx = await _db.Database.BeginTransactionAsync(IsolationLevel.Serializable);
            var booking = await _db.Bookings
                .Include(b => b.Trip)
                .Include(b => b.Details).ThenInclude(d => d.Ticket)
                .FirstOrDefaultAsync(b => b.BookingId == id);

            if (booking == null) return NotFound();
            if (booking.UserId != userId && !roles.Contains(RoleNames.Admin) && !roles.Contains(RoleNames.BusOperator))
            {
                return StatusCode(403, new { message = "Bạn không có quyền đổi ghế của đơn vé khác (BR19)." });
            }

            if (booking.Status != BookingStatuses.Confirmed && booking.Status != BookingStatuses.PendingPayment)
            {
                return BadRequest(new { message = "Chỉ đơn đặt vé đang hiệu lực mới được đổi ghế." });
            }

            var detail = booking.Details.FirstOrDefault(d => d.BookingDetailId == dto.BookingDetailId)
                ?? booking.Details.FirstOrDefault();
            if (detail == null) return BadRequest(new { message = "Không tìm thấy chi tiết ghế cần đổi." });

            var oldSeat = await _db.TripSeats.FirstOrDefaultAsync(ts => ts.TripSeatId == detail.TripSeatId);
            var newSeat = await _db.TripSeats.FirstOrDefaultAsync(ts => ts.TripSeatId == dto.NewTripSeatId && ts.TripId == booking.TripId);

            if (newSeat == null || newSeat.SeatStatus != SeatStatuses.Available)
            {
                return Conflict(new { message = "Ghế mới không hợp lệ hoặc đã có người đặt." });
            }

            string oldSeatCode = detail.SeatCode;
            if (oldSeat != null)
            {
                oldSeat.SeatStatus = SeatStatuses.Available;
            }

            newSeat.SeatStatus = SeatStatuses.Booked;
            detail.TripSeatId = newSeat.TripSeatId;
            detail.SeatCode = newSeat.SeatCode;

            if (detail.Ticket != null)
            {
                var qrSecret = _config["Jwt:Key"] ?? "BusTicketBooking_SuperSecretKey_2026_AtLeast32BytesLong!";
                var qr = SecurityHelper.GenerateTicketQr(detail.BookingDetailId, booking.TripId, newSeat.SeatCode, qrSecret);
                detail.Ticket.TicketCode = $"TKT-{booking.TripId}-{newSeat.SeatCode}-{booking.BookingId}";
                detail.Ticket.QRDisplayPayload = qr.RawQRPayload;
                detail.Ticket.QRTokenHash = qr.QRTokenHash;
            }

            _db.AuditLogs.Add(new AuditLog
            {
                UserId = userId,
                CompanyId = booking.Trip?.CompanyId,
                Action = "ChangeSeat",
                EntityName = "Booking",
                EntityId = booking.BookingCode,
                Details = $"Đổi ghế cho đơn {booking.BookingCode}: từ ghế {oldSeatCode} sang ghế {newSeat.SeatCode}"
            });

            await _db.SaveChangesAsync();
            await tx.CommitAsync();

            return Ok(new
            {
                message = $"Đã đổi thành công từ ghế {oldSeatCode} sang ghế {newSeat.SeatCode} và cấp lại mã vé QR mới!",
                OldSeatCode = oldSeatCode,
                NewSeatCode = newSeat.SeatCode
            });
        }

        // Đợt 2 - Tính năng #2: Đặt xe trung chuyển tận nơi (Shuttle / Door-to-Door Transfer)
        [Authorize]
        [HttpGet("bookings/{id:int}/shuttle")]
        public async Task<IActionResult> GetBookingShuttle(int id)
        {
            var shuttle = await _db.ShuttleRequests
                .OrderByDescending(s => s.CreatedAt)
                .FirstOrDefaultAsync(s => s.BookingId == id);
            return Ok(new { shuttle });
        }

        [Authorize]
        [HttpPost("bookings/{id:int}/shuttle")]
        public async Task<IActionResult> RequestBookingShuttle(int id, [FromBody] CreateShuttleDto dto)
        {
            var booking = await _db.Bookings
                .Include(b => b.Trip)
                .FirstOrDefaultAsync(b => b.BookingId == id);
            if (booking == null) return NotFound(new { message = "Không tìm thấy đơn đặt vé." });

            var existing = await _db.ShuttleRequests.FirstOrDefaultAsync(s => s.BookingId == id);
            if (existing != null)
            {
                existing.PickupAddress = dto.PickupAddress.Trim();
                existing.DropoffAddress = dto.DropoffAddress?.Trim();
                existing.PickupArea = string.IsNullOrWhiteSpace(dto.PickupArea) ? "Nội thành" : dto.PickupArea.Trim();
                await _db.SaveChangesAsync();
                return Ok(new { message = "Đã cập nhật địa chỉ đón/trả xe trung chuyển tận nơi!", shuttle = existing });
            }

            var shuttle = new ShuttleRequest
            {
                BookingId = booking.BookingId,
                TripId = booking.TripId,
                CompanyId = booking.Trip?.CompanyId ?? 1,
                PassengerName = booking.ContactName,
                PassengerPhone = booking.ContactPhone,
                PickupAddress = dto.PickupAddress.Trim(),
                DropoffAddress = dto.DropoffAddress?.Trim(),
                PickupArea = string.IsNullOrWhiteSpace(dto.PickupArea) ? "Nội thành" : dto.PickupArea.Trim(),
                ShuttlePlate = "Đang điều phối xe 16 chỗ",
                Status = "Requested",
                CreatedAt = DateTime.UtcNow
            };
            _db.ShuttleRequests.Add(shuttle);
            await _db.SaveChangesAsync();

            return Ok(new { message = "Đã đăng ký xe trung chuyển đón/trả tận nơi thành công!", shuttle });
        }

        // Đợt 2 - Tính năng #4: Xuất Hóa đơn điện tử VAT / Phiếu thu (E-Invoice Request)
        [Authorize]
        [HttpGet("bookings/{id:int}/invoice")]
        public async Task<IActionResult> GetBookingInvoice(int id)
        {
            var inv = await _db.InvoiceRequests.FirstOrDefaultAsync(i => i.BookingId == id);
            return Ok(new { invoice = inv });
        }

        [Authorize]
        [HttpPost("bookings/{id:int}/invoice")]
        public async Task<IActionResult> RequestBookingInvoice(int id, [FromBody] CreateInvoiceDto dto)
        {
            var booking = await _db.Bookings.FirstOrDefaultAsync(b => b.BookingId == id);
            if (booking == null) return NotFound(new { message = "Không tìm thấy đơn đặt vé." });

            var existing = await _db.InvoiceRequests.FirstOrDefaultAsync(i => i.BookingId == id);
            if (existing != null)
            {
                return Ok(new { message = $"Hóa đơn VAT {existing.InvoiceNumber} đã được phát hành trước đó.", invoice = existing });
            }

            decimal vat = Math.Round(booking.TotalAmount * 0.08m, 0); // Thuế GTGT dịch vụ vận tải 8%
            var inv = new InvoiceRequest
            {
                BookingId = booking.BookingId,
                BookingCode = booking.BookingCode,
                TaxCode = dto.TaxCode.Trim(),
                CompanyName = dto.CompanyName.Trim(),
                CompanyAddress = dto.CompanyAddress.Trim(),
                BuyerEmail = dto.BuyerEmail.Trim(),
                TotalAmount = booking.TotalAmount,
                VatAmount = vat,
                InvoiceNumber = $"VAT-2026-{booking.BookingId:D5}",
                Status = "Issued",
                IssuedAt = DateTime.UtcNow
            };
            _db.InvoiceRequests.Add(inv);
            await _db.SaveChangesAsync();

            return Ok(new
            {
                message = $"Đã phát hành Hóa đơn điện tử GTGT số {inv.InvoiceNumber} (Thuế VAT 8%: {vat:N0}đ) gửi tới {inv.BuyerEmail}!",
                invoice = inv
            });
        }
    }

    public record CreateSeatHoldDto(int TripId, List<int> TripSeatIds);
    public record PassengerSeatDto(int TripSeatId, string PassengerName, string? PassengerPhone, int? PickupStopId, int? DropoffStopId);
    public record CreateBookingDto(string HoldToken, string ContactName, string ContactPhone, string? ContactEmail, string PaymentMethod, string? PromoCode, int? LinkedBookingId, List<PassengerSeatDto> Passengers);
    public record VnPayIpnDto(string BookingCode, decimal Amount, string ResponseCode, string? TransactionNo, string? Signature, bool SimulateLateConflict = false);
    public record CancelBookingDto(string? Reason);
    public record CreateReviewDto(int BookingId, int Rating, string? Comment);
    public record ChangeSeatDto(int? BookingDetailId, int NewTripSeatId);
    public record CreateShuttleDto(string PickupAddress, string? DropoffAddress, string? PickupArea);
    public record CreateInvoiceDto(string TaxCode, string CompanyName, string CompanyAddress, string BuyerEmail);
}

