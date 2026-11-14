/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

.pragma library

/*
 * The exercise types of the Exercise app (asteroid-exercise src/ExerciseTypes.js, the 54 of stock's
 * FitbitExerciseType in stock's order) as far as the Exercise quick start tile needs them: the key the app takes,
 * the name (the button's accessible name, 'Start %1') and the icon. Made by gen_extypes.py from the app's list:
 * change that, not this.
 */

function _t(key, name, icon) {
    return { "key": key, "name": name, "icon": icon }
}

function all() {
    return [
        //% "Aerobics"
        _t("Aerobics", qsTrId("id-ex-type-aerobics"), "ios-body"),
        //% "Badminton"
        _t("Badminton", qsTrId("id-ex-type-badminton"), "ios-tennisball"),
        //% "Baseball"
        _t("Baseball", qsTrId("id-ex-type-baseball"), "ios-baseball"),
        //% "Basketball"
        _t("Basketball", qsTrId("id-ex-type-basketball"), "ios-basketball"),
        //% "Bike"
        _t("Bike", qsTrId("id-ex-type-bike"), "ios-bicycle"),
        //% "Bootcamp"
        _t("BootCamp", qsTrId("id-ex-type-bootcamp"), "ios-body"),
        //% "Canoeing"
        _t("Canoeing", qsTrId("id-ex-type-canoeing"), "ios-boat"),
        //% "Circuit training"
        _t("CircuitTraining", qsTrId("id-ex-type-circuittraining"), "ios-repeat"),
        //% "Core training"
        _t("CoreTraining", qsTrId("id-ex-type-coretraining"), "ios-body"),
        //% "Cricket"
        _t("Cricket", qsTrId("id-ex-type-cricket"), "ios-baseball"),
        //% "Cross-country skiing"
        _t("CrossCountrySki", qsTrId("id-ex-type-crosscountryski"), "ios-snow"),
        //% "CrossFit"
        _t("Crossfit", qsTrId("id-ex-type-crossfit"), "ios-body"),
        //% "Dancing"
        _t("Dance", qsTrId("id-ex-type-dance"), "ios-musical-notes"),
        //% "Elliptical"
        _t("Elliptical", qsTrId("id-ex-type-elliptical"), "ios-infinite"),
        //% "Field hockey"
        _t("FieldHockey", qsTrId("id-ex-type-fieldhockey"), "ios-football"),
        //% "Football"
        _t("Football", qsTrId("id-ex-type-football"), "ios-american-football"),
        //% "Golf"
        _t("Golf", qsTrId("id-ex-type-golf"), "ios-flag"),
        //% "HIIT"
        _t("HIIT", qsTrId("id-ex-type-hiit"), "ios-flash"),
        //% "Hike"
        _t("Hike", qsTrId("id-ex-type-hike"), "ios-hike"),
        //% "Indoor climbing"
        _t("IndoorClimbing", qsTrId("id-ex-type-indoorclimbing"), "ios-trending-up"),
        //% "Interval workout"
        _t("IntervalWorkout", qsTrId("id-ex-type-intervalworkout"), "ios-timer"),
        //% "Kayaking"
        _t("Kayaking", qsTrId("id-ex-type-kayaking"), "ios-boat"),
        //% "Kickboxing"
        _t("Kickboxing", qsTrId("id-ex-type-kickboxing"), "ios-hand"),
        //% "Martial arts"
        _t("MartialArts", qsTrId("id-ex-type-martialarts"), "ios-hand"),
        //% "Mountain Biking"
        _t("MountainBiking", qsTrId("id-ex-type-mountainbiking"), "ios-bicycle"),
        //% "Outdoor workout"
        _t("OutdoorWorkout", qsTrId("id-ex-type-outdoorworkout"), "ios-leaf"),
        //% "Swim - Open"
        _t("OpenWaterSwim", qsTrId("id-ex-type-openwaterswim"), "ios-water"),
        //% "Pickleball"
        _t("Pickleball", qsTrId("id-ex-type-pickleball"), "ios-tennisball"),
        //% "Padel"
        _t("Padel", qsTrId("id-ex-type-padel"), "ios-tennisball"),
        //% "Pilates"
        _t("Pilates", qsTrId("id-ex-type-pilates"), "ios-body"),
        //% "Swim - Pool"
        _t("PoolSwim", qsTrId("id-ex-type-poolswim"), "ios-water"),
        //% "Powerlifting"
        _t("Powerlifting", qsTrId("id-ex-type-powerlifting"), "ios-medal"),
        //% "Rollerblading"
        _t("Rollerblading", qsTrId("id-ex-type-rollerblading"), "ios-speedometer"),
        //% "Rowing machine"
        _t("RowingMachine", qsTrId("id-ex-type-rowingmachine"), "ios-rowing"),
        //% "Rugby"
        _t("Rugby", qsTrId("id-ex-type-rugby"), "ios-american-football"),
        //% "Run"
        _t("Run", qsTrId("id-ex-type-run"), "ios-run"),
        //% "Skating"
        _t("Skating", qsTrId("id-ex-type-skating"), "ios-speedometer"),
        //% "Skiing"
        _t("Skiing", qsTrId("id-ex-type-skiing"), "ios-snow"),
        //% "Snowboarding"
        _t("Snowboarding", qsTrId("id-ex-type-snowboarding"), "ios-snow"),
        //% "Soccer"
        _t("Soccer", qsTrId("id-ex-type-soccer"), "ios-football"),
        //% "Spinning"
        _t("Spinning", qsTrId("id-ex-type-spinning"), "ios-bicycle"),
        //% "Sport"
        _t("Sport", qsTrId("id-ex-type-sport"), "ios-trophy"),
        //% "Stair climber"
        _t("StairClimber", qsTrId("id-ex-type-stairclimber"), "ios-trending-up"),
        //% "Strength training"
        _t("StrengthTraining", qsTrId("id-ex-type-strengthtraining"), "ios-medal"),
        //% "Paddleboarding"
        _t("SUP", qsTrId("id-ex-type-sup"), "ios-boat"),
        //% "Surfing"
        _t("Surfing", qsTrId("id-ex-type-surfing"), "ios-water"),
        //% "Swim"
        _t("Swim", qsTrId("id-ex-type-swim"), "ios-water"),
        //% "Tennis"
        _t("Tennis", qsTrId("id-ex-type-tennis"), "ios-tennisball"),
        //% "Treadmill"
        _t("TreadMill", qsTrId("id-ex-type-treadmill"), "ios-run"),
        //% "Walk"
        _t("Walk", qsTrId("id-ex-type-walk"), "ios-walk"),
        //% "Weightlifting"
        _t("Weightlifting", qsTrId("id-ex-type-weightlifting"), "ios-medal"),
        //% "Weights"
        _t("Weights", qsTrId("id-ex-type-weights"), "ios-medal"),
        //% "Workout"
        _t("Workout", qsTrId("id-ex-type-workout"), "ios-body"),
        //% "Yoga"
        _t("Yoga", qsTrId("id-ex-type-yoga"), "ios-body")
    ]
}

var _byKey = null

function find(key) {
    if (_byKey === null) {
        _byKey = {}
        var list = all()
        for (var i = 0; i < list.length; i++)
            _byKey[list[i].key] = list[i]
    }
    return _byKey[key] || null
}
