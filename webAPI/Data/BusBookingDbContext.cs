using Microsoft.EntityFrameworkCore;
using webAPI.Models;

namespace webAPI.Data
{
    public class BusBookingDbContext : DbContext
    {
        public BusBookingDbContext(DbContextOptions<BusBookingDbContext> options) : base(options)
        {
        }

        // 10.1
        public DbSet<User> Users => Set<User>();
        public DbSet<Role> Roles => Set<Role>();
        public DbSet<UserRole> UserRoles => Set<UserRole>();
        public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
        public DbSet<UserDevice> UserDevices => Set<UserDevice>();

        // 10.2
        public DbSet<BusCompany> BusCompanies => Set<BusCompany>();
        public DbSet<CompanyMember> CompanyMembers => Set<CompanyMember>();
        public DbSet<Driver> Drivers => Set<Driver>();
        public DbSet<DriverDocument> DriverDocuments => Set<DriverDocument>();
        public DbSet<DriverAssignment> DriverAssignments => Set<DriverAssignment>();

        // 10.3
        public DbSet<Bus> Buses => Set<Bus>();
        public DbSet<BusSeat> BusSeats => Set<BusSeat>();
        public DbSet<BusMaintenance> BusMaintenances => Set<BusMaintenance>();

        // 10.4
        public DbSet<Province> Provinces => Set<Province>();
        public DbSet<Models.Route> Routes => Set<Models.Route>();
        public DbSet<RouteStop> RouteStops => Set<RouteStop>();
        public DbSet<Trip> Trips => Set<Trip>();
        public DbSet<TripSeat> TripSeats => Set<TripSeat>();
        public DbSet<TripStatusHistory> TripStatusHistories => Set<TripStatusHistory>();

        // 10.5
        public DbSet<SeatHold> SeatHolds => Set<SeatHold>();
        public DbSet<Booking> Bookings => Set<Booking>();
        public DbSet<BookingDetail> BookingDetails => Set<BookingDetail>();
        public DbSet<Payment> Payments => Set<Payment>();
        public DbSet<PaymentTransaction> PaymentTransactions => Set<PaymentTransaction>();
        public DbSet<Refund> Refunds => Set<Refund>();
        public DbSet<Ticket> Tickets => Set<Ticket>();
        public DbSet<TicketCheckIn> TicketCheckIns => Set<TicketCheckIn>();

        // 10.6
        public DbSet<TripLocation> TripLocations => Set<TripLocation>();
        public DbSet<TripLiveLocation> TripLiveLocations => Set<TripLiveLocation>();
        public DbSet<TripIncident> TripIncidents => Set<TripIncident>();
        public DbSet<Notification> Notifications => Set<Notification>();
        public DbSet<Review> Reviews => Set<Review>();
        public DbSet<SupportRequest> SupportRequests => Set<SupportRequest>();
        public DbSet<AuditLog> AuditLogs => Set<AuditLog>();
        public DbSet<Promotion> Promotions => Set<Promotion>();
        public DbSet<CargoShipment> CargoShipments => Set<CargoShipment>();
        public DbSet<TripWaitlist> TripWaitlists => Set<TripWaitlist>();
        public DbSet<ShuttleRequest> ShuttleRequests => Set<ShuttleRequest>();
        public DbSet<SavedCompanion> SavedCompanions => Set<SavedCompanion>();
        public DbSet<InvoiceRequest> InvoiceRequests => Set<InvoiceRequest>();
        public DbSet<TripExpense> TripExpenses => Set<TripExpense>();
        public DbSet<TripSafetyCheck> TripSafetyChecks => Set<TripSafetyCheck>();
        public DbSet<TripMessage> TripMessages => Set<TripMessage>();

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            // Prevent SQL Server multiple cascade paths by setting Restrict as default for foreign keys
            foreach (var relationship in modelBuilder.Model.GetEntityTypes().SelectMany(e => e.GetForeignKeys()))
            {
                relationship.DeleteBehavior = DeleteBehavior.Restrict;
            }

            // BR01: Email đăng ký phải duy nhất
            modelBuilder.Entity<User>()
                .HasIndex(u => u.Email)
                .IsUnique();

            modelBuilder.Entity<Role>()
                .HasIndex(r => r.RoleName)
                .IsUnique();

            // BR05: Biển số xe phải duy nhất toàn hệ thống
            modelBuilder.Entity<Bus>()
                .HasIndex(b => b.PlateNumber)
                .IsUnique();

            modelBuilder.Entity<BusSeat>()
                .HasIndex(bs => new { bs.BusId, bs.SeatCode })
                .IsUnique();

            modelBuilder.Entity<TripSeat>()
                .HasIndex(ts => new { ts.TripId, ts.SeatCode })
                .IsUnique();

            modelBuilder.Entity<Booking>()
                .HasIndex(b => b.BookingCode)
                .IsUnique();

            // BR09: Một TripSeat chỉ có tối đa một booking đang hiệu lực
            modelBuilder.Entity<BookingDetail>()
                .HasIndex(bd => bd.TripSeatId)
                .IsUnique()
                .HasFilter("[IsActiveBooking] = 1");

            modelBuilder.Entity<Ticket>()
                .HasIndex(t => t.TicketCode)
                .IsUnique();

            modelBuilder.Entity<Ticket>()
                .HasIndex(t => t.QRTokenHash)
                .IsUnique();

            modelBuilder.Entity<Ticket>()
                .HasOne(t => t.BookingDetail)
                .WithOne(bd => bd.Ticket)
                .HasForeignKey<Ticket>(t => t.BookingDetailId);

            modelBuilder.Entity<TripLiveLocation>()
                .HasOne(l => l.Trip)
                .WithOne()
                .HasForeignKey<TripLiveLocation>(l => l.TripId);

            // Indexes for performance (Section 9)
            modelBuilder.Entity<Trip>()
                .HasIndex(t => new { t.RouteId, t.DepartureAt, t.Status });

            modelBuilder.Entity<SeatHold>()
                .HasIndex(sh => new { sh.TripSeatId, sh.Status, sh.HoldExpiresAt });
        }
    }
}
