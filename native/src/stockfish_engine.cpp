#include "stockfish_engine.h"

#include <godot_cpp/core/class_db.hpp>

#include "../bridge/sf_bridge.h"

namespace godot {

std::atomic<StockfishEngine*> StockfishEngine::owner{nullptr};

StockfishEngine::~StockfishEngine() { stop(); }

bool StockfishEngine::start() {
    StockfishEngine* expected = nullptr;
    if (!owner.compare_exchange_strong(expected, this))
        return false;
    if (!sfbridge::start())
    {
        owner = nullptr;
        return false;
    }
    return true;
}

void StockfishEngine::send(const String& command) {
    if (owns_engine())
        sfbridge::send_line(command.utf8().get_data());
}

PackedStringArray StockfishEngine::poll_lines() {
    PackedStringArray result;
    if (!owns_engine())
        return result;
    for (const std::string& line : sfbridge::drain_lines())
        result.push_back(String::utf8(line.c_str()));
    return result;
}

void StockfishEngine::stop() {
    if (!owns_engine())
        return;
    sfbridge::stop();
    owner = nullptr;
}

bool StockfishEngine::is_running() const { return owns_engine() && sfbridge::running(); }

bool StockfishEngine::validate_position(const String& fen, const PackedStringArray& moves) {
    std::vector<std::string> std_moves;
    std_moves.reserve(moves.size());
    for (int64_t i = 0; i < moves.size(); ++i)
        std_moves.emplace_back(moves[i].utf8().get_data());
    return sfbridge::validate_position(fen.utf8().get_data(), std_moves);
}

bool StockfishEngine::owns_engine() const { return owner.load() == this; }

void StockfishEngine::_bind_methods() {
    ClassDB::bind_method(D_METHOD("start"), &StockfishEngine::start);
    ClassDB::bind_method(D_METHOD("send", "command"), &StockfishEngine::send);
    ClassDB::bind_method(D_METHOD("poll_lines"), &StockfishEngine::poll_lines);
    ClassDB::bind_method(D_METHOD("stop"), &StockfishEngine::stop);
    ClassDB::bind_method(D_METHOD("is_running"), &StockfishEngine::is_running);
    ClassDB::bind_static_method("StockfishEngine", D_METHOD("validate_position", "fen", "moves"),
                                &StockfishEngine::validate_position);
}

}  // namespace godot
