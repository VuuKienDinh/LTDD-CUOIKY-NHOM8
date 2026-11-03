using Microsoft.EntityFrameworkCore;
using webAPI.Data;
using webAPI.Models;

namespace webAPI.Services
{
    public class SeatHoldCleanupService : BackgroundService
    {
        private readonly IServiceProvider _serviceProvider;
        private readonly ILogger<SeatHoldCleanupService> _logger;

        public SeatHoldCleanupService(IServiceProvider serviceProvider, ILogger<SeatHoldCleanupService> logger)
        {
            _serviceProvider = serviceProvider;
            _logger = logger;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    await ReleaseExpiredHoldsAndBookingsAsync(stoppingToken);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error while cleaning up expired seat holds.");
                }

                await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);
            }
        }

        public static async Task<int> ReleaseExpiredHoldsInDbAsync(BusBookingDbContext db, CancellationToken ct = default)
        {
            var now = DateTime.UtcNow;
            int releasedCount = 0;

            // 1. Release expired active SeatHolds (AT05, BR10)
            var expiredHolds = await db.SeatHolds
                .Where(h => h.Status == HoldStatuses.Active && h.HoldExpiresAt <= now)
                .ToListAsync(ct);

            if (expiredHolds.Count > 0)
            {
                var seatIds = expiredHolds.Select(h => h.TripSeatId).Distinct().ToList();
                var seats = await db.TripSeats
                    .Where(ts => seatIds.Contains(ts.TripSeatId) && ts.SeatStatus == SeatStatuses.Held)
                    .ToListAsync(ct);

                foreach (var hold in expiredHolds)
                {
                    hold.Status = HoldStatuses.Expired;
                }

                foreach (var seat in seats)
                {
                    // Check if any other active hold or active booking exists for this seat
                    bool hasOtherActiveHold = await db.SeatHolds.AnyAsync(
                        h => h.TripSeatId == seat.TripSeatId && h.Status == HoldStatuses.Active && h.HoldExpiresAt > now, ct);
                    bool hasActiveBooking = await db.BookingDetails.AnyAsync(
                        bd => bd.TripSeatId == seat.TripSeatId && bd.IsActiveBooking, ct);

                    if (!hasOtherActiveHold && !hasActiveBooking)
                    {
                        seat.SeatStatus = SeatStatuses.Available;
                        releasedCount++;
                    }
                }
            }

            // 2. Expire PendingPayment Bookings past ExpiresAt
            var expiredBookings = await db.Bookings
                .Include(b => b.Details)
                .Include(b => b.Payments)
                .Where(b => b.Status == BookingStatuses.PendingPayment && b.ExpiresAt <= now)
                .ToListAsync(ct);

            foreach (var booking in expiredBookings)
            {
                booking.Status = BookingStatuses.Expired;
                foreach (var detail in booking.Details)
                {
                    detail.IsActiveBooking = false;
                    var tripSeat = await db.TripSeats.FindAsync(new object[] { detail.TripSeatId }, ct);
                    if (tripSeat != null && tripSeat.SeatStatus != SeatStatuses.Available)
                    {
                        tripSeat.SeatStatus = SeatStatuses.Available;
                        releasedCount++;
                    }
                }
                foreach (var payment in booking.Payments.Where(p => p.Status == PaymentStatuses.Pending))
                {
                    payment.Status = PaymentStatuses.Cancelled;
                }
            }

            if (expiredHolds.Count > 0 || expiredBookings.Count > 0)
            {
                await db.SaveChangesAsync(ct);
            }

            return releasedCount;
        }

        private async Task ReleaseExpiredHoldsAndBookingsAsync(CancellationToken ct)
        {
            using var scope = _serviceProvider.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<BusBookingDbContext>();
            await ReleaseExpiredHoldsInDbAsync(db, ct);
        }
    }
}

