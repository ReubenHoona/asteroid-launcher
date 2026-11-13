/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSAPPKEY_H
#define EOSAPPKEY_H

#include <algorithm>
#include <cctype>
#include <string>
#include <vector>

/*
 * The name of the program behind a window, so that a launch of an
 * application that is already running (hidden in the background) finds its
 * window again (AppLifecycle.resumeApp, lifecycle.js appKey is the same
 * rule for a desktop Exec line): the basename of argv[0] of the process,
 * lower case, without ".desktop". A program run through a launcher or
 * interpreter ("invoker --type=qt6 /usr/bin/asteroid-x", "env X=1 prog",
 * "booster-...") is named by the first argument that is a program path.
 * Plain C++: tests/tst_appkey.cpp.
 */
namespace EosAppKey {

inline std::string lower(std::string s)
{
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return std::tolower(c); });
    return s;
}

inline std::string base(const std::string &path)
{
    const size_t slash = path.rfind('/');
    std::string b = slash == std::string::npos ? path : path.substr(slash + 1);
    const std::string suffix = ".desktop";
    if (b.size() > suffix.size() && b.compare(b.size() - suffix.size(), suffix.size(), suffix) == 0)
        b.erase(b.size() - suffix.size());
    return lower(b);
}

inline bool isLauncher(const std::string &b)
{
    return b == "invoker" || b == "env" || b == "sh" || b == "bash" || b == "dbus-launch"
           || b == "qmlscene" || b.compare(0, 7, "booster") == 0 || b.compare(0, 6, "applau") == 0;
}

// cmdline: /proc/<pid>/cmdline, arguments separated by NUL
inline std::string fromCmdline(const std::string &cmdline)
{
    std::vector<std::string> args;
    size_t start = 0;
    while (start < cmdline.size()) {
        size_t end = cmdline.find('\0', start);
        if (end == std::string::npos)
            end = cmdline.size();
        if (end > start)
            args.push_back(cmdline.substr(start, end - start));
        start = end + 1;
    }
    if (args.empty())
        return std::string();
    std::string b = base(args[0]);
    if (!isLauncher(b))
        return b;
    // a launcher: the first argument that is a program, not an option or
    // an assignment
    for (size_t i = 1; i < args.size(); ++i) {
        const std::string &a = args[i];
        if (a.empty() || a[0] == '-' || a.find('=') != std::string::npos)
            continue;
        const std::string ab = base(a);
        if (!isLauncher(ab))
            return ab;
    }
    return b;
}

} // namespace EosAppKey

#endif // EOSAPPKEY_H
