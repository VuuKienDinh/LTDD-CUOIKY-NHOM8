namespace webAPI.Models
{
    public static class RoleNames
    {
        public const string Admin = "Admin";
        public const string BusOperator = "BusOperator";
        public const string Staff = "Staff";
        public const string Driver = "Driver";
        public const string Customer = "Customer";
    }

    public static class CompanyStatuses
    {
        public const string Pending = "Pending";
        public const string Active = "Active";
        public const string Rejected = "Rejected";
        public const string Suspended = "Suspended";
        public const string Inactive = "Inactive";
    }

    public static class BusStatuses
    {
        public const string Active = "Active";
        public const string Maintenance = "Maintenance";
        public const string Inactive = "Inactive";
    }

    public static class TripStatuses
    {
        public const string Draft = "Draft";
        public const string Scheduled = "Scheduled";
        public const string Boarding = "Boarding";
        public const string Departed = "Departed";
        public const string Delayed = "Delayed";
        public const string Arrived = "Arrived";
        public const string Cancelled = "Cancelled";
    }

    public static class SeatStatuses
    {
        public const string Available = "Available";
        public const string Held = "Held";
        public const string Booked = "Booked";
        public const string Unavailable = "Unavailable";
    }

    public static class HoldStatuses
    {
        public const string Active = "Active";
        public const string Converted = "Converted";
        public const string Expired = "Expired";
        public const string Released = "Released";
    }

    public static class BookingStatuses
    {
        public const string PendingPayment = "PendingPayment";
        public const string Confirmed = "Confirmed";
        public const string Expired = "Expired";
        public const string Cancelled = "Cancelled";
        public const string Completed = "Completed";
        public const string Refunded = "Refunded";
        public const string NoShow = "NoShow";
        public const string ReconcileRequired = "ReconcileRequired";
    }

    public static class PaymentStatuses
    {
        public const string Unpaid = "Unpaid";
        public const string Pending = "Pending";
        public const string Paid = "Paid";
        public const string Failed = "Failed";
        public const string Cancelled = "Cancelled";
        public const string RefundPending = "RefundPending";
        public const string PartiallyRefunded = "PartiallyRefunded";
        public const string Refunded = "Refunded";
    }

    public static class PaymentMethods
    {
        public const string VNPay = "VNPay";
        public const string COD = "COD";
    }

    public static class TicketStatuses
    {
        public const string Active = "Active";
        public const string Used = "Used";
        public const string Cancelled = "Cancelled";
        public const string Expired = "Expired";
    }

    public static class StopTypes
    {
        public const string Pickup = "Pickup";
        public const string Dropoff = "Dropoff";
        public const string Both = "Both";
        public const string Transit = "Transit";
    }
}

