#include "sf_bridge.h"

#include <pthread.h>

#include <atomic>
#include <cstdio>
#include <condition_variable>
#include <deque>
#include <iostream>
#include <memory>
#include <mutex>
#include <streambuf>
#include <utility>

#ifdef __ANDROID__
    #include <android/log.h>
#endif

// Same includes and init sequence as Stockfish's src/main.cpp.
#include "../thirdparty/Stockfish/src/attacks.h"
#include "../thirdparty/Stockfish/src/misc.h"
#include "../thirdparty/Stockfish/src/position.h"
#include "../thirdparty/Stockfish/src/tune.h"
#include "../thirdparty/Stockfish/src/uci.h"

namespace {

// Writes one line to the platform log: logcat on Android, stderr elsewhere.
// Used for what must survive Stockfish calling std::exit, since nobody will
// drain the output buffer after that.
void log_line(bool error, const std::string& line) {
#ifdef __ANDROID__
    __android_log_write(error ? ANDROID_LOG_ERROR : ANDROID_LOG_INFO, "stockfish", line.c_str());
#else
    (void) error;
    std::fprintf(stderr, "stockfish: %s\n", line.c_str());
#endif
}

bool starts_with(const std::string& s, const char* prefix) { return s.rfind(prefix, 0) == 0; }

// Engine stdin. Stockfish's getline(std::cin) blocks in underflow() until a
// command arrives; after close() it reads EOF, which the UCI loop treats as quit.
class InputBuf : public std::streambuf {
   public:
    void push(const std::string& line) {
        std::lock_guard<std::mutex> lock(mutex_);
        pending_.append(line);
        pending_.push_back('\n');
        ready_.notify_all();
    }

    void close() {
        std::lock_guard<std::mutex> lock(mutex_);
        closed_ = true;
        ready_.notify_all();
    }

    // Only called while no reader thread exists.
    void reopen() {
        std::lock_guard<std::mutex> lock(mutex_);
        pending_.clear();
        buffer_.clear();
        closed_ = false;
        setg(nullptr, nullptr, nullptr);
    }

   protected:
    int_type underflow() override {
        if (gptr() < egptr())
            return traits_type::to_int_type(*gptr());
        std::unique_lock<std::mutex> lock(mutex_);
        ready_.wait(lock, [this] { return !pending_.empty() || closed_; });
        if (pending_.empty())
            return traits_type::eof();
        buffer_.swap(pending_);
        pending_.clear();
        setg(buffer_.data(), buffer_.data(), buffer_.data() + buffer_.size());
        return traits_type::to_int_type(*gptr());
    }

   private:
    std::mutex              mutex_;
    std::condition_variable ready_;
    std::string             pending_;  // written by send_line(), guarded by mutex_
    std::string             buffer_;   // read by the engine thread only
    bool                    closed_ = false;
};

// Engine stdout. Collects characters into lines and only exposes complete ones.
class LineBuf : public std::streambuf {
   public:
    std::vector<std::string> drain() {
        std::lock_guard<std::mutex> lock(mutex_);
        std::vector<std::string> out(std::make_move_iterator(lines_.begin()),
                                     std::make_move_iterator(lines_.end()));
        lines_.clear();
        return out;
    }

    void reset() {
        std::lock_guard<std::mutex> lock(mutex_);
        lines_.clear();
        current_.clear();
    }

   protected:
    int_type overflow(int_type ch) override {
        if (!traits_type::eq_int_type(ch, traits_type::eof()))
        {
            std::lock_guard<std::mutex> lock(mutex_);
            put(traits_type::to_char_type(ch));
        }
        return traits_type::not_eof(ch);
    }

    std::streamsize xsputn(const char* s, std::streamsize n) override {
        std::lock_guard<std::mutex> lock(mutex_);
        for (std::streamsize i = 0; i < n; ++i)
            put(s[i]);
        return n;
    }

   private:
    // Caller holds mutex_.
    void put(char c) {
        if (c == '\n')
        {
            mirror(current_);
            lines_.push_back(std::move(current_));
            current_.clear();
        }
        else if (c != '\r')
            current_.push_back(c);
    }

    // Stockfish prints this right before std::exit(1) (UCIEngine::terminate_on_critical_error).
    static void mirror(const std::string& line) {
        if (starts_with(line, "info string CRITICAL ERROR"))
            log_line(true, line);
#if defined(__ANDROID__) && defined(DEBUG_ENABLED)
        else if (starts_with(line, "info string"))
            log_line(false, line);
#endif
    }

