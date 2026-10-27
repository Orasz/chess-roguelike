#pragma once

#include <atomic>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

// Godot handle on the in-process Stockfish engine. Stockfish's state is
// process-wide, so only one instance at a time may own the running engine.
class StockfishEngine : public RefCounted {
    GDCLASS(StockfishEngine, RefCounted)

   public:
    ~StockfishEngine();

    // Returns false if this or any other instance already runs the engine.
    bool start();
    void send(const String& command);
    // Complete output lines since the last call; empty unless this instance owns the engine.
    PackedStringArray poll_lines();
    // Does nothing unless this instance owns the engine.
    void stop();
    bool is_running() const;
    // True if Stockfish would accept this position; false where it would exit the process.
    static bool validate_position(const String& fen, const PackedStringArray& moves);

   protected:
    static void _bind_methods();

   private:
    bool owns_engine() const;

    static std::atomic<StockfishEngine*> owner;
};

}  // namespace godot
