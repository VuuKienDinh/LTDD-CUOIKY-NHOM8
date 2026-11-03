using Microsoft.AspNetCore.SignalR;

namespace webAPI.Hubs
{
    public class TripTrackingHub : Hub
    {
        public async Task JoinTripGroup(int tripId)
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, $"trip-{tripId}");
        }

        public async Task LeaveTripGroup(int tripId)
        {
            await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"trip-{tripId}");
        }
    }
}

