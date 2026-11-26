/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSOFFLOADCLIENT_H
#define EOSOFFLOADCLIENT_H

#include <cstring>
#include <functional>
#include <string>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>

/*
 * The compositor's side of eos-display-offload's socket (CR-46):
 * /run/eos-display-offload/socket, SOCK_SEQPACKET, one request per message,
 * replies "ok", "ok ignored" or "err ...".
 *
 *  - request(): sends and waits for the reply (at most timeoutSec), for the
 *    display state machine (suspend, resume, layout, clear, status), which
 *    needs the answer.
 *  - post(): sends and does not wait (the daemon answers a closed socket, it
 *    ignores SIGPIPE): the frame pacing boost at the start of a transition,
 *    the burn-in mask, the brightness config, tilt-to-bright. A missing
 *    daemon costs one failed connect.
 *
 * Requests: when they are sent. boost only with the display on (the daemon
 * ignores it with the display handed over); mask and ttb only when they
 * change, as the daemon keeps them; reset() at the compositor's start puts
 * back what a launcher that ended with the mask up or tilt-to-bright on may
 * have left. Nothing is polled and nothing is timed. Plain C++ (POSIX):
 * tests/tst_offloadclient.cpp, against a fake daemon on a socket of its own.
 */
namespace EosOffload {

static const char SOCKET_PATH[] = "/run/eos-display-offload/socket";
// the daemon's limit (BOOST_MAX_MS): the touch boost's frequencies for 500 ms
static const int BOOST_MS = 500;
// mce's Adaptive brightness switch (Settings > Display), which the hub's
// brightness config follows
static const char ADAPTIVE_KEY[] = "/system/osso/dsm/display/als_enabled";

inline int connectTo(const char *path, bool nonBlocking)
{
    struct sockaddr_un sa;
    const int s = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC | (nonBlocking ? SOCK_NONBLOCK : 0), 0);
    if (s < 0)
        return -1;
    memset(&sa, 0, sizeof(sa));
    sa.sun_family = AF_UNIX;
    strncpy(sa.sun_path, path, sizeof(sa.sun_path) - 1);
    if (::connect(s, reinterpret_cast<struct sockaddr *>(&sa), sizeof(sa)) != 0) {
        ::close(s);
        return -1;
    }
    return s;
}

// One request and its reply; empty when there is no daemon or no reply came
inline std::string request(const char *path, const std::string &req, int timeoutSec)
{
    char reply[512];
    ssize_t n = -1;
    const int s = connectTo(path, false);
    if (s < 0)
        return std::string();
    struct timeval tv = { timeoutSec, 0 };
    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    if (::send(s, req.data(), req.size(), MSG_NOSIGNAL) == ssize_t(req.size()))
        n = ::recv(s, reply, sizeof(reply) - 1, 0);
    ::close(s);
    return n > 0 ? std::string(reply, size_t(n)) : std::string();
}

// One request, not waiting for the reply; false when it could not be sent
inline bool post(const char *path, const std::string &req)
{
    const int s = connectTo(path, true);
    if (s < 0)
        return false;
    const bool sent = ::send(s, req.data(), req.size(), MSG_NOSIGNAL | MSG_DONTWAIT) == ssize_t(req.size());
    ::close(s);
    return sent;
}

inline bool adaptiveKey(const std::string &key)
{
    return key == ADAPTIVE_KEY;
}

// tilt-to-bright: the hub layout asks for brighten_on_tilt and the screen is
// not locked with a secure lock (the hub would light a locked watch's face)
inline bool ttbWanted(bool layoutAsks, bool lockedSecure)
{
    return layoutAsks && !lockedSecure;
}

class Requests
{
public:
    typedef std::function<bool(const std::string &)> Sender;

    explicit Requests(Sender send) : m_send(send) {}

    // a window transition starts
    bool boost(bool displayOn)
    {
        return displayOn && m_send("boost " + std::to_string(BOOST_MS));
    }

    // the burn-in image mask shows (the daemon doubles the always-on levels) or not
    bool mask(bool shown)
    {
        const int v = shown ? 1 : 0;
        if (v == m_mask)
            return false;
        m_mask = v;
        return m_send(shown ? "mask 1" : "mask 0");
    }

    // Adaptive brightness was switched: the hub gets its brightness config again
    bool brightness()
    {
        return m_send("brightness");
    }

    bool ttb(bool layoutAsks, bool lockedSecure)
    {
        const int v = ttbWanted(layoutAsks, lockedSecure) ? 1 : 0;
        if (v == m_ttb)
            return false;
        m_ttb = v;
        return m_send(v ? "ttb 1" : "ttb 0");
    }

    // at the start: the daemon may hold a mask or tilt-to-bright of an earlier launcher
    void reset()
    {
        m_mask = -1;
        m_ttb = -1;
        mask(false);
        ttb(false, false);
    }

private:
    Sender m_send;
    int m_mask = -1;    // -1: not known
    int m_ttb = -1;
};

} // namespace EosOffload

#endif // EOSOFFLOADCLIENT_H
