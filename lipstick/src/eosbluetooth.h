/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The pairing rules of the BlueZ agent (connectivity-system-ux-01, -02, -03), as stock CP3A's
 * BluetoothPairingDialogBuilder and the pairing activities decide them. Plain C++ (no Qt):
 * tests/tst_bluetooth.cpp.
 */
#ifndef EOSBLUETOOTH_H
#define EOSBLUETOOTH_H

#include <cstdint>
#include <string>

namespace EosBluetooth {

// A Class of Device whose major device class is Phone (bits 8-12 = 2, BluetoothClass 0x200):
// BluetoothDisplayPasskeyActivity picks "Enter this code on phone" for it, else
// "Enter code on other device"
inline bool isPhoneClass(uint32_t classOfDevice) { return (classOfDevice & 0x1F00u) == 0x0200u; }

// BlueZ's Alias is the address (XX-XX-XX-XX-XX-XX) for a device without a name; the dialog shows
// no address, so such a name counts as none
inline bool looksLikeAddress(const std::string &s)
{
    if (s.size() != 17)
        return false;
    for (size_t i = 0; i < s.size(); i++) {
        const char c = s[i];
        if (i % 3 == 2) {
            if (c != '-' && c != ':')
                return false;
        } else if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) {
            return false;
        }
    }
    return true;
}

// The name the pairing dialog shows: the alias, else the name, else "" (the dialog says "device")
inline std::string displayName(const std::string &alias, const std::string &name)
{
    if (!alias.empty() && !looksLikeAddress(alias))
        return alias;
    if (!name.empty() && !looksLikeAddress(name))
        return name;
    return std::string();
}

// What an AuthorizeService request (a profile of a device wants to connect) gets. Stock has no
// per-service prompt: a bonded device's profiles are allowed silently, an unbonded device's are
// refused silently; the service's UUID is never shown.
enum class ServiceReply { Accept, Reject };
inline ServiceReply authorizeService(bool paired) { return paired ? ServiceReply::Accept : ServiceReply::Reject; }

// The pairing window is up for these requests only (a service request never opens it)
enum class Request { PinCode, Passkey, DisplayPinCode, DisplayPasskey, Confirmation, Authorization, Service };
inline bool opensWindow(Request r) { return r != Request::Service; }

// stock BluetoothPairingDialogBuilder: the long form of the title when it fits 18 characters
// ("Secure pair with" is 17 characters, so only a one character name fits it), else the short
inline bool useShortTitle(size_t fullTitleLength) { return fullTitleLength > 18; }

// The variants stock calls legacy ("Legacy pair with"): PIN (0), display PIN (5) and 16 digit PIN (7)
inline bool isLegacy(Request r) { return r == Request::PinCode || r == Request::DisplayPinCode; }

} // namespace EosBluetooth

#endif // EOSBLUETOOTH_H
