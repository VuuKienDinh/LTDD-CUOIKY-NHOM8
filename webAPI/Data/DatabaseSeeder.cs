using Microsoft.EntityFrameworkCore;
using webAPI.Models;
using webAPI.Services;

namespace webAPI.Data
{
    public static class DatabaseSeeder
    {
        public static async Task SeedAsync(BusBookingDbContext db, IConfiguration config)
        {
            if (db.Database.GetMigrations().Any())
            {
                await db.Database.MigrateAsync();
            }
            else
            {
                await db.Database.EnsureCreatedAsync();
            }

            try
            {
                var sqlScript = db.Database.GenerateCreateScript();
                await File.WriteAllTextAsync("Database_BusTicketBooking_Schema.sql", sqlScript);
            }
            catch
            {
                // Ignore if file is locked
            }

            await EnsureAdvancedTablesAndSeedAsync(db);

            if (await db.Roles.AnyAsync())
            {
                return;
            }

            // 1. Roles
            var roles = new List<Role>
            {
                new() { RoleName = RoleNames.Admin, Description = "Quản trị viên nền tảng" },
                new() { RoleName = RoleNames.BusOperator, Description = "Quản lý nhà xe" },
                new() { RoleName = RoleNames.Staff, Description = "Nhân viên nhà xe" },
                new() { RoleName = RoleNames.Driver, Description = "Tài xế vận hành chuyến" },
                new() { RoleName = RoleNames.Customer, Description = "Khách hàng đặt vé" }
            };
            db.Roles.AddRange(roles);
            await db.SaveChangesAsync();

            var roleMap = roles.ToDictionary(r => r.RoleName, r => r.RoleId);

            // 2. Bus Companies
            var futa = new BusCompany
            {
                Name = "Phương Trang (FUTA Bus Lines)",
                TaxCode = "0302241579",
                Address = "80 Trần Hưng Đạo, Quận 1, TP. Hồ Chí Minh",
                Phone = "19006067",
                Email = "hotro@phuongtrang.vn",
                RepresentativeName = "Nguyễn Hoàng Phương",
                Description = "Nhà xe uy tín hàng đầu Việt Nam chuyên tuyến miền Nam - Tây Nguyên - miền Trung.",
                Status = CompanyStatuses.Active,
                AllowCod = true,
                MaxCodSeatsPerBooking = 4,
                SeatHoldMinutes = 10
            };
            var thanhBuoi = new BusCompany
            {
                Name = "Thành Bưởi Limousine",
                TaxCode = "0301988241",
                Address = "266 Lê Hồng Phong, Quận 5, TP. Hồ Chí Minh",
                Phone = "19006079",
                Email = "contact@thanhbuoi.vn",
                RepresentativeName = "Lê Thành Bưởi",
                Description = "Chuyên xe phòng nằm VIP đi Đà Lạt, Cần Thơ.",
                Status = CompanyStatuses.Active,
                AllowCod = true,
                MaxCodSeatsPerBooking = 3,
                SeatHoldMinutes = 10
            };
            var kumho = new BusCompany
            {
                Name = "Kumho Samco Buslines",
                TaxCode = "0305112890",
                Address = "292 Đinh Bộ Lĩnh, Bình Thạnh, TP. Hồ Chí Minh",
                Phone = "19006065",
                Email = "info@kumhosamco.com.vn",
                RepresentativeName = "Park Jin",
                Description = "Nhà xe liên doanh Hàn Quốc chờ duyệt hoạt động.",
                Status = CompanyStatuses.Pending,
                AllowCod = false,
                MaxCodSeatsPerBooking = 2,
                SeatHoldMinutes = 10
            };
            db.BusCompanies.AddRange(futa, thanhBuoi, kumho);
            await db.SaveChangesAsync();

            // 3. Users (Mật khẩu mặc định: 123456)
            var defaultPwd = SecurityHelper.HashPassword("123456");

            var adminUser = new User
            {
                FullName = "Quản Trị Nền Tảng (Admin)",
                Email = "admin@busticket.vn",
                Phone = "0901000001",
                PasswordHash = defaultPwd
            };
            var futaOperator = new User
            {
                FullName = "Nguyễn Quản Lý (Phương Trang)",
                Email = "operator@phuongtrang.vn",
                Phone = "0901000002",
                PasswordHash = defaultPwd
            };
            var futaStaff = new User
            {
                FullName = "Lê Thu Ngân (NV Phương Trang)",
                Email = "staff@phuongtrang.vn",
                Phone = "0901000003",
                PasswordHash = defaultPwd
            };
            var futaDriverUser = new User
            {
                FullName = "Nguyễn Văn Tài (Tài xế FUTA)",
                Email = "driver@phuongtrang.vn",
                Phone = "0901000004",
                PasswordHash = defaultPwd
            };
            var tbOperator = new User
            {
                FullName = "Trần Quản Lý (Thành Bưởi)",
                Email = "operator@thanhbuoi.vn",
                Phone = "0901000005",
                PasswordHash = defaultPwd
            };
            var customerUser = new User
            {
                FullName = "Trần Minh Khách",
                Email = "customer@gmail.vn",
                Phone = "0988123456",
                PasswordHash = defaultPwd
            };

            db.Users.AddRange(adminUser, futaOperator, futaStaff, futaDriverUser, tbOperator, customerUser);
            await db.SaveChangesAsync();

            db.UserRoles.AddRange(
                new UserRole { UserId = adminUser.UserId, RoleId = roleMap[RoleNames.Admin] },
                new UserRole { UserId = futaOperator.UserId, RoleId = roleMap[RoleNames.BusOperator], CompanyId = futa.CompanyId },
                new UserRole { UserId = futaStaff.UserId, RoleId = roleMap[RoleNames.Staff], CompanyId = futa.CompanyId },
                new UserRole { UserId = futaDriverUser.UserId, RoleId = roleMap[RoleNames.Driver], CompanyId = futa.CompanyId },
                new UserRole { UserId = tbOperator.UserId, RoleId = roleMap[RoleNames.BusOperator], CompanyId = thanhBuoi.CompanyId },
                new UserRole { UserId = customerUser.UserId, RoleId = roleMap[RoleNames.Customer] }
            );

            db.CompanyMembers.AddRange(
                new CompanyMember { CompanyId = futa.CompanyId, UserId = futaOperator.UserId, MemberRole = RoleNames.BusOperator },
                new CompanyMember { CompanyId = futa.CompanyId, UserId = futaStaff.UserId, MemberRole = RoleNames.Staff },
                new CompanyMember { CompanyId = thanhBuoi.CompanyId, UserId = tbOperator.UserId, MemberRole = RoleNames.BusOperator }
            );
            await db.SaveChangesAsync();

            // 4. Drivers
            var driver1 = new Driver
            {
                CompanyId = futa.CompanyId,
                UserId = futaDriverUser.UserId,
                FullName = "Nguyễn Văn Tài",
                Phone = "0901000004",
                LicenseNumber = "790123456789",
                LicenseClass = "E",
                LicenseExpiry = DateTime.UtcNow.AddYears(3),
                Status = "Active"
            };
            var driver2 = new Driver
            {
                CompanyId = futa.CompanyId,
                FullName = "Lê Hoàng Nam",
                Phone = "0909222333",
                LicenseNumber = "790987654321",
                LicenseClass = "E",
                LicenseExpiry = DateTime.UtcNow.AddYears(2),
                Status = "Active"
            };
            var driver3 = new Driver
            {
                CompanyId = thanhBuoi.CompanyId,
                FullName = "Phạm Quốc Bảo",
                Phone = "0909444555",
                LicenseNumber = "790555666777",
                LicenseClass = "E",
                LicenseExpiry = DateTime.UtcNow.AddYears(2),
                Status = "Active"
            };
            db.Drivers.AddRange(driver1, driver2, driver3);
            await db.SaveChangesAsync();

            db.DriverDocuments.Add(new DriverDocument
            {
                DriverId = driver1.DriverId,
                Type = "GPLX Hạng E",
                FileUrl = "https://busticket.vn/docs/gplx-driver1.pdf",
                ExpiryDate = driver1.LicenseExpiry,
                Status = "Verified"
            });

            // 5. Buses & BusSeats
            var bus1 = new Bus
            {
                CompanyId = futa.CompanyId,
                PlateNumber = "51B-288.99",
                BusType = "Limousine 20 Phòng VIP",
                BrandModel = "Thaco Mobihome Luxury",
                TotalSeats = 20,
                ManufactureYear = 2025,
                TurnaroundMinutes = 60,
                Status = BusStatuses.Active
            };
            var bus2 = new Bus
            {
                CompanyId = futa.CompanyId,
                PlateNumber = "51B-678.88",
                BusType = "Giường nằm 24 chỗ",
                BrandModel = "Hyundai Universe",
                TotalSeats = 24,
                ManufactureYear = 2024,
                TurnaroundMinutes = 60,
                Status = BusStatuses.Active
            };
            var bus3 = new Bus
            {
                CompanyId = thanhBuoi.CompanyId,
                PlateNumber = "51B-999.11",
                BusType = "Cabin Cung Điện 20 Phòng",
                BrandModel = "KimLong 99",
                TotalSeats = 20,
                ManufactureYear = 2025,
                TurnaroundMinutes = 60,
                Status = BusStatuses.Active
            };
            db.Buses.AddRange(bus1, bus2, bus3);
            await db.SaveChangesAsync();

            static List<BusSeat> CreateSeatsForBus(int busId, int countPerDeck, string seatType, decimal vipSurcharge)
            {
                var list = new List<BusSeat>();
                for (int deck = 1; deck <= 2; deck++)
                {
                    string prefix = deck == 1 ? "A" : "B";
                    for (int i = 1; i <= countPerDeck; i++)
                    {
                        int row = (i - 1) / 2 + 1;
                        int col = (i - 1) % 2 + 1;
                        list.Add(new BusSeat
                        {
                            BusId = busId,
                            SeatCode = $"{prefix}{i:D2}",
                            Deck = deck,
                            Row = row,
                            Column = col,
                            SeatType = i <= 4 ? "VIP" : seatType,
                            PriceSurcharge = i <= 4 ? vipSurcharge : 0,
                            IsActive = true
                        });
                    }
                }
                return list;
            }

            db.BusSeats.AddRange(CreateSeatsForBus(bus1.BusId, 10, "Cabin", 20000));
            db.BusSeats.AddRange(CreateSeatsForBus(bus2.BusId, 12, "Sleeper", 10000));
            db.BusSeats.AddRange(CreateSeatsForBus(bus3.BusId, 10, "Cabin", 30000));
            await db.SaveChangesAsync();

            // 6. Provinces
            var hcm = new Province { Name = "TP. Hồ Chí Minh", Code = "SGN" };
            var dalat = new Province { Name = "Lâm Đồng (Đà Lạt)", Code = "DLI" };
            var nhatrang = new Province { Name = "Khánh Hòa (Nha Trang)", Code = "CXR" };
            var vungtau = new Province { Name = "Bà Rịa - Vũng Tàu", Code = "VTG" };
            var cantho = new Province { Name = "Cần Thơ", Code = "VCA" };
            var phanthiet = new Province { Name = "Bình Thuận (Phan Thiết)", Code = "PTH" };
            db.Provinces.AddRange(hcm, dalat, nhatrang, vungtau, cantho, phanthiet);
            await db.SaveChangesAsync();

            // 7. Routes & RouteStops
            var routeHcmDlFuta = new Models.Route
            {
                CompanyId = futa.CompanyId,
                OriginProvinceId = hcm.ProvinceId,
                DestinationProvinceId = dalat.ProvinceId,
                Name = "TP. Hồ Chí Minh → Đà Lạt (Cao tốc Dầu Giây)",
                DistanceKm = 310,
                EstimatedDurationMinutes = 390
            };
            var routeDlHcmFuta = new Models.Route
            {
                CompanyId = futa.CompanyId,
                OriginProvinceId = dalat.ProvinceId,
                DestinationProvinceId = hcm.ProvinceId,
                Name = "Đà Lạt → TP. Hồ Chí Minh",
                DistanceKm = 310,
                EstimatedDurationMinutes = 390
            };
            var routeHcmNtFuta = new Models.Route
            {
                CompanyId = futa.CompanyId,
                OriginProvinceId = hcm.ProvinceId,
                DestinationProvinceId = nhatrang.ProvinceId,
                Name = "TP. Hồ Chí Minh → Nha Trang (Cao tốc Vĩnh Hảo)",
                DistanceKm = 420,
                EstimatedDurationMinutes = 450
            };
            var routeHcmDlTb = new Models.Route
            {
                CompanyId = thanhBuoi.CompanyId,
                OriginProvinceId = hcm.ProvinceId,
                DestinationProvinceId = dalat.ProvinceId,
                Name = "TP. Hồ Chí Minh → Đà Lạt (Cung Điện Di Động)",
                DistanceKm = 310,
                EstimatedDurationMinutes = 380
            };
            db.Routes.AddRange(routeHcmDlFuta, routeDlHcmFuta, routeHcmNtFuta, routeHcmDlTb);
            await db.SaveChangesAsync();

            var stopBxMienDong = new RouteStop
            {
                RouteId = routeHcmDlFuta.RouteId,
                StopName = "Bến xe Miền Đông Mới",
                Address = "501 Hoàng Hữu Nam, TP. Thủ Đức, TP.HCM",
                Sequence = 1,
                OffsetMinutes = 0,
                Surcharge = 0,
                Latitude = 10.8794,
                Longitude = 106.8142,
                StopType = StopTypes.Pickup
            };
            var stopHangXanh = new RouteStop
            {
                RouteId = routeHcmDlFuta.RouteId,
                StopName = "VP Hàng Xanh (Đón khách)",
                Address = "486 Điện Biên Phủ, Bình Thạnh, TP.HCM",
                Sequence = 2,
                OffsetMinutes = 25,
                Surcharge = 0,
                Latitude = 10.8015,
                Longitude = 106.7114,
                StopType = StopTypes.Pickup
            };
            var stopBaoLoc = new RouteStop
            {
                RouteId = routeHcmDlFuta.RouteId,
                StopName = "Trạm dừng Bảo Lộc",
                Address = "280 Trần Phú, TP. Bảo Lộc, Lâm Đồng",
                Sequence = 3,
                OffsetMinutes = 210,
                Surcharge = 0,
                Latitude = 11.5479,
                Longitude = 107.8077,
                StopType = StopTypes.Dropoff
            };
            var stopBxDaLat = new RouteStop
            {
                RouteId = routeHcmDlFuta.RouteId,
                StopName = "Bến xe Liên tỉnh Đà Lạt",
                Address = "01 Tô Hiến Thành, Phường 3, TP. Đà Lạt",
                Sequence = 4,
                OffsetMinutes = 390,
                Surcharge = 0,
                Latitude = 11.9267,
                Longitude = 108.4451,
                StopType = StopTypes.Dropoff
            };
            var stopTrungChuyenDaLat = new RouteStop
            {
                RouteId = routeHcmDlFuta.RouteId,
                StopName = "Trung chuyển Nội ô Chợ Đà Lạt (+15k)",
                Address = "Khu Hòa Bình, Phường 1, TP. Đà Lạt",
                Sequence = 5,
                OffsetMinutes = 410,
                Surcharge = 15000,
                Latitude = 11.9428,
                Longitude = 108.4369,
                StopType = StopTypes.Dropoff
            };

            db.RouteStops.AddRange(stopBxMienDong, stopHangXanh, stopBaoLoc, stopBxDaLat, stopTrungChuyenDaLat);

            // Stops for other routes
            db.RouteStops.AddRange(
                new RouteStop { RouteId = routeDlHcmFuta.RouteId, StopName = "Bến xe Liên tỉnh Đà Lạt", Address = "01 Tô Hiến Thành, Đà Lạt", Sequence = 1, OffsetMinutes = 0, Latitude = 11.9267, Longitude = 108.4451, StopType = StopTypes.Pickup },
                new RouteStop { RouteId = routeDlHcmFuta.RouteId, StopName = "Bến xe Miền Đông Mới", Address = "Thủ Đức, TP.HCM", Sequence = 2, OffsetMinutes = 390, Latitude = 10.8794, Longitude = 106.8142, StopType = StopTypes.Dropoff },
                new RouteStop { RouteId = routeHcmNtFuta.RouteId, StopName = "Bến xe Miền Đông Mới", Address = "Thủ Đức, TP.HCM", Sequence = 1, OffsetMinutes = 0, Latitude = 10.8794, Longitude = 106.8142, StopType = StopTypes.Pickup },
                new RouteStop { RouteId = routeHcmNtFuta.RouteId, StopName = "Bến xe Phía Nam Nha Trang", Address = "Đường 23/10, Vĩnh Trung, Nha Trang", Sequence = 2, OffsetMinutes = 450, Latitude = 12.2488, Longitude = 109.1462, StopType = StopTypes.Dropoff },
                new RouteStop { RouteId = routeHcmDlTb.RouteId, StopName = "VP Lê Hồng Phong Q.5", Address = "266 Lê Hồng Phong, Q.5, TP.HCM", Sequence = 1, OffsetMinutes = 0, Latitude = 10.7611, Longitude = 106.6768, StopType = StopTypes.Pickup },
                new RouteStop { RouteId = routeHcmDlTb.RouteId, StopName = "VP Phan Bội Châu Đà Lạt", Address = "55 Phan Bội Châu, Đà Lạt", Sequence = 2, OffsetMinutes = 380, Latitude = 11.9435, Longitude = 108.4382, StopType = StopTypes.Dropoff }
            );
            await db.SaveChangesAsync();

            // 8. Trips & TripSeats
            var today = DateTime.UtcNow.Date;
            var tripsToCreate = new List<(Models.Route route, Bus bus, Driver driver, DateTime dep, decimal price, string status)>
            {
                (routeHcmDlFuta, bus1, driver1, today.AddHours(22), 350000m, TripStatuses.Boarding),
                (routeHcmDlFuta, bus2, driver2, today.AddDays(1).AddHours(8), 290000m, TripStatuses.Scheduled),
                (routeHcmDlFuta, bus1, driver1, today.AddDays(1).AddHours(22), 350000m, TripStatuses.Scheduled),
                (routeHcmDlTb, bus3, driver3, today.AddDays(1).AddHours(23), 420000m, TripStatuses.Scheduled),
                (routeHcmNtFuta, bus2, driver2, today.AddDays(1).AddHours(21), 320000m, TripStatuses.Scheduled),
                (routeDlHcmFuta, bus1, driver1, today.AddDays(2).AddHours(13), 350000m, TripStatuses.Scheduled)
            };

            var createdTrips = new List<Trip>();
            foreach (var item in tripsToCreate)
            {
                var trip = new Trip
                {
                    CompanyId = item.route.CompanyId,
                    RouteId = item.route.RouteId,
                    BusId = item.bus.BusId,
                    DepartureAt = item.dep,
                    ArrivalEstimate = item.dep.AddMinutes(item.route.EstimatedDurationMinutes),
                    BasePrice = item.price,
                    Status = item.status
                };
                db.Trips.Add(trip);
                await db.SaveChangesAsync();

                var busSeats = await db.BusSeats.Where(bs => bs.BusId == item.bus.BusId && bs.IsActive).ToListAsync();
                foreach (var bs in busSeats)
                {
                    db.TripSeats.Add(new TripSeat
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

                db.DriverAssignments.Add(new DriverAssignment
                {
                    TripId = trip.TripId,
                    DriverId = item.driver.DriverId,
                    Role = "Primary"
                });

                db.TripStatusHistories.Add(new TripStatusHistory
                {
                    TripId = trip.TripId,
                    OldStatus = TripStatuses.Draft,
                    NewStatus = item.status,
                    Reason = "Khởi tạo lịch chạy mẫu"
                });

                createdTrips.Add(trip);
                await db.SaveChangesAsync();
            }

            // 9. Seed sample Bookings, Payments, Tickets & GPS Location for the first Trip so all screens have immediate demo data!
            var firstTrip = createdTrips[0];
            var firstTripSeats = await db.TripSeats.Where(ts => ts.TripId == firstTrip.TripId).OrderBy(ts => ts.SeatCode).ToListAsync();

            // Sample Booking 1: Paid via VNPay (Seats A01, A02)
            var seatA01 = firstTripSeats[0];
            var seatA02 = firstTripSeats[1];
            seatA01.SeatStatus = SeatStatuses.Booked;
            seatA02.SeatStatus = SeatStatuses.Booked;

            var booking1 = new Booking
            {
                UserId = customerUser.UserId,
                TripId = firstTrip.TripId,
                BookingCode = "BTB-20261103-001",
                ContactName = customerUser.FullName,
                ContactPhone = customerUser.Phone,
                ContactEmail = customerUser.Email,
                SubTotal = seatA01.CurrentPrice + seatA02.CurrentPrice,
                SurchargeTotal = 0,
                DiscountAmount = 0,
                TotalAmount = seatA01.CurrentPrice + seatA02.CurrentPrice,
                Status = BookingStatuses.Confirmed,
                ExpiresAt = DateTime.UtcNow.AddMinutes(15)
            };
            db.Bookings.Add(booking1);
            await db.SaveChangesAsync();

            var detail1 = new BookingDetail
            {
                BookingId = booking1.BookingId,
                TripSeatId = seatA01.TripSeatId,
                SeatCode = seatA01.SeatCode,
                PassengerName = "Trần Minh Khách",
                PassengerPhone = "0988123456",
                PickupStopId = stopBxMienDong.RouteStopId,
                DropoffStopId = stopBxDaLat.RouteStopId,
                UnitPrice = seatA01.CurrentPrice,
                Surcharge = 0,
                IsActiveBooking = true
            };
            var detail2 = new BookingDetail
            {
                BookingId = booking1.BookingId,
                TripSeatId = seatA02.TripSeatId,
                SeatCode = seatA02.SeatCode,
                PassengerName = "Nguyễn Thị Lan",
                PassengerPhone = "0988654321",
                PickupStopId = stopHangXanh.RouteStopId,
                DropoffStopId = stopBxDaLat.RouteStopId,
                UnitPrice = seatA02.CurrentPrice,
                Surcharge = 0,
                IsActiveBooking = true
            };
            db.BookingDetails.AddRange(detail1, detail2);
            await db.SaveChangesAsync();

            var payment1 = new Payment
            {
                BookingId = booking1.BookingId,
                Method = PaymentMethods.VNPay,
                Amount = booking1.TotalAmount,
                Status = PaymentStatuses.Paid,
                PaidAt = DateTime.UtcNow.AddMinutes(-30)
            };
            db.Payments.Add(payment1);
            await db.SaveChangesAsync();

            db.PaymentTransactions.Add(new PaymentTransaction
            {
                PaymentId = payment1.PaymentId,
                ProviderRef = "VNP14589201",
                TxnRef = booking1.BookingCode,
                ResponseCode = "00",
                RawStatus = "Success",
                SignatureValid = true
            });

            var qrSecret = config["Jwt:Key"] ?? "BusTicketBooking_SuperSecretKey_2026_AtLeast32BytesLong!";
            var qr1 = SecurityHelper.GenerateTicketQr(detail1.BookingDetailId, firstTrip.TripId, detail1.SeatCode, qrSecret);
            var qr2 = SecurityHelper.GenerateTicketQr(detail2.BookingDetailId, firstTrip.TripId, detail2.SeatCode, qrSecret);

            db.Tickets.AddRange(
                new Ticket
                {
                    BookingDetailId = detail1.BookingDetailId,
                    TripId = firstTrip.TripId,
                    TicketCode = $"TKT-{firstTrip.TripId}-{detail1.SeatCode}",
                    QRDisplayPayload = qr1.RawQRPayload,
                    QRTokenHash = qr1.QRTokenHash,
                    Status = TicketStatuses.Active
                },
                new Ticket
                {
                    BookingDetailId = detail2.BookingDetailId,
                    TripId = firstTrip.TripId,
                    TicketCode = $"TKT-{firstTrip.TripId}-{detail2.SeatCode}",
                    QRDisplayPayload = qr2.RawQRPayload,
                    QRTokenHash = qr2.QRTokenHash,
                    Status = TicketStatuses.Active
                }
            );

            // Sample Booking 2: COD Confirmed but Unpaid (Seat A03)
            var seatA03 = firstTripSeats[2];
            seatA03.SeatStatus = SeatStatuses.Booked;

            var booking2 = new Booking
            {
                UserId = customerUser.UserId,
                TripId = firstTrip.TripId,
                BookingCode = "BTB-20261103-002",
                ContactName = customerUser.FullName,
                ContactPhone = customerUser.Phone,
                ContactEmail = customerUser.Email,
                SubTotal = seatA03.CurrentPrice,
                SurchargeTotal = 15000,
                DiscountAmount = 0,
                TotalAmount = seatA03.CurrentPrice + 15000,
                Status = BookingStatuses.Confirmed,
                ExpiresAt = DateTime.UtcNow.AddMinutes(15)
            };
            db.Bookings.Add(booking2);
            await db.SaveChangesAsync();

            var detail3 = new BookingDetail
            {
                BookingId = booking2.BookingId,
                TripSeatId = seatA03.TripSeatId,
                SeatCode = seatA03.SeatCode,
                PassengerName = "Trần Minh Khách (COD)",
                PassengerPhone = "0988123456",
                PickupStopId = stopBxMienDong.RouteStopId,
                DropoffStopId = stopTrungChuyenDaLat.RouteStopId,
                UnitPrice = seatA03.CurrentPrice,
                Surcharge = 15000,
                IsActiveBooking = true
            };
            db.BookingDetails.Add(detail3);
            await db.SaveChangesAsync();

            var payment2 = new Payment
            {
                BookingId = booking2.BookingId,
                Method = PaymentMethods.COD,
                Amount = booking2.TotalAmount,
                Status = PaymentStatuses.Unpaid
            };
            db.Payments.Add(payment2);
            await db.SaveChangesAsync();

            var qr3 = SecurityHelper.GenerateTicketQr(detail3.BookingDetailId, firstTrip.TripId, detail3.SeatCode, qrSecret);
            db.Tickets.Add(new Ticket
            {
                BookingDetailId = detail3.BookingDetailId,
                TripId = firstTrip.TripId,
                TicketCode = $"TKT-{firstTrip.TripId}-{detail3.SeatCode}",
                QRDisplayPayload = qr3.RawQRPayload,
                QRTokenHash = qr3.QRTokenHash,
                Status = TicketStatuses.Active
            });

            // Live GPS location for firstTrip
            db.TripLiveLocations.Add(new TripLiveLocation
            {
                TripId = firstTrip.TripId,
                DriverId = driver1.DriverId,
                Latitude = 10.8794,
                Longitude = 106.8142,
                SpeedKmh = 45.5,
                Accuracy = 5.0,
                UpdatedAt = DateTime.UtcNow
            });
            db.TripLocations.Add(new TripLocation
            {
                TripId = firstTrip.TripId,
                DriverId = driver1.DriverId,
                Latitude = 10.8794,
                Longitude = 106.8142,
                SpeedKmh = 45.5,
                Accuracy = 5.0,
                RecordedAt = DateTime.UtcNow
            });

            // Sample Notification
            db.Notifications.AddRange(
                new Notification
                {
                    UserId = customerUser.UserId,
                    Title = "Đặt vé thành công BTB-20261103-001",
                    Content = "Vé đi Đà Lạt (Ghế A01, A02) đã được thanh toán qua VNPay và phát hành mã QR.",
                    Type = "BookingConfirmed",
                    ReferenceId = booking1.BookingId
                },
                new Notification
                {
                    UserId = customerUser.UserId,
                    Title = "Chuyến xe TP.HCM → Đà Lạt đang đón khách",
                    Content = "Chuyến xe 51B-288.99 đã chuyển sang trạng thái Boarding tại Bến xe Miền Đông Mới.",
                    Type = "TripStatus",
                    ReferenceId = firstTrip.TripId
                }
            );

            await db.SaveChangesAsync();
            await EnsureAdvancedTablesAndSeedAsync(db);
        }

        private static async Task EnsureAdvancedTablesAndSeedAsync(BusBookingDbContext db)
        {
            const string createTablesSql = @"
IF OBJECT_ID('dbo.Promotions', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[Promotions] (
        [PromotionId] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [Code] NVARCHAR(50) NOT NULL,
        [Description] NVARCHAR(250) NOT NULL,
        [DiscountType] NVARCHAR(20) NOT NULL,
        [DiscountValue] DECIMAL(18,2) NOT NULL,
        [MaxDiscountAmount] DECIMAL(18,2) NOT NULL,
        [UsageLimit] INT NOT NULL,
        [UsedCount] INT NOT NULL,
        [ExpiresAt] DATETIME2 NOT NULL,
        [IsActive] BIT NOT NULL,
        [CreatedAt] DATETIME2 NOT NULL
    );
END;

IF OBJECT_ID('dbo.CargoShipments', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[CargoShipments] (
        [ShipmentId] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [TripId] INT NOT NULL,
        [CompanyId] INT NOT NULL,
        [TrackingCode] NVARCHAR(40) NOT NULL,
        [SenderName] NVARCHAR(120) NOT NULL,
        [SenderPhone] NVARCHAR(30) NOT NULL,
        [ReceiverName] NVARCHAR(120) NOT NULL,
        [ReceiverPhone] NVARCHAR(30) NOT NULL,
        [Description] NVARCHAR(300) NOT NULL,
        [WeightKg] FLOAT NOT NULL,
        [FeeAmount] DECIMAL(18,2) NOT NULL,
        [Status] NVARCHAR(30) NOT NULL,
        [CreatedAt] DATETIME2 NOT NULL
    );
END;

IF OBJECT_ID('dbo.TripWaitlists', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[TripWaitlists] (
        [WaitlistId] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [TripId] INT NOT NULL,
        [UserId] INT NOT NULL,
        [CustomerName] NVARCHAR(120) NOT NULL,
        [CustomerPhone] NVARCHAR(30) NOT NULL,
        [SeatCountRequested] INT NOT NULL,
        [Status] NVARCHAR(30) NOT NULL,
        [CreatedAt] DATETIME2 NOT NULL,
        [NotifiedAt] DATETIME2 NULL
    );
END;

IF OBJECT_ID('dbo.ShuttleRequests', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[ShuttleRequests] (
        [ShuttleRequestId] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [BookingId] INT NOT NULL,
        [TripId] INT NOT NULL,
        [CompanyId] INT NOT NULL,
        [PassengerName] NVARCHAR(120) NOT NULL,
        [PassengerPhone] NVARCHAR(30) NOT NULL,
        [PickupAddress] NVARCHAR(300) NOT NULL,
        [DropoffAddress] NVARCHAR(300) NULL,
        [PickupArea] NVARCHAR(100) NOT NULL,
        [ShuttlePlate] NVARCHAR(100) NULL,
        [Status] NVARCHAR(30) NOT NULL,
        [CreatedAt] DATETIME2 NOT NULL
    );
END;

IF OBJECT_ID('dbo.SavedCompanions', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[SavedCompanions] (
        [CompanionId] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [UserId] INT NOT NULL,
        [FullName] NVARCHAR(120) NOT NULL,
        [Phone] NVARCHAR(30) NOT NULL,
        [Relationship] NVARCHAR(60) NOT NULL,
        [CreatedAt] DATETIME2 NOT NULL
    );
END;

IF OBJECT_ID('dbo.InvoiceRequests', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[InvoiceRequests] (
        [InvoiceRequestId] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [BookingId] INT NOT NULL,
        [BookingCode] NVARCHAR(40) NOT NULL,
        [TaxCode] NVARCHAR(40) NOT NULL,
        [CompanyName] NVARCHAR(200) NOT NULL,
        [CompanyAddress] NVARCHAR(300) NOT NULL,
        [BuyerEmail] NVARCHAR(150) NOT NULL,
        [TotalAmount] DECIMAL(18,2) NOT NULL,
        [VatAmount] DECIMAL(18,2) NOT NULL,
        [InvoiceNumber] NVARCHAR(60) NOT NULL,
        [Status] NVARCHAR(30) NOT NULL,
        [IssuedAt] DATETIME2 NOT NULL
    );
END;

IF OBJECT_ID('dbo.TripExpenses', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[TripExpenses] (
        [ExpenseId] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [TripId] INT NOT NULL,
        [CompanyId] INT NOT NULL,
        [Category] NVARCHAR(60) NOT NULL,
        [Amount] DECIMAL(18,2) NOT NULL,
        [Note] NVARCHAR(300) NOT NULL,
        [RecordedByUserId] INT NOT NULL,
        [CreatedAt] DATETIME2 NOT NULL
    );
END;

IF OBJECT_ID('dbo.TripSafetyChecks', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[TripSafetyChecks] (
        [SafetyCheckId] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [TripId] INT NOT NULL,
        [DriverId] INT NOT NULL,
        [BrakesOk] BIT NOT NULL,
        [TiresOk] BIT NOT NULL,
        [FireExtinguisherOk] BIT NOT NULL,
        [DashcamOk] BIT NOT NULL,
        [ZeroAlcoholConfirmed] BIT NOT NULL,
        [Note] NVARCHAR(300) NULL,
        [CheckedAt] DATETIME2 NOT NULL
    );
END;

IF OBJECT_ID('dbo.TripMessages', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[TripMessages] (
        [MessageId] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [TripId] INT NOT NULL,
        [BookingId] INT NULL,
        [SenderUserId] INT NOT NULL,
        [SenderName] NVARCHAR(100) NOT NULL,
        [SenderRole] NVARCHAR(30) NOT NULL,
        [Content] NVARCHAR(1000) NOT NULL,
        [IsRead] BIT NOT NULL DEFAULT 0,
        [CreatedAt] DATETIME2 NOT NULL
    );
END;";
            await db.Database.ExecuteSqlRawAsync(createTablesSql);

            if (!await db.Promotions.AnyAsync())
            {
                db.Promotions.AddRange(
                    new Promotion
                    {
                        Code = "FUTA50K",
                        Description = "Giảm trực tiếp 50.000đ cho mọi tuyến xe Phương Trang / Thành Bưởi",
                        DiscountType = "Fixed",
                        DiscountValue = 50000,
                        MaxDiscountAmount = 50000,
                        UsageLimit = 500,
                        UsedCount = 12,
                        ExpiresAt = DateTime.UtcNow.AddDays(60),
                        IsActive = true
                    },
                    new Promotion
                    {
                        Code = "SINHVIEN30K",
                        Description = "Ưu đãi Sinh viên giảm 30.000đ giá vé",
                        DiscountType = "Fixed",
                        DiscountValue = 30000,
                        MaxDiscountAmount = 30000,
                        UsageLimit = 300,
                        UsedCount = 8,
                        ExpiresAt = DateTime.UtcNow.AddDays(60),
                        IsActive = true
                    },
                    new Promotion
                    {
                        Code = "GIAM10",
                        Description = "Giảm 10% tổng hóa đơn (Tối đa 60.000đ)",
                        DiscountType = "Percent",
                        DiscountValue = 10,
                        MaxDiscountAmount = 60000,
                        UsageLimit = 200,
                        UsedCount = 5,
                        ExpiresAt = DateTime.UtcNow.AddDays(45),
                        IsActive = true
                    },
                    new Promotion
                    {
                        Code = "VIP100K",
                        Description = "Ưu đãi Hạng Vàng / Kim Cương giảm 100.000đ cho đơn khứ hồi hoặc nhóm",
                        DiscountType = "Fixed",
                        DiscountValue = 100000,
                        MaxDiscountAmount = 100000,
                        UsageLimit = 100,
                        UsedCount = 2,
                        ExpiresAt = DateTime.UtcNow.AddDays(90),
                        IsActive = true
                    }
                );
                await db.SaveChangesAsync();
            }

            if (!await db.CargoShipments.AnyAsync())
            {
                var firstTrip = await db.Trips.OrderBy(t => t.TripId).FirstOrDefaultAsync();
                if (firstTrip != null)
                {
                    db.CargoShipments.AddRange(
                        new CargoShipment
                        {
                            TripId = firstTrip.TripId,
                            CompanyId = firstTrip.CompanyId,
                            TrackingCode = "PKG-20261103-01",
                            SenderName = "Trần Minh Khoa",
                            SenderPhone = "0903111222",
                            ReceiverName = "Nguyễn Thị Lan (Đà Lạt)",
                            ReceiverPhone = "0918333444",
                            Description = "Thùng quà đặc sản & Tài liệu hợp đồng niêm phong",
                            WeightKg = 4.5,
                            FeeAmount = 80000,
                            Status = "InTransit"
                        },
                        new CargoShipment
                        {
                            TripId = firstTrip.TripId,
                            CompanyId = firstTrip.CompanyId,
                            TrackingCode = "PKG-20261103-02",
                            SenderName = "Lê Hoàng Nam",
                            SenderPhone = "0909555666",
                            ReceiverName = "Phạm Văn Hải",
                            ReceiverPhone = "0988777999",
                            Description = "Linh kiện máy tính đóng hộp xốp chống sốc",
                            WeightKg = 2.0,
                            FeeAmount = 60000,
                            Status = "Received"
                        }
                    );
                    await db.SaveChangesAsync();
                }
            }

            // Seed Phase 2 tables if empty
            var customer = await db.Users.FirstOrDefaultAsync(u => u.Email == "khachhang@gmail.com");
            var trip1 = await db.Trips.OrderBy(t => t.TripId).FirstOrDefaultAsync();
            var booking1 = await db.Bookings.OrderBy(b => b.BookingId).FirstOrDefaultAsync();
            var driver1 = await db.Drivers.OrderBy(d => d.DriverId).FirstOrDefaultAsync();

            if (customer != null && !await db.SavedCompanions.AnyAsync())
            {
                db.SavedCompanions.AddRange(
                    new SavedCompanion
                    {
                        UserId = customer.UserId,
                        FullName = "Nguyễn Thị Ngọc Ánh (Vợ)",
                        Phone = "0909888777",
                        Relationship = "Gia đình"
                    },
                    new SavedCompanion
                    {
                        UserId = customer.UserId,
                        FullName = "Lê Minh Hoàng (Đồng nghiệp)",
                        Phone = "0912333444",
                        Relationship = "Đồng nghiệp"
                    }
                );
                await db.SaveChangesAsync();
            }

            if (trip1 != null && booking1 != null && !await db.ShuttleRequests.AnyAsync())
            {
                db.ShuttleRequests.Add(new ShuttleRequest
                {
                    BookingId = booking1.BookingId,
                    TripId = trip1.TripId,
                    CompanyId = trip1.CompanyId,
                    PassengerName = booking1.ContactName,
                    PassengerPhone = booking1.ContactPhone,
                    PickupAddress = "268 Lý Thường Kiệt, Quận 10, TP.HCM",
                    DropoffAddress = "Khách sạn TTC Ngọc Lan, 42 Nguyễn Chí Thanh, Đà Lạt",
                    PickupArea = "Quận 10 / Nội thành",
                    ShuttlePlate = "51B-999.16 (Ford Transit 16 chỗ)",
                    Status = "Assigned"
                });
                await db.SaveChangesAsync();
            }

            if (trip1 != null && !await db.TripExpenses.AnyAsync())
            {
                db.TripExpenses.AddRange(
                    new TripExpense
                    {
                        TripId = trip1.TripId,
                        CompanyId = trip1.CompanyId,
                        Category = "Fuel",
                        Amount = 1250000,
                        Note = "Đổ dầu Diesel chặng TP.HCM - Đà Lạt (65 lít)",
                        RecordedByUserId = 1
                    },
                    new TripExpense
                    {
                        TripId = trip1.TripId,
                        CompanyId = trip1.CompanyId,
                        Category = "BOT",
                        Amount = 240000,
                        Note = "Vé trạm thu phí cao tốc Long Thành - Dầu Giây & Liên Khương",
                        RecordedByUserId = 1
                    }
                );
                await db.SaveChangesAsync();
            }

            if (trip1 != null && driver1 != null && !await db.TripSafetyChecks.AnyAsync())
            {
                db.TripSafetyChecks.Add(new TripSafetyCheck
                {
                    TripId = trip1.TripId,
                    DriverId = driver1.DriverId,
                    BrakesOk = true,
                    TiresOk = true,
                    FireExtinguisherOk = true,
                    DashcamOk = true,
                    ZeroAlcoholConfirmed = true,
                    Note = "Đã kiểm tra áp suất lốp, hệ thống phanh ABS, camera hành trình và đo nồng độ cồn = 0.00 mg/L trước giờ xuất bến."
                });
                await db.SaveChangesAsync();
            }
        }
    }
}
