CREATE TABLE [AuditLogs] (
    [AuditId] int NOT NULL IDENTITY,
    [UserId] int NULL,
    [CompanyId] int NULL,
    [Action] nvarchar(100) NOT NULL,
    [EntityName] nvarchar(80) NOT NULL,
    [EntityId] nvarchar(80) NULL,
    [Details] nvarchar(2000) NULL,
    [IpAddress] nvarchar(60) NULL,
    [CreatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_AuditLogs] PRIMARY KEY ([AuditId])
);
GO


CREATE TABLE [BusCompanies] (
    [CompanyId] int NOT NULL IDENTITY,
    [Name] nvarchar(150) NOT NULL,
    [TaxCode] nvarchar(50) NOT NULL,
    [Address] nvarchar(250) NOT NULL,
    [Phone] nvarchar(30) NOT NULL,
    [Email] nvarchar(150) NULL,
    [LogoUrl] nvarchar(300) NULL,
    [Description] nvarchar(1000) NULL,
    [RepresentativeName] nvarchar(120) NULL,
    [Status] nvarchar(30) NOT NULL,
    [RejectionReason] nvarchar(500) NULL,
    [AllowCod] bit NOT NULL,
    [MaxCodSeatsPerBooking] int NOT NULL,
    [SeatHoldMinutes] int NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_BusCompanies] PRIMARY KEY ([CompanyId])
);
GO


CREATE TABLE [InvoiceRequests] (
    [InvoiceRequestId] int NOT NULL IDENTITY,
    [BookingId] int NOT NULL,
    [BookingCode] nvarchar(40) NOT NULL,
    [TaxCode] nvarchar(40) NOT NULL,
    [CompanyName] nvarchar(200) NOT NULL,
    [CompanyAddress] nvarchar(300) NOT NULL,
    [BuyerEmail] nvarchar(150) NOT NULL,
    [TotalAmount] decimal(18,2) NOT NULL,
    [VatAmount] decimal(18,2) NOT NULL,
    [InvoiceNumber] nvarchar(60) NOT NULL,
    [Status] nvarchar(30) NOT NULL,
    [IssuedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_InvoiceRequests] PRIMARY KEY ([InvoiceRequestId])
);
GO


CREATE TABLE [Promotions] (
    [PromotionId] int NOT NULL IDENTITY,
    [Code] nvarchar(50) NOT NULL,
    [Description] nvarchar(250) NOT NULL,
    [DiscountType] nvarchar(20) NOT NULL,
    [DiscountValue] decimal(18,2) NOT NULL,
    [MaxDiscountAmount] decimal(18,2) NOT NULL,
    [UsageLimit] int NOT NULL,
    [UsedCount] int NOT NULL,
    [ExpiresAt] datetime2 NOT NULL,
    [IsActive] bit NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_Promotions] PRIMARY KEY ([PromotionId])
);
GO


CREATE TABLE [Provinces] (
    [ProvinceId] int NOT NULL IDENTITY,
    [Name] nvarchar(100) NOT NULL,
    [Code] nvarchar(20) NOT NULL,
    CONSTRAINT [PK_Provinces] PRIMARY KEY ([ProvinceId])
);
GO


CREATE TABLE [Roles] (
    [RoleId] int NOT NULL IDENTITY,
    [RoleName] nvarchar(50) NOT NULL,
    [Description] nvarchar(200) NULL,
    CONSTRAINT [PK_Roles] PRIMARY KEY ([RoleId])
);
GO


CREATE TABLE [SavedCompanions] (
    [CompanionId] int NOT NULL IDENTITY,
    [UserId] int NOT NULL,
    [FullName] nvarchar(120) NOT NULL,
    [Phone] nvarchar(30) NOT NULL,
    [Relationship] nvarchar(60) NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_SavedCompanions] PRIMARY KEY ([CompanionId])
);
GO


CREATE TABLE [ShuttleRequests] (
    [ShuttleRequestId] int NOT NULL IDENTITY,
    [BookingId] int NOT NULL,
    [TripId] int NOT NULL,
    [CompanyId] int NOT NULL,
    [PassengerName] nvarchar(120) NOT NULL,
    [PassengerPhone] nvarchar(30) NOT NULL,
    [PickupAddress] nvarchar(300) NOT NULL,
    [DropoffAddress] nvarchar(300) NULL,
    [PickupArea] nvarchar(100) NOT NULL,
    [ShuttlePlate] nvarchar(100) NULL,
    [Status] nvarchar(30) NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_ShuttleRequests] PRIMARY KEY ([ShuttleRequestId])
);
GO


