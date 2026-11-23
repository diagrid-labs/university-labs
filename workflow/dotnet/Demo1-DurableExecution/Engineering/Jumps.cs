using System.Text.Json;

// The HTTP contract. The property order is the JSON key order.

// Both fields are optional. Demo 1 accepts a destination and ignores it; later demos fly there.
record JumpRequest(string? JumpId, string Destination = "Vesper Reach");

record JumpStarted(string JumpId);

record JumpStatus(string JumpId, string Status, JsonElement? Output);
