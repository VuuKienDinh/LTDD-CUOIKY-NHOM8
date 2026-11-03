using System.Collections.Concurrent;

namespace webAPI.Services
{
    public class CallSession
    {
        public string CallId { get; set; } = Guid.NewGuid().ToString("N");
        public int TripId { get; set; }
        public int CallerUserId { get; set; }
        public string CallerName { get; set; } = string.Empty;
        public string CallerRole { get; set; } = "Customer"; // Customer, Driver
        public string TargetName { get; set; } = string.Empty;
        public string Status { get; set; } = "Ringing"; // Ringing, Connected, Ended, Rejected
        public DateTime StartedAt { get; set; } = DateTime.UtcNow;
        public DateTime? ConnectedAt { get; set; }
        public DateTime? EndedAt { get; set; }
        public int DurationSeconds => ConnectedAt.HasValue
            ? (int)((EndedAt ?? DateTime.UtcNow) - ConnectedAt.Value).TotalSeconds
            : 0;

        // WebRTC Voice Signaling Data
        public string? OfferSdp { get; set; }
        public string? AnswerSdp { get; set; }
        public List<string> CallerCandidates { get; set; } = new();
        public List<string> CalleeCandidates { get; set; } = new();
    }

    public class CallSignalingService
    {
        private readonly ConcurrentDictionary<int, CallSession> _activeCalls = new();

        public CallSession InitiateCall(int tripId, int callerUserId, string callerName, string callerRole, string targetName, string? offerSdp = null)
        {
            var session = new CallSession
            {
                TripId = tripId,
                CallerUserId = callerUserId,
                CallerName = callerName,
                CallerRole = callerRole,
                TargetName = targetName,
                Status = "Ringing",
                StartedAt = DateTime.UtcNow,
                OfferSdp = offerSdp
            };
            _activeCalls[tripId] = session;
            return session;
        }

        public CallSession? GetActiveCall(int tripId)
        {
            if (_activeCalls.TryGetValue(tripId, out var session))
            {
                // Auto-cleanup stale calls older than 5 minutes
                if ((DateTime.UtcNow - session.StartedAt).TotalMinutes > 5 && session.Status != "Connected")
                {
                    _activeCalls.TryRemove(tripId, out _);
                    return null;
                }
                return session;
            }
            return null;
        }

        public CallSession? AnswerCall(int tripId, string callId, string? answerSdp = null)
        {
            if (_activeCalls.TryGetValue(tripId, out var session) && session.CallId == callId)
            {
                session.Status = "Connected";
                session.ConnectedAt = DateTime.UtcNow;
                if (!string.IsNullOrEmpty(answerSdp))
                {
                    session.AnswerSdp = answerSdp;
                }
                return session;
            }
            return null;
        }

        public bool AddIceCandidate(int tripId, string callId, string candidate, bool isCaller)
        {
            if (_activeCalls.TryGetValue(tripId, out var session) && session.CallId == callId)
            {
                if (isCaller)
                {
                    lock (session.CallerCandidates)
                    {
                        if (!session.CallerCandidates.Contains(candidate))
                            session.CallerCandidates.Add(candidate);
                    }
                }
                else
                {
                    lock (session.CalleeCandidates)
                    {
                        if (!session.CalleeCandidates.Contains(candidate))
                            session.CalleeCandidates.Add(candidate);
                    }
                }
                return true;
            }
            return false;
        }

        public CallSession? EndCall(int tripId, string callId, bool isReject = false)
        {
            if (_activeCalls.TryGetValue(tripId, out var session) && session.CallId == callId)
            {
                session.Status = isReject ? "Rejected" : "Ended";
                session.EndedAt = DateTime.UtcNow;
                // Keep for a short moment so other party reads status, then remove
                Task.Delay(15000).ContinueWith(t => _activeCalls.TryRemove(tripId, out var discarded));
                return session;
            }
            return null;
        }
    }
}