CREATE TABLE [TripExpenses] (
    [ExpenseId] int NOT NULL IDENTITY,
    [TripId] int NOT NULL,
    [CompanyId] int NOT NULL,
    [Category] nvarchar(60) NOT NULL,
    [Amount] decimal(18,2) NOT NULL,
    [Note] nvarchar(300) NOT NULL,
    [RecordedByUserId] int NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_TripExpenses] PRIMARY KEY ([ExpenseId])
);
GO


CREATE TABLE [TripSafetyChecks] (
    [SafetyCheckId] int NOT NULL IDENTITY,
    [TripId] int NOT NULL,
    [DriverId] int NOT NULL,
    [BrakesOk] bit NOT NULL,
    [TiresOk] bit NOT NULL,
    [FireExtinguisherOk] bit NOT NULL,
    [DashcamOk] bit NOT NULL,
    [ZeroAlcoholConfirmed] bit NOT NULL,
    [Note] nvarchar(300) NULL,
    [CheckedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_TripSafetyChecks] PRIMARY KEY ([SafetyCheckId])
);
GO


CREATE TABLE [TripWaitlists] (
    [WaitlistId] int NOT NULL IDENTITY,
    [TripId] int NOT NULL,
    [UserId] int NOT NULL,
    [CustomerName] nvarchar(120) NOT NULL,
    [CustomerPhone] nvarchar(30) NOT NULL,
    [SeatCountRequested] int NOT NULL,
    [Status] nvarchar(30) NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    [NotifiedAt] datetime2 NULL,
    CONSTRAINT [PK_TripWaitlists] PRIMARY KEY ([WaitlistId])
);
GO


CREATE TABLE [Users] (
    [UserId] int NOT NULL IDENTITY,
    [FullName] nvarchar(120) NOT NULL,
    [Email] nvarchar(150) NOT NULL,
    [Phone] nvarchar(25) NOT NULL,
    [PasswordHash] nvarchar(max) NOT NULL,
    [IsActive] bit NOT NULL,
    [NoShowCount] int NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_Users] PRIMARY KEY ([UserId])
);
GO


