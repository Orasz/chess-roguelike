#pragma once

// Stockfish side of the extension. This header uses the standard library only:
// Godot code includes it, but never Stockfish's own headers.

#include <string>
#include <vector>

namespace sfbridge {

// Starts Stockfish's UCI loop on a background thread, with std::cin and
// std::cout redirected to in-memory buffers. Returns false if it already runs.
bool start();

// Queues one UCI command for the engine. Ignored when the engine is not running.
void send_line(const std::string& line);

// Returns the complete output lines produced since the last call.
std::vector<std::string> drain_lines();

// Sends `quit`, waits for the loop to end and restores std::cin and std::cout.
void stop();

bool running();

}  // namespace sfbridge
