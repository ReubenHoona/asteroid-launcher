/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSBOOTFEEDBACK_H
#define EOSBOOTFEEDBACK_H

#include <string>

/*
 * The boot-complete feedback (R5 B-09; power-boot-warnings-06 = haptics-sounds-10), as stock's
 * BootCompletedFeedbackProvider (CSUI feedback/BootCompletedFeedbackProvider$$ExternalSyntheticLambda0):
 * at the end of the boot the screen is woken, then, unless the boot follows an update or the setup is not
 * finished, the two-part haptic and the after-reboot sound play (ngfd event boot_done, meta-eos64
 * events.d/boot_done.ini: a system sound, silent while ring and notifications are muted). Once per boot:
 * a restart of the launcher is no boot. The first boot of an update is eos-update's trial boot (its
 * state file /var/lib/eos-update/state says PHASE=trial). Plain C++: tests/tst_bootfeedback.cpp.
 */
namespace EosBootFeedback {

// the value of the last PHASE= line of eos-update's state file ("" when there is none)
inline std::string updatePhase(const std::string &stateText)
{
    std::string phase;
    size_t pos = 0;
    while (pos <= stateText.size()) {
        size_t end = stateText.find('\n', pos);
        if (end == std::string::npos)
            end = stateText.size();
        const std::string line = stateText.substr(pos, end - pos);
        if (line.compare(0, 6, "PHASE=") == 0) {
            phase = line.substr(6);
            while (!phase.empty() && (phase.back() == '\r' || phase.back() == ' ' || phase.back() == '\t'))
                phase.pop_back();
        }
        pos = end + 1;
    }
    return phase;
}

// the kernel's boot id without blanks ("" when it could not be read)
inline std::string trim(const std::string &s)
{
    size_t b = s.find_first_not_of(" \t\r\n");
    if (b == std::string::npos)
        return std::string();
    size_t e = s.find_last_not_of(" \t\r\n");
    return s.substr(b, e - b + 1);
}

// The screen is woken and the feedback plays: a known boot that it has not played for, the setup finished,
// not the trial boot of an update
inline bool due(const std::string &bootId, const std::string &lastBootId, bool setupDone, const std::string &phase)
{
    const std::string id = trim(bootId);
    if (id.empty() || id == trim(lastBootId))
        return false;
    if (!setupDone)
        return false;
    if (phase == "trial")
        return false;
    return true;
}

// Whether the boot id is to be kept as played: every boot it was asked for once, even when it did not play
// (a trial boot, the setup), so that a restart of the launcher later in that boot does not play it
inline bool remember(const std::string &bootId, const std::string &lastBootId)
{
    const std::string id = trim(bootId);
    return !id.empty() && id != trim(lastBootId);
}

} // namespace EosBootFeedback

#endif // EOSBOOTFEEDBACK_H