CREATE TABLE [Buses] (
    [BusId] int NOT NULL IDENTITY,
    [CompanyId] int NOT NULL,
    [PlateNumber] nvarchar(30) NOT NULL,
    [BusType] nvarchar(50) NOT NULL,
    [BrandModel] nvarchar(100) NOT NULL,
    [TotalSeats] int NOT NULL,
    [ManufactureYear] int NOT NULL,
    [TurnaroundMinutes] int NOT NULL,
    [Status] nvarchar(30) NOT NULL,
    CONSTRAINT [PK_Buses] PRIMARY KEY ([BusId]),
    CONSTRAINT [FK_Buses_BusCompanies_CompanyId] FOREIGN KEY ([CompanyId]) REFERENCES [BusCompanies] ([CompanyId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [Routes] (
    [RouteId] int NOT NULL IDENTITY,
    [CompanyId] int NOT NULL,
    [OriginProvinceId] int NOT NULL,
    [DestinationProvinceId] int NOT NULL,
    [Name] nvarchar(180) NOT NULL,
    [DistanceKm] int NOT NULL,
    [EstimatedDurationMinutes] int NOT NULL,
    [IsActive] bit NOT NULL,
    CONSTRAINT [PK_Routes] PRIMARY KEY ([RouteId]),
    CONSTRAINT [FK_Routes_BusCompanies_CompanyId] FOREIGN KEY ([CompanyId]) REFERENCES [BusCompanies] ([CompanyId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_Routes_Provinces_DestinationProvinceId] FOREIGN KEY ([DestinationProvinceId]) REFERENCES [Provinces] ([ProvinceId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_Routes_Provinces_OriginProvinceId] FOREIGN KEY ([OriginProvinceId]) REFERENCES [Provinces] ([ProvinceId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [CompanyMembers] (
    [CompanyMemberId] int NOT NULL IDENTITY,
    [CompanyId] int NOT NULL,
    [UserId] int NOT NULL,
    [MemberRole] nvarchar(50) NOT NULL,
    [Status] nvarchar(30) NOT NULL,
    [JoinedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_CompanyMembers] PRIMARY KEY ([CompanyMemberId]),
    CONSTRAINT [FK_CompanyMembers_BusCompanies_CompanyId] FOREIGN KEY ([CompanyId]) REFERENCES [BusCompanies] ([CompanyId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_CompanyMembers_Users_UserId] FOREIGN KEY ([UserId]) REFERENCES [Users] ([UserId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [Drivers] (
    [DriverId] int NOT NULL IDENTITY,
    [CompanyId] int NOT NULL,
    [UserId] int NULL,
    [FullName] nvarchar(120) NOT NULL,
    [Phone] nvarchar(30) NOT NULL,
    [LicenseNumber] nvarchar(50) NOT NULL,
    [LicenseClass] nvarchar(20) NOT NULL,
    [LicenseExpiry] datetime2 NOT NULL,
    [Status] nvarchar(30) NOT NULL,
    CONSTRAINT [PK_Drivers] PRIMARY KEY ([DriverId]),
    CONSTRAINT [FK_Drivers_BusCompanies_CompanyId] FOREIGN KEY ([CompanyId]) REFERENCES [BusCompanies] ([CompanyId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_Drivers_Users_UserId] FOREIGN KEY ([UserId]) REFERENCES [Users] ([UserId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [Notifications] (
    [NotificationId] int NOT NULL IDENTITY,
    [UserId] int NOT NULL,
    [Title] nvarchar(180) NOT NULL,
    [Content] nvarchar(1000) NOT NULL,
    [Type] nvarchar(50) NOT NULL,
    [ReferenceId] int NULL,
    [IsRead] bit NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_Notifications] PRIMARY KEY ([NotificationId]),
    CONSTRAINT [FK_Notifications_Users_UserId] FOREIGN KEY ([UserId]) REFERENCES [Users] ([UserId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [RefreshTokens] (
    [TokenId] int NOT NULL IDENTITY,
    [UserId] int NOT NULL,
    [TokenHash] nvarchar(256) NOT NULL,
    [ExpiresAt] datetime2 NOT NULL,
    [RevokedAt] datetime2 NULL,
    [CreatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_RefreshTokens] PRIMARY KEY ([TokenId]),
    CONSTRAINT [FK_RefreshTokens_Users_UserId] FOREIGN KEY ([UserId]) REFERENCES [Users] ([UserId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [SupportRequests] (
    [RequestId] int NOT NULL IDENTITY,
    [UserId] int NOT NULL,
    [CompanyId] int NULL,
    [BookingId] int NULL,
    [Subject] nvarchar(200) NOT NULL,
    [Content] nvarchar(2000) NOT NULL,
    [Status] nvarchar(30) NOT NULL,
    [HandledByUserId] int NULL,
    [ReplyContent] nvarchar(2000) NULL,
    [CreatedAt] datetime2 NOT NULL,
    [UpdatedAt] datetime2 NULL,
    CONSTRAINT [PK_SupportRequests] PRIMARY KEY ([RequestId]),
    CONSTRAINT [FK_SupportRequests_Users_UserId] FOREIGN KEY ([UserId]) REFERENCES [Users] ([UserId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [UserDevices] (
    [DeviceId] int NOT NULL IDENTITY,
    [UserId] int NOT NULL,
    [FcmToken] nvarchar(512) NOT NULL,
    [DevicePlatform] nvarchar(50) NOT NULL,
    [LastSeenAt] datetime2 NOT NULL,
    CONSTRAINT [PK_UserDevices] PRIMARY KEY ([DeviceId]),
    CONSTRAINT [FK_UserDevices_Users_UserId] FOREIGN KEY ([UserId]) REFERENCES [Users] ([UserId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [UserRoles] (
    [UserRoleId] int NOT NULL IDENTITY,
    [UserId] int NOT NULL,
    [RoleId] int NOT NULL,
    [CompanyId] int NULL,
    CONSTRAINT [PK_UserRoles] PRIMARY KEY ([UserRoleId]),
    CONSTRAINT [FK_UserRoles_BusCompanies_CompanyId] FOREIGN KEY ([CompanyId]) REFERENCES [BusCompanies] ([CompanyId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_UserRoles_Roles_RoleId] FOREIGN KEY ([RoleId]) REFERENCES [Roles] ([RoleId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_UserRoles_Users_UserId] FOREIGN KEY ([UserId]) REFERENCES [Users] ([UserId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [BusMaintenances] (
    [MaintenanceId] int NOT NULL IDENTITY,
    [BusId] int NOT NULL,
    [StartAt] datetime2 NOT NULL,
    [EndAt] datetime2 NOT NULL,
    [Description] nvarchar(500) NOT NULL,
    [Status] nvarchar(30) NOT NULL,
    CONSTRAINT [PK_BusMaintenances] PRIMARY KEY ([MaintenanceId]),
    CONSTRAINT [FK_BusMaintenances_Buses_BusId] FOREIGN KEY ([BusId]) REFERENCES [Buses] ([BusId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [BusSeats] (
    [BusSeatId] int NOT NULL IDENTITY,
    [BusId] int NOT NULL,
    [SeatCode] nvarchar(20) NOT NULL,
    [Deck] int NOT NULL,
    [Row] int NOT NULL,
    [Column] int NOT NULL,
    [SeatType] nvarchar(30) NOT NULL,
    [PriceSurcharge] decimal(18,2) NOT NULL,
    [IsActive] bit NOT NULL,
    CONSTRAINT [PK_BusSeats] PRIMARY KEY ([BusSeatId]),
    CONSTRAINT [FK_BusSeats_Buses_BusId] FOREIGN KEY ([BusId]) REFERENCES [Buses] ([BusId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [RouteStops] (
    [RouteStopId] int NOT NULL IDENTITY,
    [RouteId] int NOT NULL,
    [StopName] nvarchar(150) NOT NULL,
    [Address] nvarchar(250) NOT NULL,
    [Sequence] int NOT NULL,
    [OffsetMinutes] int NOT NULL,
    [Surcharge] decimal(18,2) NOT NULL,
    [Latitude] float NOT NULL,
    [Longitude] float NOT NULL,
    [StopType] nvarchar(30) NOT NULL,
    CONSTRAINT [PK_RouteStops] PRIMARY KEY ([RouteStopId]),
    CONSTRAINT [FK_RouteStops_Routes_RouteId] FOREIGN KEY ([RouteId]) REFERENCES [Routes] ([RouteId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [Trips] (
    [TripId] int NOT NULL IDENTITY,
    [CompanyId] int NOT NULL,
    [RouteId] int NOT NULL,
    [BusId] int NOT NULL,
    [DepartureAt] datetime2 NOT NULL,
    [ArrivalEstimate] datetime2 NOT NULL,
    [DelayedArrivalEstimate] datetime2 NULL,
    [DelayReason] nvarchar(300) NULL,
    [BasePrice] decimal(18,2) NOT NULL,
    [SaleOpenAt] datetime2 NOT NULL,
    [Status] nvarchar(30) NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_Trips] PRIMARY KEY ([TripId]),
    CONSTRAINT [FK_Trips_BusCompanies_CompanyId] FOREIGN KEY ([CompanyId]) REFERENCES [BusCompanies] ([CompanyId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_Trips_Buses_BusId] FOREIGN KEY ([BusId]) REFERENCES [Buses] ([BusId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_Trips_Routes_RouteId] FOREIGN KEY ([RouteId]) REFERENCES [Routes] ([RouteId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [DriverDocuments] (
    [DocumentId] int NOT NULL IDENTITY,
    [DriverId] int NOT NULL,
    [FileUrl] nvarchar(400) NOT NULL,
    [Type] nvarchar(50) NOT NULL,
    [ExpiryDate] datetime2 NOT NULL,
    [Status] nvarchar(30) NOT NULL,
    CONSTRAINT [PK_DriverDocuments] PRIMARY KEY ([DocumentId]),
    CONSTRAINT [FK_DriverDocuments_Drivers_DriverId] FOREIGN KEY ([DriverId]) REFERENCES [Drivers] ([DriverId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [Bookings] (
    [BookingId] int NOT NULL IDENTITY,
    [UserId] int NOT NULL,
    [TripId] int NOT NULL,
    [LinkedBookingId] int NULL,
    [BookingCode] nvarchar(40) NOT NULL,
    [HoldToken] nvarchar(100) NULL,
    [ContactName] nvarchar(120) NOT NULL,
    [ContactPhone] nvarchar(30) NOT NULL,
    [ContactEmail] nvarchar(150) NULL,
    [SubTotal] decimal(18,2) NOT NULL,
    [SurchargeTotal] decimal(18,2) NOT NULL,
    [DiscountAmount] decimal(18,2) NOT NULL,
    [TotalAmount] decimal(18,2) NOT NULL,
    [Status] nvarchar(30) NOT NULL,
    [CancelReason] nvarchar(500) NULL,
    [CreatedAt] datetime2 NOT NULL,
    [ExpiresAt] datetime2 NOT NULL,
    CONSTRAINT [PK_Bookings] PRIMARY KEY ([BookingId]),
    CONSTRAINT [FK_Bookings_Trips_TripId] FOREIGN KEY ([TripId]) REFERENCES [Trips] ([TripId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_Bookings_Users_UserId] FOREIGN KEY ([UserId]) REFERENCES [Users] ([UserId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [CargoShipments] (
    [ShipmentId] int NOT NULL IDENTITY,
    [TripId] int NOT NULL,
    [CompanyId] int NOT NULL,
    [TrackingCode] nvarchar(40) NOT NULL,
    [SenderName] nvarchar(120) NOT NULL,
    [SenderPhone] nvarchar(30) NOT NULL,
    [ReceiverName] nvarchar(120) NOT NULL,
    [ReceiverPhone] nvarchar(30) NOT NULL,
    [Description] nvarchar(300) NOT NULL,
    [WeightKg] float NOT NULL,
    [FeeAmount] decimal(18,2) NOT NULL,
    [Status] nvarchar(30) NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_CargoShipments] PRIMARY KEY ([ShipmentId]),
    CONSTRAINT [FK_CargoShipments_Trips_TripId] FOREIGN KEY ([TripId]) REFERENCES [Trips] ([TripId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [DriverAssignments] (
    [AssignmentId] int NOT NULL IDENTITY,
    [TripId] int NOT NULL,
    [DriverId] int NOT NULL,
    [Role] nvarchar(30) NOT NULL,
    [AssignedAt] datetime2 NOT NULL,
    [ReleasedAt] datetime2 NULL,
    [ReplaceReason] nvarchar(300) NULL,
    CONSTRAINT [PK_DriverAssignments] PRIMARY KEY ([AssignmentId]),
    CONSTRAINT [FK_DriverAssignments_Drivers_DriverId] FOREIGN KEY ([DriverId]) REFERENCES [Drivers] ([DriverId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_DriverAssignments_Trips_TripId] FOREIGN KEY ([TripId]) REFERENCES [Trips] ([TripId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [TripIncidents] (
    [IncidentId] int NOT NULL IDENTITY,
    [TripId] int NOT NULL,
    [DriverId] int NOT NULL,
    [Type] nvarchar(80) NOT NULL,
    [Description] nvarchar(500) NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_TripIncidents] PRIMARY KEY ([IncidentId]),
    CONSTRAINT [FK_TripIncidents_Drivers_DriverId] FOREIGN KEY ([DriverId]) REFERENCES [Drivers] ([DriverId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_TripIncidents_Trips_TripId] FOREIGN KEY ([TripId]) REFERENCES [Trips] ([TripId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [TripLiveLocations] (
    [TripId] int NOT NULL,
    [DriverId] int NOT NULL,
    [Latitude] float NOT NULL,
    [Longitude] float NOT NULL,
    [SpeedKmh] float NOT NULL,
    [Accuracy] float NOT NULL,
    [UpdatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_TripLiveLocations] PRIMARY KEY ([TripId]),
    CONSTRAINT [FK_TripLiveLocations_Trips_TripId] FOREIGN KEY ([TripId]) REFERENCES [Trips] ([TripId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [TripLocations] (
    [LocationId] int NOT NULL IDENTITY,
    [TripId] int NOT NULL,
    [DriverId] int NOT NULL,
    [Latitude] float NOT NULL,
    [Longitude] float NOT NULL,
    [SpeedKmh] float NOT NULL,
    [Accuracy] float NOT NULL,
    [RecordedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_TripLocations] PRIMARY KEY ([LocationId]),
    CONSTRAINT [FK_TripLocations_Drivers_DriverId] FOREIGN KEY ([DriverId]) REFERENCES [Drivers] ([DriverId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_TripLocations_Trips_TripId] FOREIGN KEY ([TripId]) REFERENCES [Trips] ([TripId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [TripMessages] (
    [MessageId] int NOT NULL IDENTITY,
    [TripId] int NOT NULL,
    [BookingId] int NULL,
    [SenderUserId] int NOT NULL,
    [SenderName] nvarchar(100) NOT NULL,
    [SenderRole] nvarchar(30) NOT NULL,
    [Content] nvarchar(1000) NOT NULL,
    [IsRead] bit NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_TripMessages] PRIMARY KEY ([MessageId]),
    CONSTRAINT [FK_TripMessages_Trips_TripId] FOREIGN KEY ([TripId]) REFERENCES [Trips] ([TripId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_TripMessages_Users_SenderUserId] FOREIGN KEY ([SenderUserId]) REFERENCES [Users] ([UserId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [TripSeats] (
    [TripSeatId] int NOT NULL IDENTITY,
    [TripId] int NOT NULL,
    [BusSeatId] int NOT NULL,
    [SeatCode] nvarchar(20) NOT NULL,
    [Deck] int NOT NULL,
    [Row] int NOT NULL,
    [Column] int NOT NULL,
    [SeatStatus] nvarchar(30) NOT NULL,
    [CurrentPrice] decimal(18,2) NOT NULL,
    [RowVersion] rowversion NULL,
    CONSTRAINT [PK_TripSeats] PRIMARY KEY ([TripSeatId]),
    CONSTRAINT [FK_TripSeats_BusSeats_BusSeatId] FOREIGN KEY ([BusSeatId]) REFERENCES [BusSeats] ([BusSeatId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_TripSeats_Trips_TripId] FOREIGN KEY ([TripId]) REFERENCES [Trips] ([TripId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [TripStatusHistories] (
    [HistoryId] int NOT NULL IDENTITY,
    [TripId] int NOT NULL,
    [OldStatus] nvarchar(30) NOT NULL,
    [NewStatus] nvarchar(30) NOT NULL,
    [ChangedByUserId] int NULL,
    [ChangedAt] datetime2 NOT NULL,
    [Reason] nvarchar(500) NULL,
    CONSTRAINT [PK_TripStatusHistories] PRIMARY KEY ([HistoryId]),
    CONSTRAINT [FK_TripStatusHistories_Trips_TripId] FOREIGN KEY ([TripId]) REFERENCES [Trips] ([TripId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [Payments] (
    [PaymentId] int NOT NULL IDENTITY,
    [BookingId] int NOT NULL,
    [Method] nvarchar(30) NOT NULL,
    [Amount] decimal(18,2) NOT NULL,
    [Status] nvarchar(30) NOT NULL,
    [CollectedByUserId] int NULL,
    [PaidAt] datetime2 NULL,
    [CreatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_Payments] PRIMARY KEY ([PaymentId]),
    CONSTRAINT [FK_Payments_Bookings_BookingId] FOREIGN KEY ([BookingId]) REFERENCES [Bookings] ([BookingId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [Reviews] (
    [ReviewId] int NOT NULL IDENTITY,
    [BookingId] int NOT NULL,
    [TripId] int NOT NULL,
    [CompanyId] int NOT NULL,
    [UserId] int NOT NULL,
    [Rating] int NOT NULL,
    [Comment] nvarchar(1000) NULL,
    [CreatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_Reviews] PRIMARY KEY ([ReviewId]),
    CONSTRAINT [FK_Reviews_Bookings_BookingId] FOREIGN KEY ([BookingId]) REFERENCES [Bookings] ([BookingId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_Reviews_Users_UserId] FOREIGN KEY ([UserId]) REFERENCES [Users] ([UserId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [BookingDetails] (
    [BookingDetailId] int NOT NULL IDENTITY,
    [BookingId] int NOT NULL,
    [TripSeatId] int NOT NULL,
    [SeatCode] nvarchar(20) NOT NULL,
    [PassengerName] nvarchar(120) NOT NULL,
    [PassengerPhone] nvarchar(30) NULL,
    [PickupStopId] int NULL,
    [DropoffStopId] int NULL,
    [UnitPrice] decimal(18,2) NOT NULL,
    [Surcharge] decimal(18,2) NOT NULL,
    [IsActiveBooking] bit NOT NULL,
    CONSTRAINT [PK_BookingDetails] PRIMARY KEY ([BookingDetailId]),
    CONSTRAINT [FK_BookingDetails_Bookings_BookingId] FOREIGN KEY ([BookingId]) REFERENCES [Bookings] ([BookingId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_BookingDetails_RouteStops_DropoffStopId] FOREIGN KEY ([DropoffStopId]) REFERENCES [RouteStops] ([RouteStopId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_BookingDetails_RouteStops_PickupStopId] FOREIGN KEY ([PickupStopId]) REFERENCES [RouteStops] ([RouteStopId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_BookingDetails_TripSeats_TripSeatId] FOREIGN KEY ([TripSeatId]) REFERENCES [TripSeats] ([TripSeatId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [SeatHolds] (
    [HoldId] int NOT NULL IDENTITY,
    [TripId] int NOT NULL,
    [TripSeatId] int NOT NULL,
    [UserId] int NOT NULL,
    [HoldToken] nvarchar(100) NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    [HoldExpiresAt] datetime2 NOT NULL,
    [Status] nvarchar(30) NOT NULL,
    CONSTRAINT [PK_SeatHolds] PRIMARY KEY ([HoldId]),
    CONSTRAINT [FK_SeatHolds_TripSeats_TripSeatId] FOREIGN KEY ([TripSeatId]) REFERENCES [TripSeats] ([TripSeatId]) ON DELETE NO ACTION,
    CONSTRAINT [FK_SeatHolds_Users_UserId] FOREIGN KEY ([UserId]) REFERENCES [Users] ([UserId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [PaymentTransactions] (
    [TransactionId] int NOT NULL IDENTITY,
    [PaymentId] int NOT NULL,
    [ProviderRef] nvarchar(100) NOT NULL,
    [TxnRef] nvarchar(100) NOT NULL,
    [ResponseCode] nvarchar(20) NOT NULL,
    [RawStatus] nvarchar(40) NOT NULL,
    [RawPayload] nvarchar(2000) NULL,
    [SignatureValid] bit NOT NULL,
    [CreatedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_PaymentTransactions] PRIMARY KEY ([TransactionId]),
    CONSTRAINT [FK_PaymentTransactions_Payments_PaymentId] FOREIGN KEY ([PaymentId]) REFERENCES [Payments] ([PaymentId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [Refunds] (
    [RefundId] int NOT NULL IDENTITY,
    [PaymentId] int NOT NULL,
    [BookingId] int NOT NULL,
    [Amount] decimal(18,2) NOT NULL,
    [Reason] nvarchar(500) NOT NULL,
    [Status] nvarchar(30) NOT NULL,
    [ProcessedByUserId] int NULL,
    [RequestedAt] datetime2 NOT NULL,
    [CompletedAt] datetime2 NULL,
    CONSTRAINT [PK_Refunds] PRIMARY KEY ([RefundId]),
    CONSTRAINT [FK_Refunds_Payments_PaymentId] FOREIGN KEY ([PaymentId]) REFERENCES [Payments] ([PaymentId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [Tickets] (
    [TicketId] int NOT NULL IDENTITY,
    [BookingDetailId] int NOT NULL,
    [TripId] int NOT NULL,
    [TicketCode] nvarchar(50) NOT NULL,
    [QRTokenHash] nvarchar(256) NOT NULL,
    [QRDisplayPayload] nvarchar(300) NOT NULL,
    [Status] nvarchar(30) NOT NULL,
    [IssuedAt] datetime2 NOT NULL,
    CONSTRAINT [PK_Tickets] PRIMARY KEY ([TicketId]),
    CONSTRAINT [FK_Tickets_BookingDetails_BookingDetailId] FOREIGN KEY ([BookingDetailId]) REFERENCES [BookingDetails] ([BookingDetailId]) ON DELETE NO ACTION
);
GO


CREATE TABLE [TicketCheckIns] (
    [CheckInId] int NOT NULL IDENTITY,
    [TicketId] int NOT NULL,
    [CheckedByUserId] int NOT NULL,
    [DeviceInfo] nvarchar(150) NULL,
    [CheckedAt] datetime2 NOT NULL,
    [Result] nvarchar(50) NOT NULL,
    [Note] nvarchar(300) NULL,
    CONSTRAINT [PK_TicketCheckIns] PRIMARY KEY ([CheckInId]),
    CONSTRAINT [FK_TicketCheckIns_Tickets_TicketId] FOREIGN KEY ([TicketId]) REFERENCES [Tickets] ([TicketId]) ON DELETE NO ACTION
);
GO


CREATE INDEX [IX_BookingDetails_BookingId] ON [BookingDetails] ([BookingId]);
GO


CREATE INDEX [IX_BookingDetails_DropoffStopId] ON [BookingDetails] ([DropoffStopId]);
GO


CREATE INDEX [IX_BookingDetails_PickupStopId] ON [BookingDetails] ([PickupStopId]);
GO


CREATE UNIQUE INDEX [IX_BookingDetails_TripSeatId] ON [BookingDetails] ([TripSeatId]) WHERE [IsActiveBooking] = 1;
GO


CREATE UNIQUE INDEX [IX_Bookings_BookingCode] ON [Bookings] ([BookingCode]);
GO


CREATE INDEX [IX_Bookings_TripId] ON [Bookings] ([TripId]);
GO


CREATE INDEX [IX_Bookings_UserId] ON [Bookings] ([UserId]);
GO


CREATE INDEX [IX_Buses_CompanyId] ON [Buses] ([CompanyId]);
GO


CREATE UNIQUE INDEX [IX_Buses_PlateNumber] ON [Buses] ([PlateNumber]);
GO


CREATE INDEX [IX_BusMaintenances_BusId] ON [BusMaintenances] ([BusId]);
GO


CREATE UNIQUE INDEX [IX_BusSeats_BusId_SeatCode] ON [BusSeats] ([BusId], [SeatCode]);
GO


CREATE INDEX [IX_CargoShipments_TripId] ON [CargoShipments] ([TripId]);
GO


CREATE INDEX [IX_CompanyMembers_CompanyId] ON [CompanyMembers] ([CompanyId]);
GO


CREATE INDEX [IX_CompanyMembers_UserId] ON [CompanyMembers] ([UserId]);
GO


CREATE INDEX [IX_DriverAssignments_DriverId] ON [DriverAssignments] ([DriverId]);
GO


CREATE INDEX [IX_DriverAssignments_TripId] ON [DriverAssignments] ([TripId]);
GO


CREATE INDEX [IX_DriverDocuments_DriverId] ON [DriverDocuments] ([DriverId]);
GO


CREATE INDEX [IX_Drivers_CompanyId] ON [Drivers] ([CompanyId]);
GO


CREATE INDEX [IX_Drivers_UserId] ON [Drivers] ([UserId]);
GO


CREATE INDEX [IX_Notifications_UserId] ON [Notifications] ([UserId]);
GO


CREATE INDEX [IX_Payments_BookingId] ON [Payments] ([BookingId]);
GO


CREATE INDEX [IX_PaymentTransactions_PaymentId] ON [PaymentTransactions] ([PaymentId]);
GO


CREATE INDEX [IX_RefreshTokens_UserId] ON [RefreshTokens] ([UserId]);
GO


CREATE INDEX [IX_Refunds_PaymentId] ON [Refunds] ([PaymentId]);
GO


CREATE INDEX [IX_Reviews_BookingId] ON [Reviews] ([BookingId]);
GO


CREATE INDEX [IX_Reviews_UserId] ON [Reviews] ([UserId]);
GO


CREATE UNIQUE INDEX [IX_Roles_RoleName] ON [Roles] ([RoleName]);
GO


CREATE INDEX [IX_Routes_CompanyId] ON [Routes] ([CompanyId]);
GO


CREATE INDEX [IX_Routes_DestinationProvinceId] ON [Routes] ([DestinationProvinceId]);
GO


CREATE INDEX [IX_Routes_OriginProvinceId] ON [Routes] ([OriginProvinceId]);
GO


CREATE INDEX [IX_RouteStops_RouteId] ON [RouteStops] ([RouteId]);
GO


CREATE INDEX [IX_SeatHolds_TripSeatId_Status_HoldExpiresAt] ON [SeatHolds] ([TripSeatId], [Status], [HoldExpiresAt]);
GO


CREATE INDEX [IX_SeatHolds_UserId] ON [SeatHolds] ([UserId]);
GO


CREATE INDEX [IX_SupportRequests_UserId] ON [SupportRequests] ([UserId]);
GO


CREATE INDEX [IX_TicketCheckIns_TicketId] ON [TicketCheckIns] ([TicketId]);
GO


CREATE UNIQUE INDEX [IX_Tickets_BookingDetailId] ON [Tickets] ([BookingDetailId]);
GO


CREATE UNIQUE INDEX [IX_Tickets_QRTokenHash] ON [Tickets] ([QRTokenHash]);
GO


CREATE UNIQUE INDEX [IX_Tickets_TicketCode] ON [Tickets] ([TicketCode]);
GO


CREATE INDEX [IX_TripIncidents_DriverId] ON [TripIncidents] ([DriverId]);
GO


CREATE INDEX [IX_TripIncidents_TripId] ON [TripIncidents] ([TripId]);
GO


CREATE INDEX [IX_TripLocations_DriverId] ON [TripLocations] ([DriverId]);
GO


CREATE INDEX [IX_TripLocations_TripId] ON [TripLocations] ([TripId]);
GO


CREATE INDEX [IX_TripMessages_SenderUserId] ON [TripMessages] ([SenderUserId]);
GO


CREATE INDEX [IX_TripMessages_TripId] ON [TripMessages] ([TripId]);
GO


CREATE INDEX [IX_Trips_BusId] ON [Trips] ([BusId]);
GO


CREATE INDEX [IX_Trips_CompanyId] ON [Trips] ([CompanyId]);
GO


CREATE INDEX [IX_Trips_RouteId_DepartureAt_Status] ON [Trips] ([RouteId], [DepartureAt], [Status]);
GO


CREATE INDEX [IX_TripSeats_BusSeatId] ON [TripSeats] ([BusSeatId]);
GO


CREATE UNIQUE INDEX [IX_TripSeats_TripId_SeatCode] ON [TripSeats] ([TripId], [SeatCode]);
GO


CREATE INDEX [IX_TripStatusHistories_TripId] ON [TripStatusHistories] ([TripId]);
GO


CREATE INDEX [IX_UserDevices_UserId] ON [UserDevices] ([UserId]);
GO


CREATE INDEX [IX_UserRoles_CompanyId] ON [UserRoles] ([CompanyId]);
GO


CREATE INDEX [IX_UserRoles_RoleId] ON [UserRoles] ([RoleId]);
GO


CREATE INDEX [IX_UserRoles_UserId] ON [UserRoles] ([UserId]);
GO


CREATE UNIQUE INDEX [IX_Users_Email] ON [Users] ([Email]);
GO


