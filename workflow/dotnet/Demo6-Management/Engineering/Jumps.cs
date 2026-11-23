using System.Text.Json;

// The HTTP contract. The property order is the JSON key order.

// Both fields are optional. A missing, null or empty destination becomes Vesper Reach in the endpoint.
record JumpRequest(string? JumpId, string? Destination);

record JumpStarted(string JumpId);

record JumpStatus(string JumpId, string Status, JsonElement? Output);
