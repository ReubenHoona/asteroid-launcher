/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSSHUTDOWN_H
#define EOSSHUTDOWN_H

#include <string>

/*
 * Power off or restart (power-boot-warnings-03): systemd 257's logind sends
 * PrepareForShutdownWithMetadata(start, {type: ...}) with the type of the
 * shutdown. The screen says "Restarting..." for the ones that come back up
 * and "Bye" for the ones that do not; it is the same screen for the user's,
 * a battery-empty and a thermal shutdown. Plain C++ (tests/tst_shutdown.cpp).
 */
namespace EosShutdown {

// type: "poweroff", "halt", "reboot", "kexec", "soft-reboot" (logind's
// SystemdManager action names); an unknown or empty one is a power off
inline bool isRestart(const std::string &type)
{
    return type == "reboot" || type == "kexec" || type == "soft-reboot";
}

} // namespace EosShutdown

#endif // EOSSHUTDOWN_H
