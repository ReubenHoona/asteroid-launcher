/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.sensorlogd

/*
 * The health history the assistant reads for one question (AssistantActions: steps and distance of past days,
 * workouts): asteroid-sensorlogd's HealthMetricsLoader (a day's summary from the step logs and health.db) and
 * WorkoutLoader (the Exercise app's workouts in health.db), as Health and the tiles read them. Made for the
 * question and dropped after it: nothing is read or watched otherwise, no sensor is woken.
 */
QtObject {
    property QtObject metrics: HealthMetricsLoader {}
    property QtObject workouts: WorkoutLoader {}
}
