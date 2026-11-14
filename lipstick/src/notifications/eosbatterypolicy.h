/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSBATTERYPOLICY_H
#define EOSBATTERYPOLICY_H

/*
 * Which battery notices the notification server posts (W2-launcher-charging; audit
 * charging-battery-04, -05, -30, power-boot-warnings-09, -16). Plain C++, tested
 * by tests/tst_batterypolicy.cpp.
 *
 * Stock Pixel Watch (CP3A) posts none of the Sailfish battery notices: no 'Charging',
 * no 'Charging complete' (it woke the screen for 6 s at full charge, also in the
 * middle of the night), no 'Disconnect charger', no 'Charging not started', no power
 * save entering and leaving, no 'Not enough power to charge'. The charging screen
 * and its quality screen (the compositor's ChargingController) say all of that,
 * the Battery Saver notices are the modes engine's, and the low battery is the
 * battery guard's alone (one warning, one shutdown). The 'Low battery' warning
 * of lipstick was repeated every 30 minutes by a keepalive BackgroundActivity,
 * which woke the system from suspend (M1: no such wake-ups), and again at every
 * 2 % drop while the watch was in use; 'Recharge battery' came at 2 %.
 *
 * Every notice is therefore off. BatteryNotifier keeps its table so that one can
 * be switched back on here; with all off it does not even listen to mce.
 */
namespace EosBattery {

// the order of BatteryNotifier's table
enum Notice {
    Charging,
    ChargingComplete,
    RemoveCharger,
    ChargingNotStarted,
    RechargeBattery,
    EnteringPSM,
    ExitingPSM,
    LowBattery,
    NotEnoughPower,
    First = Charging,
    Last = NotEnoughPower
};

// whether the notice is posted (none: DECISIONS.md, 'do what stock does')
constexpr bool wanted(Notice)
{
    return false;
}

constexpr bool anyWanted()
{
    return wanted(Charging) || wanted(ChargingComplete) || wanted(RemoveCharger) || wanted(ChargingNotStarted)
        || wanted(RechargeBattery) || wanted(EnteringPSM) || wanted(ExitingPSM) || wanted(LowBattery)
        || wanted(NotEnoughPower);
}

// the seconds between repeats of a low battery warning: none; nothing repeats and nothing is
// scheduled from suspend (it was 1800 s, a keepalive wake-up)
constexpr int lowBatteryRepeatSeconds()
{
    return 0;
}

// a notice that shows as a banner and turns the display on (the preview of its category): none
constexpr bool wakesDisplay(Notice n)
{
    return wanted(n) && (n == ChargingComplete || n == LowBattery || n == RechargeBattery);
}

} // namespace EosBattery

#endif
