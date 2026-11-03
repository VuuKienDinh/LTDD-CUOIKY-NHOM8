using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace webAPI.Models
{
    // 10.1. Tài khoản
    public class User
    {
        [Key]
        public int UserId { get; set; }
        [Required, MaxLength(120)]
        public string FullName { get; set; } = string.Empty;
        [Required, MaxLength(150)]
        public string Email { get; set; } = string.Empty;
        [Required, MaxLength(25)]
        public string Phone { get; set; } = string.Empty;
        [Required]
        public string PasswordHash { get; set; } = string.Empty;
        public bool IsActive { get; set; } = true;
        public int NoShowCount { get; set; } = 0;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public ICollection<UserRole> UserRoles { get; set; } = new List<UserRole>();
    }

    public class Role
    {
        [Key]
        public int RoleId { get; set; }
        [Required, MaxLength(50)]
        public string RoleName { get; set; } = string.Empty;
        [MaxLength(200)]
        public string? Description { get; set; }
    }

    public class UserRole
    {
        [Key]
        public int UserRoleId { get; set; }
        public int UserId { get; set; }
        public User? User { get; set; }
        public int RoleId { get; set; }
        public Role? Role { get; set; }
        public int? CompanyId { get; set; }
        public BusCompany? Company { get; set; }
    }

    public class RefreshToken
    {
        [Key]
        public int TokenId { get; set; }
        public int UserId { get; set; }
        public User? User { get; set; }
        [Required, MaxLength(256)]
        public string TokenHash { get; set; } = string.Empty;
        public DateTime ExpiresAt { get; set; }
        public DateTime? RevokedAt { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public class UserDevice
    {
        [Key]
        public int DeviceId { get; set; }
        public int UserId { get; set; }
        public User? User { get; set; }
        [Required, MaxLength(512)]
        public string FcmToken { get; set; } = string.Empty;
        [MaxLength(50)]
        public string DevicePlatform { get; set; } = "Android";
        public DateTime LastSeenAt { get; set; } = DateTime.UtcNow;
    }

    // 10.2. Nhà xe và nhân sự
    public class BusCompany
    {
        [Key]
        public int CompanyId { get; set; }
        [Required, MaxLength(150)]
        public string Name { get; set; } = string.Empty;
        [MaxLength(50)]
        public string TaxCode { get; set; } = string.Empty;
        [MaxLength(250)]
        public string Address { get; set; } = string.Empty;
        [MaxLength(30)]
        public string Phone { get; set; } = string.Empty;
        [MaxLength(150)]
        public string? Email { get; set; }
        [MaxLength(300)]
        public string? LogoUrl { get; set; }
        [MaxLength(1000)]
        public string? Description { get; set; }
        [MaxLength(120)]
        public string? RepresentativeName { get; set; }
        [Required, MaxLength(30)]
        public string Status { get; set; } = CompanyStatuses.Pending;
        [MaxLength(500)]
        public string? RejectionReason { get; set; }
        public bool AllowCod { get; set; } = true;
        public int MaxCodSeatsPerBooking { get; set; } = 4;
        public int SeatHoldMinutes { get; set; } = 10;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public class CompanyMember
    {
        [Key]
        public int CompanyMemberId { get; set; }
        public int CompanyId { get; set; }
        public BusCompany? Company { get; set; }
        public int UserId { get; set; }
        public User? User { get; set; }
        [Required, MaxLength(50)]
        public string MemberRole { get; set; } = RoleNames.Staff; // BusOperator or Staff
        [Required, MaxLength(30)]
        public string Status { get; set; } = "Active";
        public DateTime JoinedAt { get; set; } = DateTime.UtcNow;
    }

    public class Driver
    {
        [Key]
        public int DriverId { get; set; }
        public int CompanyId { get; set; }
        public BusCompany? Company { get; set; }
        public int? UserId { get; set; }
        public User? User { get; set; }
        [Required, MaxLength(120)]
        public string FullName { get; set; } = string.Empty;
        [Required, MaxLength(30)]
        public string Phone { get; set; } = string.Empty;
        [Required, MaxLength(50)]
        public string LicenseNumber { get; set; } = string.Empty;
        [Required, MaxLength(20)]
        public string LicenseClass { get; set; } = "E";
        public DateTime LicenseExpiry { get; set; }
        [Required, MaxLength(30)]
        public string Status { get; set; } = "Active";
    }

    public class DriverDocument
    {
        [Key]
        public int DocumentId { get; set; }
        public int DriverId { get; set; }
        public Driver? Driver { get; set; }
        [Required, MaxLength(400)]
        public string FileUrl { get; set; } = string.Empty;
        [Required, MaxLength(50)]
        public string Type { get; set; } = "DriverLicense";
        public DateTime ExpiryDate { get; set; }
        [Required, MaxLength(30)]
        public string Status { get; set; } = "Verified";
    }

    public class DriverAssignment
    {
        [Key]
        public int AssignmentId { get; set; }
        public int TripId { get; set; }
        public Trip? Trip { get; set; }
        public int DriverId { get; set; }
        public Driver? Driver { get; set; }
        [Required, MaxLength(30)]
        public string Role { get; set; } = "Primary"; // Primary, Assistant
        public DateTime AssignedAt { get; set; } = DateTime.UtcNow;
        public DateTime? ReleasedAt { get; set; }
        [MaxLength(300)]
        public string? ReplaceReason { get; set; }
    }

    // 10.3. Phương tiện
    public class Bus
    {
        [Key]
        public int BusId { get; set; }
        public int CompanyId { get; set; }
        public BusCompany? Company { get; set; }
        [Required, MaxLength(30)]
        public string PlateNumber { get; set; } = string.Empty;
        [Required, MaxLength(50)]
        public string BusType { get; set; } = "Giường nằm Limousine 34 chỗ";
        [MaxLength(100)]
        public string BrandModel { get; set; } = "Thaco Mobihome";
        public int TotalSeats { get; set; } = 34;
        public int ManufactureYear { get; set; } = 2024;
        public int TurnaroundMinutes { get; set; } = 60;
        [Required, MaxLength(30)]
        public string Status { get; set; } = BusStatuses.Active;

        public ICollection<BusSeat> Seats { get; set; } = new List<BusSeat>();
    }

    public class BusSeat
    {
        [Key]
        public int BusSeatId { get; set; }
        public int BusId { get; set; }
        public Bus? Bus { get; set; }
        [Required, MaxLength(20)]
        public string SeatCode { get; set; } = string.Empty;
        public int Deck { get; set; } = 1;
        public int Row { get; set; } = 1;
        public int Column { get; set; } = 1;
        [Required, MaxLength(30)]
        public string SeatType { get; set; } = "Standard"; // Standard, VIP, Cabin
        [Column(TypeName = "decimal(18,2)")]
        public decimal PriceSurcharge { get; set; } = 0;
        public bool IsActive { get; set; } = true;
    }

    public class BusMaintenance
    {
        [Key]
        public int MaintenanceId { get; set; }
        public int BusId { get; set; }
        public Bus? Bus { get; set; }
        public DateTime StartAt { get; set; }
        public DateTime EndAt { get; set; }
        [MaxLength(500)]
        public string Description { get; set; } = string.Empty;
        [Required, MaxLength(30)]
        public string Status { get; set; } = "Scheduled";
    }

    // 10.4. Tuyến và chuyến
    public class Province
    {
        [Key]
        public int ProvinceId { get; set; }
        [Required, MaxLength(100)]
        public string Name { get; set; } = string.Empty;
        [Required, MaxLength(20)]
        public string Code { get; set; } = string.Empty;
    }

    public class Route
    {
        [Key]
        public int RouteId { get; set; }
        public int CompanyId { get; set; }
        public BusCompany? Company { get; set; }
        public int OriginProvinceId { get; set; }
        public Province? OriginProvince { get; set; }
        public int DestinationProvinceId { get; set; }
        public Province? DestinationProvince { get; set; }
        [Required, MaxLength(180)]
        public string Name { get; set; } = string.Empty;
        public int DistanceKm { get; set; } = 300;
        public int EstimatedDurationMinutes { get; set; } = 360;
        public bool IsActive { get; set; } = true;

        public ICollection<RouteStop> Stops { get; set; } = new List<RouteStop>();
    }

    public class RouteStop
    {
        [Key]
        public int RouteStopId { get; set; }
        public int RouteId { get; set; }
        public Route? Route { get; set; }
        [Required, MaxLength(150)]
        public string StopName { get; set; } = string.Empty;
        [MaxLength(250)]
        public string Address { get; set; } = string.Empty;
        public int Sequence { get; set; } = 1;
        public int OffsetMinutes { get; set; } = 0;
        [Column(TypeName = "decimal(18,2)")]
        public decimal Surcharge { get; set; } = 0;
        public double Latitude { get; set; }
        public double Longitude { get; set; }
        [Required, MaxLength(30)]
        public string StopType { get; set; } = StopTypes.Both; // Pickup, Dropoff, Both, Transit
    }

    public class Trip
    {
        [Key]
        public int TripId { get; set; }
        public int CompanyId { get; set; }
        public BusCompany? Company { get; set; }
        public int RouteId { get; set; }
        public Route? Route { get; set; }
        public int BusId { get; set; }
        public Bus? Bus { get; set; }
        public DateTime DepartureAt { get; set; }
        public DateTime ArrivalEstimate { get; set; }
        public DateTime? DelayedArrivalEstimate { get; set; }
        [MaxLength(300)]
        public string? DelayReason { get; set; }
        [Column(TypeName = "decimal(18,2)")]
        public decimal BasePrice { get; set; }
        public DateTime SaleOpenAt { get; set; } = DateTime.UtcNow.AddDays(-7);
        [Required, MaxLength(30)]
        public string Status { get; set; } = TripStatuses.Scheduled;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public ICollection<TripSeat> TripSeats { get; set; } = new List<TripSeat>();
        public ICollection<DriverAssignment> DriverAssignments { get; set; } = new List<DriverAssignment>();
    }

    public class TripSeat
    {
        [Key]
        public int TripSeatId { get; set; }
        public int TripId { get; set; }
        public Trip? Trip { get; set; }
        public int BusSeatId { get; set; }
        public BusSeat? BusSeat { get; set; }
        [Required, MaxLength(20)]
        public string SeatCode { get; set; } = string.Empty;
        public int Deck { get; set; } = 1;
        public int Row { get; set; } = 1;
        public int Column { get; set; } = 1;
        [Required, MaxLength(30)]
        public string SeatStatus { get; set; } = SeatStatuses.Available;
        [Column(TypeName = "decimal(18,2)")]
        public decimal CurrentPrice { get; set; }
        [Timestamp]
        public byte[]? RowVersion { get; set; }
    }

    public class TripStatusHistory
    {
        [Key]
        public int HistoryId { get; set; }
        public int TripId { get; set; }
        public Trip? Trip { get; set; }
        [Required, MaxLength(30)]
        public string OldStatus { get; set; } = string.Empty;
        [Required, MaxLength(30)]
        public string NewStatus { get; set; } = string.Empty;
        public int? ChangedByUserId { get; set; }
        public DateTime ChangedAt { get; set; } = DateTime.UtcNow;
        [MaxLength(500)]
        public string? Reason { get; set; }
    }

    // 10.5. Đặt vé và thanh toán
    public class SeatHold
    {
        [Key]
        public int HoldId { get; set; }
        public int TripId { get; set; }
        public int TripSeatId { get; set; }
        public TripSeat? TripSeat { get; set; }
        public int UserId { get; set; }
        public User? User { get; set; }
        [Required, MaxLength(100)]
        public string HoldToken { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime HoldExpiresAt { get; set; }
        [Required, MaxLength(30)]
        public string Status { get; set; } = HoldStatuses.Active;
    }

    public class Booking
    {
        [Key]
        public int BookingId { get; set; }
        public int UserId { get; set; }
        public User? User { get; set; }
        public int TripId { get; set; }
        public Trip? Trip { get; set; }
        public int? LinkedBookingId { get; set; }
        [Required, MaxLength(40)]
        public string BookingCode { get; set; } = string.Empty;
        [MaxLength(100)]
        public string? HoldToken { get; set; }
        [Required, MaxLength(120)]
        public string ContactName { get; set; } = string.Empty;
        [Required, MaxLength(30)]
        public string ContactPhone { get; set; } = string.Empty;
        [MaxLength(150)]
        public string? ContactEmail { get; set; }
        [Column(TypeName = "decimal(18,2)")]
        public decimal SubTotal { get; set; }
        [Column(TypeName = "decimal(18,2)")]
        public decimal SurchargeTotal { get; set; }
        [Column(TypeName = "decimal(18,2)")]
        public decimal DiscountAmount { get; set; }
        [Column(TypeName = "decimal(18,2)")]
        public decimal TotalAmount { get; set; }
        [Required, MaxLength(30)]
        public string Status { get; set; } = BookingStatuses.PendingPayment;
        [MaxLength(500)]
        public string? CancelReason { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime ExpiresAt { get; set; }

        public ICollection<BookingDetail> Details { get; set; } = new List<BookingDetail>();
        public ICollection<Payment> Payments { get; set; } = new List<Payment>();
    }

    public class BookingDetail
    {
        [Key]
        public int BookingDetailId { get; set; }
        public int BookingId { get; set; }
        public Booking? Booking { get; set; }
        public int TripSeatId { get; set; }
        public TripSeat? TripSeat { get; set; }
        [Required, MaxLength(20)]
        public string SeatCode { get; set; } = string.Empty;
        [Required, MaxLength(120)]
        public string PassengerName { get; set; } = string.Empty;
        [MaxLength(30)]
        public string? PassengerPhone { get; set; }
        public int? PickupStopId { get; set; }
        public RouteStop? PickupStop { get; set; }
        public int? DropoffStopId { get; set; }
        public RouteStop? DropoffStop { get; set; }
        [Column(TypeName = "decimal(18,2)")]
        public decimal UnitPrice { get; set; }
        [Column(TypeName = "decimal(18,2)")]
        public decimal Surcharge { get; set; }
        public bool IsActiveBooking { get; set; } = true;

        public Ticket? Ticket { get; set; }
    }

    public class Payment
    {
        [Key]
        public int PaymentId { get; set; }
        public int BookingId { get; set; }
        public Booking? Booking { get; set; }
        [Required, MaxLength(30)]
        public string Method { get; set; } = PaymentMethods.VNPay;
        [Column(TypeName = "decimal(18,2)")]
        public decimal Amount { get; set; }
        [Required, MaxLength(30)]
        public string Status { get; set; } = PaymentStatuses.Pending;
        public int? CollectedByUserId { get; set; }
        public DateTime? PaidAt { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        public ICollection<PaymentTransaction> Transactions { get; set; } = new List<PaymentTransaction>();
        public ICollection<Refund> Refunds { get; set; } = new List<Refund>();
    }

    public class PaymentTransaction
    {
        [Key]
        public int TransactionId { get; set; }
        public int PaymentId { get; set; }
        public Payment? Payment { get; set; }
        [Required, MaxLength(100)]
        public string ProviderRef { get; set; } = string.Empty;
        [MaxLength(100)]
        public string TxnRef { get; set; } = string.Empty;
        [MaxLength(20)]
        public string ResponseCode { get; set; } = string.Empty;
        [Required, MaxLength(40)]
        public string RawStatus { get; set; } = string.Empty;
        [MaxLength(2000)]
        public string? RawPayload { get; set; }
        public bool SignatureValid { get; set; } = true;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public class Refund
    {
        [Key]
        public int RefundId { get; set; }
        public int PaymentId { get; set; }
        public Payment? Payment { get; set; }
        public int BookingId { get; set; }
        [Column(TypeName = "decimal(18,2)")]
        public decimal Amount { get; set; }
        [Required, MaxLength(500)]
        public string Reason { get; set; } = string.Empty;
        [Required, MaxLength(30)]
        public string Status { get; set; } = "Pending"; // Pending, Completed, Rejected
        public int? ProcessedByUserId { get; set; }
        public DateTime RequestedAt { get; set; } = DateTime.UtcNow;
        public DateTime? CompletedAt { get; set; }
    }

    public class Ticket
    {
        [Key]
        public int TicketId { get; set; }
        public int BookingDetailId { get; set; }
        public BookingDetail? BookingDetail { get; set; }
        public int TripId { get; set; }
        [Required, MaxLength(50)]
        public string TicketCode { get; set; } = string.Empty;
        [Required, MaxLength(256)]
        public string QRTokenHash { get; set; } = string.Empty;
        [Required, MaxLength(300)]
        public string QRDisplayPayload { get; set; } = string.Empty;
        [Required, MaxLength(30)]
        public string Status { get; set; } = TicketStatuses.Active;
        public DateTime IssuedAt { get; set; } = DateTime.UtcNow;

        public ICollection<TicketCheckIn> CheckIns { get; set; } = new List<TicketCheckIn>();
    }

    public class TicketCheckIn
    {
        [Key]
        public int CheckInId { get; set; }
        public int TicketId { get; set; }
        public Ticket? Ticket { get; set; }
        public int CheckedByUserId { get; set; }
        [MaxLength(150)]
        public string? DeviceInfo { get; set; }
        public DateTime CheckedAt { get; set; } = DateTime.UtcNow;
        [Required, MaxLength(50)]
        public string Result { get; set; } = "Success"; // Success, AlreadyCheckedIn, InvalidTrip, CancelledTicket
        [MaxLength(300)]
        public string? Note { get; set; }
    }

    // 10.6. Theo dõi và hỗ trợ
    public class TripLocation
    {
        [Key]
        public int LocationId { get; set; }
        public int TripId { get; set; }
        public Trip? Trip { get; set; }
        public int DriverId { get; set; }
        public Driver? Driver { get; set; }
        public double Latitude { get; set; }
        public double Longitude { get; set; }
        public double SpeedKmh { get; set; }
        public double Accuracy { get; set; }
        public DateTime RecordedAt { get; set; } = DateTime.UtcNow;
    }

    public class TripLiveLocation
    {
        [Key, DatabaseGenerated(DatabaseGeneratedOption.None)]
        public int TripId { get; set; }
        public Trip? Trip { get; set; }
        public int DriverId { get; set; }
        public double Latitude { get; set; }
        public double Longitude { get; set; }
        public double SpeedKmh { get; set; }
        public double Accuracy { get; set; }
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    }

    public class TripIncident
    {
        [Key]
        public int IncidentId { get; set; }
        public int TripId { get; set; }
        public Trip? Trip { get; set; }
        public int DriverId { get; set; }
        public Driver? Driver { get; set; }
        [Required, MaxLength(80)]
        public string Type { get; set; } = string.Empty;
        [Required, MaxLength(500)]
        public string Description { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public class TripMessage
    {
        [Key]
        public int MessageId { get; set; }
        public int TripId { get; set; }
        public Trip? Trip { get; set; }
        public int? BookingId { get; set; }
        public int SenderUserId { get; set; }
        public User? SenderUser { get; set; }
        [Required, MaxLength(100)]
        public string SenderName { get; set; } = string.Empty;
        [Required, MaxLength(30)]
        public string SenderRole { get; set; } = "Customer"; // Customer, Driver, Staff
        [Required, MaxLength(1000)]
        public string Content { get; set; } = string.Empty;
        public bool IsRead { get; set; } = false;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public class Notification
    {
        [Key]
        public int NotificationId { get; set; }
        public int UserId { get; set; }
        public User? User { get; set; }
        [Required, MaxLength(180)]
        public string Title { get; set; } = string.Empty;
        [Required, MaxLength(1000)]
        public string Content { get; set; } = string.Empty;
        [Required, MaxLength(50)]
        public string Type { get; set; } = "General";
        public int? ReferenceId { get; set; }
        public bool IsRead { get; set; } = false;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public class Review
    {
        [Key]
        public int ReviewId { get; set; }
        public int BookingId { get; set; }
        public Booking? Booking { get; set; }
        public int TripId { get; set; }
        public int CompanyId { get; set; }
        public int UserId { get; set; }
        public User? User { get; set; }
        [Range(1, 5)]
        public int Rating { get; set; } = 5;
        [MaxLength(1000)]
        public string? Comment { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public class SupportRequest
    {
        [Key]
        public int RequestId { get; set; }
        public int UserId { get; set; }
        public User? User { get; set; }
        public int? CompanyId { get; set; }
        public int? BookingId { get; set; }
        [Required, MaxLength(200)]
        public string Subject { get; set; } = string.Empty;
        [Required, MaxLength(2000)]
        public string Content { get; set; } = string.Empty;
        [Required, MaxLength(30)]
        public string Status { get; set; } = "Open"; // Open, InProgress, Resolved, Closed
        public int? HandledByUserId { get; set; }
        [MaxLength(2000)]
        public string? ReplyContent { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime? UpdatedAt { get; set; }
    }

    public class AuditLog
    {
        [Key]
        public int AuditId { get; set; }
        public int? UserId { get; set; }
        public int? CompanyId { get; set; }
        [Required, MaxLength(100)]
        public string Action { get; set; } = string.Empty;
        [Required, MaxLength(80)]
        public string EntityName { get; set; } = string.Empty;
        [MaxLength(80)]
        public string? EntityId { get; set; }
        [MaxLength(2000)]
        public string? Details { get; set; }
        [MaxLength(60)]
        public string? IpAddress { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    // Mở rộng nâng cao: Chương trình Khuyến mãi / Voucher động & Ký gửi Hàng hóa theo chuyến
    public class Promotion
    {
        [Key]
        public int PromotionId { get; set; }
        [Required, MaxLength(50)]
        public string Code { get; set; } = string.Empty;
        [Required, MaxLength(250)]
        public string Description { get; set; } = string.Empty;
        [Required, MaxLength(20)]
        public string DiscountType { get; set; } = "Fixed"; // Fixed, Percent
        [Column(TypeName = "decimal(18,2)")]
        public decimal DiscountValue { get; set; }
        [Column(TypeName = "decimal(18,2)")]
        public decimal MaxDiscountAmount { get; set; }
        public int UsageLimit { get; set; } = 100;
        public int UsedCount { get; set; } = 0;
        public DateTime ExpiresAt { get; set; } = DateTime.UtcNow.AddDays(30);
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public class CargoShipment
    {
        [Key]
        public int ShipmentId { get; set; }
        public int TripId { get; set; }
        public Trip? Trip { get; set; }
        public int CompanyId { get; set; }
        [Required, MaxLength(40)]
        public string TrackingCode { get; set; } = string.Empty;
        [Required, MaxLength(120)]
        public string SenderName { get; set; } = string.Empty;
        [Required, MaxLength(30)]
        public string SenderPhone { get; set; } = string.Empty;
        [Required, MaxLength(120)]
        public string ReceiverName { get; set; } = string.Empty;
        [Required, MaxLength(30)]
        public string ReceiverPhone { get; set; } = string.Empty;
        [Required, MaxLength(300)]
        public string Description { get; set; } = string.Empty;
        public double WeightKg { get; set; } = 1.0;
        [Column(TypeName = "decimal(18,2)")]
        public decimal FeeAmount { get; set; } = 50000;
        [Required, MaxLength(30)]
        public string Status { get; set; } = "Received"; // Received, InTransit, Delivered
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    // Đợt 2: 8 Tính năng thông minh & Vận hành chuyên sâu (Super-App Suite)
    public class TripWaitlist
    {
        [Key]
        public int WaitlistId { get; set; }
        public int TripId { get; set; }
        public int UserId { get; set; }
        [Required, MaxLength(120)]
        public string CustomerName { get; set; } = string.Empty;
        [Required, MaxLength(30)]
        public string CustomerPhone { get; set; } = string.Empty;
        public int SeatCountRequested { get; set; } = 1;
        [Required, MaxLength(30)]
        public string Status { get; set; } = "Waiting"; // Waiting, Notified, Booked
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime? NotifiedAt { get; set; }
    }

    public class ShuttleRequest
    {
        [Key]
        public int ShuttleRequestId { get; set; }
        public int BookingId { get; set; }
        public int TripId { get; set; }
        public int CompanyId { get; set; }
        [Required, MaxLength(120)]
        public string PassengerName { get; set; } = string.Empty;
        [Required, MaxLength(30)]
        public string PassengerPhone { get; set; } = string.Empty;
        [Required, MaxLength(300)]
        public string PickupAddress { get; set; } = string.Empty;
        [MaxLength(300)]
        public string? DropoffAddress { get; set; }
        [Required, MaxLength(100)]
        public string PickupArea { get; set; } = "Trung tâm";
        [MaxLength(100)]
        public string? ShuttlePlate { get; set; }
        [Required, MaxLength(30)]
        public string Status { get; set; } = "Requested"; // Requested, Assigned, PickedUp
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public class SavedCompanion
    {
        [Key]
        public int CompanionId { get; set; }
        public int UserId { get; set; }
        [Required, MaxLength(120)]
        public string FullName { get; set; } = string.Empty;
        [Required, MaxLength(30)]
        public string Phone { get; set; } = string.Empty;
        [Required, MaxLength(60)]
        public string Relationship { get; set; } = "Gia đình"; // Gia đình, Bạn bè, Đồng nghiệp
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public class InvoiceRequest
    {
        [Key]
        public int InvoiceRequestId { get; set; }
        public int BookingId { get; set; }
        [Required, MaxLength(40)]
        public string BookingCode { get; set; } = string.Empty;
        [Required, MaxLength(40)]
        public string TaxCode { get; set; } = string.Empty;
        [Required, MaxLength(200)]
        public string CompanyName { get; set; } = string.Empty;
        [Required, MaxLength(300)]
        public string CompanyAddress { get; set; } = string.Empty;
        [Required, MaxLength(150)]
        public string BuyerEmail { get; set; } = string.Empty;
        [Column(TypeName = "decimal(18,2)")]
        public decimal TotalAmount { get; set; }
        [Column(TypeName = "decimal(18,2)")]
        public decimal VatAmount { get; set; }
        [Required, MaxLength(60)]
        public string InvoiceNumber { get; set; } = string.Empty;
        [Required, MaxLength(30)]
        public string Status { get; set; } = "Issued";
        public DateTime IssuedAt { get; set; } = DateTime.UtcNow;
    }

    public class TripExpense
    {
        [Key]
        public int ExpenseId { get; set; }
        public int TripId { get; set; }
        public int CompanyId { get; set; }
        [Required, MaxLength(60)]
        public string Category { get; set; } = "Fuel"; // Fuel, BOT, DriverAllowance, Other
        [Column(TypeName = "decimal(18,2)")]
        public decimal Amount { get; set; }
        [Required, MaxLength(300)]
        public string Note { get; set; } = string.Empty;
        public int RecordedByUserId { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public class TripSafetyCheck
    {
        [Key]
        public int SafetyCheckId { get; set; }
        public int TripId { get; set; }
        public int DriverId { get; set; }
        public bool BrakesOk { get; set; } = true;
        public bool TiresOk { get; set; } = true;
        public bool FireExtinguisherOk { get; set; } = true;
        public bool DashcamOk { get; set; } = true;
        public bool ZeroAlcoholConfirmed { get; set; } = true;
        [MaxLength(300)]
        public string? Note { get; set; }
        public DateTime CheckedAt { get; set; } = DateTime.UtcNow;
    }
}

