using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.IdentityModel.Tokens;
using webAPI.Models;

namespace webAPI.Services
{
    public static class SecurityHelper
    {
        public static string HashPassword(string password)
        {
            byte[] salt = RandomNumberGenerator.GetBytes(16);
            byte[] hash = Rfc2898DeriveBytes.Pbkdf2(
                Encoding.UTF8.GetBytes(password),
                salt,
                100_000,
                HashAlgorithmName.SHA256,
                32);
            return $"{Convert.ToBase64String(salt)}.{Convert.ToBase64String(hash)}";
        }

        public static bool VerifyPassword(string password, string storedHash)
        {
            var parts = storedHash.Split('.');
            if (parts.Length != 2) return false;
            byte[] salt = Convert.FromBase64String(parts[0]);
            byte[] expectedHash = Convert.FromBase64String(parts[1]);
            byte[] actualHash = Rfc2898DeriveBytes.Pbkdf2(
                Encoding.UTF8.GetBytes(password),
                salt,
                100_000,
                HashAlgorithmName.SHA256,
                32);
            return CryptographicOperations.FixedTimeEquals(actualHash, expectedHash);
        }

        public static string ComputeSha256(string raw)
        {
            byte[] bytes = SHA256.HashData(Encoding.UTF8.GetBytes(raw));
            return Convert.ToHexString(bytes).ToLowerInvariant();
        }

        public static string ComputeHmacSha512(string key, string data)
        {
            using var hmac = new HMACSHA512(Encoding.UTF8.GetBytes(key));
            byte[] bytes = hmac.ComputeHash(Encoding.UTF8.GetBytes(data));
            return Convert.ToHexString(bytes).ToLowerInvariant();
        }

        public static string GenerateJwtToken(User user, IEnumerable<string> roles, int? companyId, int? driverId, IConfiguration config)
        {
            var jwtKey = config["Jwt:Key"] ?? "BusTicketBooking_SuperSecretKey_2026_AtLeast32BytesLong!";
            var issuer = config["Jwt:Issuer"] ?? "BusTicketBookingApi";
            var audience = config["Jwt:Audience"] ?? "BusTicketBookingClient";

            var claims = new List<Claim>
            {
                new Claim(ClaimTypes.NameIdentifier, user.UserId.ToString()),
                new Claim(ClaimTypes.Email, user.Email),
                new Claim(ClaimTypes.Name, user.FullName),
                new Claim("phone", user.Phone)
            };

            if (companyId.HasValue)
            {
                claims.Add(new Claim("companyId", companyId.Value.ToString()));
            }
            if (driverId.HasValue)
            {
                claims.Add(new Claim("driverId", driverId.Value.ToString()));
            }

            foreach (var role in roles.Distinct())
            {
                claims.Add(new Claim(ClaimTypes.Role, role));
            }

            var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey));
            var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

            var token = new JwtSecurityToken(
                issuer: issuer,
                audience: audience,
                claims: claims,
                expires: DateTime.UtcNow.AddHours(8),
                signingCredentials: creds);

            return new JwtSecurityTokenHandler().WriteToken(token);
        }

        public static (string RawQRPayload, string QRTokenHash) GenerateTicketQr(int bookingDetailId, int tripId, string seatCode, string secret)
        {
            var nonce = Convert.ToHexString(RandomNumberGenerator.GetBytes(8));
            var rawData = $"BTB|{tripId}|{bookingDetailId}|{seatCode}|{nonce}";
            var sig = ComputeHmacSha512(secret, rawData)[..24].ToUpperInvariant();
            var payload = $"{rawData}|{sig}";
            var hash = ComputeSha256(payload);
            return (payload, hash);
        }
    }
}

