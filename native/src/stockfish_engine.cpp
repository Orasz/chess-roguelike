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

bool StockfishEngine::owns_engine() const { return owner.load() == this; }

void StockfishEngine::_bind_methods() {
    ClassDB::bind_method(D_METHOD("start"), &StockfishEngine::start);
    ClassDB::bind_method(D_METHOD("send", "command"), &StockfishEngine::send);
    ClassDB::bind_method(D_METHOD("poll_lines"), &StockfishEngine::poll_lines);
    ClassDB::bind_method(D_METHOD("stop"), &StockfishEngine::stop);
    ClassDB::bind_method(D_METHOD("is_running"), &StockfishEngine::is_running);
}

}  // namespace godot