    std::mutex              mutex_;
    std::string             current_;
    std::deque<std::string> lines_;
};

#ifdef __ANDROID__
// Android drops an app's stderr, where Stockfish reports allocation, thread and
// network failures; while the engine runs, std::cerr goes to logcat instead.
class LogcatBuf : public std::streambuf {
   protected:
    int_type overflow(int_type ch) override {
        if (!traits_type::eq_int_type(ch, traits_type::eof()))
        {
            std::lock_guard<std::mutex> lock(mutex_);
            put(traits_type::to_char_type(ch));
        }
        return traits_type::not_eof(ch);
    }

    std::streamsize xsputn(const char* s, std::streamsize n) override {
        std::lock_guard<std::mutex> lock(mutex_);
        for (std::streamsize i = 0; i < n; ++i)
            put(s[i]);
        return n;
    }

   private:
    void put(char c) {
        if (c == '\n')
        {
            log_line(true, current_);
            current_.clear();
        }
        else if (c != '\r')
            current_.push_back(c);
    }

    std::mutex  mutex_;
    std::string current_;
};
#endif

struct State {
    InputBuf        in;
    LineBuf         out;
    std::streambuf* saved_in  = nullptr;
    std::streambuf* saved_out = nullptr;
#ifdef __ANDROID__
    LogcatBuf       err;
    std::streambuf* saved_err = nullptr;
#endif
    pthread_t         thread{};
    std::atomic<bool> running{false};
    std::mutex        lifecycle;
};

// Deliberately leaked: a static destructor at process exit must never race a
// still-running engine thread.
State& state() {
    static State* s = new State;
    return *s;
}

void restore_streams(State& s) {
    std::cin.rdbuf(s.saved_in);
    std::cout.rdbuf(s.saved_out);
#ifdef __ANDROID__
    std::cerr.rdbuf(s.saved_err);
#endif
}

// Attacks and Zobrist tables, built once and read-only afterwards; shared by
// the engine thread and validate_position().
void init_tables() {
    static std::once_flag init_once;
    std::call_once(init_once, [] {
        Stockfish::Attacks::init();
        Stockfish::Position::init();
    });
}

bool has_line_break(const std::string& s) { return s.find_first_of("\r\n") != std::string::npos; }

// Search threads get 8 MB stacks in thread_native.h; the UCI loop gets the same.
constexpr size_t kLoopStackSize = 8 * 1024 * 1024;

void* run_loop(void*) {
    char  arg0[] = "stockfish";
    char* argv[] = {arg0, nullptr};
    // argc must be 1: with any other value UCIEngine::loop() never reads stdin.
    auto uci = std::make_unique<Stockfish::UCIEngine>(Stockfish::CommandLine(1, argv));
    Stockfish::Tune::init(uci->engine_options());
    uci->loop();
    return nullptr;
}

}  // namespace

namespace sfbridge {

bool start() {
    State&                      s = state();
    std::lock_guard<std::mutex> lock(s.lifecycle);
    if (s.running)
        return false;

    init_tables();

    s.in.reopen();
    s.out.reset();
    s.saved_in  = std::cin.rdbuf(&s.in);
    s.saved_out = std::cout.rdbuf(&s.out);
#ifdef __ANDROID__
    s.saved_err = std::cerr.rdbuf(&s.err);
#endif

    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, kLoopStackSize);
    const int rc = pthread_create(&s.thread, &attr, run_loop, nullptr);
    pthread_attr_destroy(&attr);
    if (rc != 0)
    {
        restore_streams(s);
        return false;
    }
    s.running = true;
    return true;
}

void send_line(const std::string& line) {
    // A line break would let one call smuggle in several commands.
    if (state().running && !has_line_break(line))
        state().in.push(line);
}

std::vector<std::string> drain_lines() { return state().out.drain(); }

void stop() {
    State&                      s = state();
    std::lock_guard<std::mutex> lock(s.lifecycle);
    if (!s.running)
        return;
    s.in.push("quit");
    s.in.close();
    pthread_join(s.thread, nullptr);
    restore_streams(s);
    s.running = false;
}

bool running() { return state().running; }

bool validate_position(const std::string& fen, const std::vector<std::string>& moves) {
    // A line break would split the command, so what Stockfish parses would differ.
    if (has_line_break(fen))
        return false;
    for (const std::string& move : moves)
        if (has_line_break(move))
            return false;

    init_tables();
    std::deque<Stockfish::StateInfo> states(1);
    Stockfish::Position              pos;
    if (pos.set(fen, false, &states.back()).has_value())
        return false;
    for (const std::string& move : moves)
    {
        const Stockfish::Move m = Stockfish::UCIEngine::to_move(pos, move);
        if (m == Stockfish::Move::none())
            return false;
        states.emplace_back();
        pos.do_move(m, states.back());
    }
    return true;
}

}  // namespace sfbridge
