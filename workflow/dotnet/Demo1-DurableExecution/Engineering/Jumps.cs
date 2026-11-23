using System.Text.Json;

// The HTTP contract. The property order is the JSON key order.

// Both fields are optional. Demo 1 accepts a destination, like the other demos, but ignores it.
record JumpRequest(string? JumpId, string? Destination);

record JumpStarted(string JumpId);

record JumpStatus(string JumpId, string Status, JsonElement? Output);
