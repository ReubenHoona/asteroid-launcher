/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The compositor's requests to eos-display-offload (lipstick/src/compositor/
 * eosoffloadclient.h, CR-46) against a fake daemon on a socket of its own:
 * what is sent (boost 500, mask 1, mask 0, brightness, ttb 1, ttb 0), when
 * (the boost only with the display on, mask and ttb only on a change, the
 * reset at the start), a request that waits for its reply, and no daemon.
 * Plain C++ (POSIX, threads): cmake -DLAUNCHER_TESTS=ON, or
 * g++ -std=c++17 -pthread -I../lipstick/src/compositor tst_offloadclient.cpp
 */

#include "eosoffloadclient.h"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <mutex>
#include <poll.h>
#include <string>
#include <thread>
#include <vector>

using namespace EosOffload;

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

// The daemon's accept loop (eos-display-offload.c): one connection at a time,
// each message answered; records the requests in the order they came
struct FakeDaemon {
    std::string path;
    int ls = -1;
    std::thread th;
    std::atomic<bool> stop { false };
    std::mutex mu;
    std::vector<std::string> got;
    std::string answer = "ok";

    explicit FakeDaemon(const std::string &p) : path(p)
    {
        struct sockaddr_un sa;
        ls = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
        memset(&sa, 0, sizeof(sa));
        sa.sun_family = AF_UNIX;
        strncpy(sa.sun_path, path.c_str(), sizeof(sa.sun_path) - 1);
        unlink(path.c_str());
        if (ls < 0 || bind(ls, reinterpret_cast<struct sockaddr *>(&sa), sizeof(sa)) || listen(ls, 16)) {
            fprintf(stderr, "fake daemon: cannot listen on %s\n", path.c_str());
            exit(2);
        }
        th = std::thread([this] { run(); });
    }
    ~FakeDaemon()
    {
        stop = true;
        th.join();
        close(ls);
        unlink(path.c_str());
    }
    void run()
    {
        while (!stop) {
            struct pollfd p = { ls, POLLIN, 0 };
            if (poll(&p, 1, 20) <= 0)
                continue;
            const int c = accept4(ls, nullptr, nullptr, SOCK_CLOEXEC);
            if (c < 0)
                continue;
            char req[512];
            ssize_t n;
            while ((n = recv(c, req, sizeof(req) - 1, 0)) > 0) {
                {
                    std::lock_guard<std::mutex> g(mu);
                    got.push_back(std::string(req, size_t(n)));
                }
                send(c, answer.data(), answer.size(), MSG_NOSIGNAL);
            }
            close(c);
        }
    }
    // the requests so far, once the daemon has read `count` of them (at most 2 s)
    std::vector<std::string> wait(size_t count)
    {
        for (int i = 0; i < 200; i++) {
            {
                std::lock_guard<std::mutex> g(mu);
                if (got.size() >= count)
                    break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        // and nothing more for a moment
        std::this_thread::sleep_for(std::chrono::milliseconds(30));
        std::lock_guard<std::mutex> g(mu);
        return got;
    }
    void clear()
    {
        std::lock_guard<std::mutex> g(mu);
        got.clear();
    }
};

static std::string tempDir()
{
    char t[] = "/tmp/tst_offloadclient-XXXXXX";
    const char *d = mkdtemp(t);
    if (!d) {
        fprintf(stderr, "mkdtemp failed\n");
        exit(2);
    }
    return d;
}

static void testRequestWaitsForReply(const std::string &dir)
{
    FakeDaemon d(dir + "/socket");
    d.answer = "ok offloaded";
    CHECK(request(d.path.c_str(), "suspend blank", 2) == "ok offloaded");
    const auto got = d.wait(1);
    CHECK(got.size() == 1 && got[0] == "suspend blank");
}

static void testPostDoesNotWait(const std::string &dir)
{
    FakeDaemon d(dir + "/socket");
    const auto t0 = std::chrono::steady_clock::now();
    CHECK(post(d.path.c_str(), "boost 500"));
    CHECK(post(d.path.c_str(), "brightness"));
    const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count();
    CHECK(ms < 200);                        // never waited for a reply
    const auto got = d.wait(2);
    CHECK(got.size() == 2);
    CHECK(got.size() == 2 && got[0] == "boost 500" && got[1] == "brightness");
}

static void testRequests(const std::string &dir)
{
    FakeDaemon d(dir + "/socket");
    const std::string path = d.path;
    Requests r([path](const std::string &q) { return post(path.c_str(), q); });

    // the start: the daemon may hold an earlier launcher's mask and tilt-to-bright
    r.reset();
    auto got = d.wait(2);
    CHECK(got.size() == 2 && got[0] == "mask 0" && got[1] == "ttb 0");
    d.clear();

    // a transition with the display on: boost 500; with it off: nothing
    CHECK(r.boost(true));
    CHECK(!r.boost(false));
    CHECK(r.boost(true));
    got = d.wait(2);
    CHECK(got.size() == 2 && got[0] == "boost 500" && got[1] == "boost 500");
    d.clear();

    // the burn-in mask: once per change
    CHECK(r.mask(true));
    CHECK(!r.mask(true));
    CHECK(r.mask(false));
    CHECK(!r.mask(false));
    got = d.wait(2);
    CHECK(got.size() == 2 && got[0] == "mask 1" && got[1] == "mask 0");
    d.clear();

    // Adaptive brightness switched: every time
    CHECK(r.brightness());
    CHECK(r.brightness());
    got = d.wait(2);
    CHECK(got.size() == 2 && got[0] == "brightness" && got[1] == "brightness");
    d.clear();

    // tilt-to-bright: the layout asks and the screen is not locked and secure
    CHECK(!r.ttb(false, false));            // 0 already (the reset)
    CHECK(r.ttb(true, false));              // ttb 1
    CHECK(!r.ttb(true, false));
    CHECK(r.ttb(true, true));               // a secure lock came on: ttb 0
    CHECK(!r.ttb(false, true));
    CHECK(r.ttb(true, false));              // unlocked: ttb 1
    CHECK(r.ttb(false, false));             // a layout that does not ask: ttb 0
    got = d.wait(4);
    CHECK(got.size() == 4 && got[0] == "ttb 1" && got[1] == "ttb 0" && got[2] == "ttb 1" && got[3] == "ttb 0");
}

static void testRules()
{
    CHECK(BOOST_MS == 500);
    CHECK(std::string(SOCKET_PATH) == "/run/eos-display-offload/socket");
    CHECK(adaptiveKey("/system/osso/dsm/display/als_enabled"));
    CHECK(!adaptiveKey("/system/osso/dsm/display/display_brightness"));
    CHECK(!adaptiveKey(""));
    CHECK(ttbWanted(true, false));
    CHECK(!ttbWanted(true, true));
    CHECK(!ttbWanted(false, false));
}

static void testNoDaemon(const std::string &dir)
{
    const std::string none = dir + "/nothing-listens";
    CHECK(!post(none.c_str(), "boost 500"));
    CHECK(request(none.c_str(), "status", 1).empty());
    // a Requests without a daemon keeps its state: the change is not sent twice
    int sent = 0;
    Requests r([&sent, none](const std::string &q) { sent++; return post(none.c_str(), q); });
    CHECK(!r.mask(true));
    CHECK(!r.mask(true));
    CHECK(sent == 1);
}

int main()
{
    const std::string dir = tempDir();
    testRules();
    testRequestWaitsForReply(dir);
    testPostDoesNotWait(dir);
    testRequests(dir);
    testNoDaemon(dir);
    rmdir(dir.c_str());
    printf("tst_offloadclient: %d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
