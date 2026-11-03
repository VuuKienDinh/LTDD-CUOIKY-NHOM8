using System.Text;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using webAPI.Data;
using webAPI.Hubs;
using webAPI.Services;

namespace webAPI
{
    public class Program
    {
        public static async Task Main(string[] args)
        {
            var builder = WebApplication.CreateBuilder(args);

            var connectionString = builder.Configuration.GetConnectionString("DefaultConnection")
                ?? "Server=KKKK\\SQLEXPRESS;Database=BusTicketBookingDb;Trusted_Connection=True;Encrypt=Mandatory;TrustServerCertificate=True;MultipleActiveResultSets=True";

            builder.Services.AddDbContext<BusBookingDbContext>(options =>
                options.UseSqlServer(connectionString));

            var jwtKey = builder.Configuration["Jwt:Key"] ?? "BusTicketBooking_SuperSecretKey_2026_AtLeast32BytesLong!";
            var jwtIssuer = builder.Configuration["Jwt:Issuer"] ?? "BusTicketBookingApi";
            var jwtAudience = builder.Configuration["Jwt:Audience"] ?? "BusTicketBookingClient";

            builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
                .AddJwtBearer(options =>
                {
                    options.TokenValidationParameters = new TokenValidationParameters
                    {
                        ValidateIssuer = true,
                        ValidateAudience = true,
                        ValidateLifetime = true,
                        ValidateIssuerSigningKey = true,
                        ValidIssuer = jwtIssuer,
                        ValidAudience = jwtAudience,
                        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey))
                    };
                });

            builder.Services.AddAuthorization();

            builder.Services.AddCors(options =>
            {
                options.AddPolicy("AllowFlutter", policy =>
                {
                    policy.SetIsOriginAllowed(_ => true)
                          .AllowAnyHeader()
                          .AllowAnyMethod()
                          .AllowCredentials();
                });
            });

            builder.Services.AddSignalR();
            builder.Services.AddHostedService<SeatHoldCleanupService>();
            builder.Services.AddSingleton<CallSignalingService>();

            builder.Services.AddControllers()
                .AddJsonOptions(options =>
                {
                    options.JsonSerializerOptions.ReferenceHandler = ReferenceHandler.IgnoreCycles;
                    options.JsonSerializerOptions.DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull;
                });
            builder.Services.AddEndpointsApiExplorer();
            builder.Services.AddSwaggerGen(c =>
            {
                c.SwaggerDoc("v1", new OpenApiInfo
                {
                    Title = "BusTicketBooking API (.NET 8 - Multi-tenant)",
                    Version = "v1.0",
                    Description = "Hệ thống đặt vé xe khách trực tuyến đa nhà xe (Flutter - ASP.NET Core Web API - SQL Server - SignalR - VNPay Sandbox)"
                });

                c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
                {
                    Name = "Authorization",
                    Type = SecuritySchemeType.Http,
                    Scheme = "bearer",
                    BearerFormat = "JWT",
                    In = ParameterLocation.Header,
                    Description = "Nhập JWT token nhận được từ /api/auth/login"
                });

                c.AddSecurityRequirement(new OpenApiSecurityRequirement
                {
                    {
                        new OpenApiSecurityScheme
                        {
                            Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" }
                        },
                        Array.Empty<string>()
                    }
                });
            });

            var app = builder.Build();

            // Tự động khởi tạo Database & Seed dữ liệu mẫu trên KKKK\SQLEXPRESS
            using (var scope = app.Services.CreateScope())
            {
                var db = scope.ServiceProvider.GetRequiredService<BusBookingDbContext>();
                var logger = scope.ServiceProvider.GetRequiredService<ILogger<Program>>();
                try
                {
                    await DatabaseSeeder.SeedAsync(db, builder.Configuration);
                    logger.LogInformation("BusTicketBookingDb migrated and seeded successfully on KKKK\\SQLEXPRESS.");
                }
                catch (Exception ex)
                {
                    logger.LogError(ex, "Error migrating/seeding BusTicketBookingDb.");
                }
            }

            app.UseSwagger();
            app.UseSwaggerUI();

            app.UseDefaultFiles();
            app.UseStaticFiles();

            app.UseCors("AllowFlutter");

            app.UseAuthentication();
            app.UseAuthorization();

            app.MapControllers();
            app.MapHub<TripTrackingHub>("/hubs/trip-tracking");

            await app.RunAsync();
        }
    }
}
