/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.sensorlogd

/*
 * The Last activity tile's reader (LastActivityTile.qml): asteroid-sensorlogd's WorkoutLoader (health.db; last(): the
 * newest workout that ended, {} for none; dataChanged when the daemon writes health.db). A file of its own, made only
 * while the tile is on screen, so the tile (and its picture in the tiles editor) loads where the plugin has no
 * WorkoutLoader yet.
 */
WorkoutLoader {
}
