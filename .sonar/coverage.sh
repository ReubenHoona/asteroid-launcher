#!/bin/sh
# Coverage for SonarQube. sonarqube/scan.sh builds .sonar/Dockerfile and runs this in it, with the repository at
# /usr/src and one job; the report is .sonar-reports/cobertura.xml, its paths relative to the repository root.
#   1. the unit tests in tests/ (Qt Test): the units under test from src/ and lipstick/src/ compiled with
#      gcc --coverage, the AsteroidOS-only libraries replaced by tests/stubs, each test on its own private
#      dbus-daemon with fake mce / BlueZ / GeoClue / PulseAudio peers (QT_QPA_PLATFORM=offscreen);
#   2. gcovr: the lines and conditions of src/ and lipstick/src/ as Cobertura (test code is analysed as tests,
#      not as code to cover; the branches gcc adds for exception unwinding are left out); the test results as
#      JUnit XML in .sonar-reports/build/junit/.
# Exit status (bits): 1 a test failed or did not build, 2 no coverage report.
# Without Docker (Debian/Ubuntu with qt6-base-dev, libdbus-glib-1-dev, dbus-daemon, tzdata, gcovr):
#   sh .sonar/coverage.sh      (or SKIP_GCOVR=1 to only build and run the tests)
set -u
cd "$(dirname "$0")/.." || exit 2

reports=.sonar-reports
build=$reports/build
status=0

rm -rf "$build"
mkdir -p "$build"

echo "== unit tests"
if cmake -S tests -B "$build" -DCOVERAGE=ON -DCMAKE_BUILD_TYPE=Debug > "$build/configure.log" 2>&1 \
    && cmake --build "$build" -j "${JOBS:-1}"; then
    if QT_QPA_PLATFORM=offscreen ctest --test-dir "$build" --output-on-failure; then
        echo "unit tests passed"
    else
        echo "unit tests FAILED"
        status=$((status | 1))
    fi
else
    cat "$build/configure.log"
    echo "unit tests did not build"
    status=$((status | 1))
fi

if [ "${SKIP_GCOVR:-}" != 1 ]; then
    echo "== coverage"
    gcovr --root . --filter 'src/' --filter 'lipstick/src/' --merge-mode-functions=separate \
        --exclude-throw-branches --exclude-unreachable-branches \
        --cobertura "$reports/cobertura.xml" --cobertura-pretty --print-summary "$build" || status=$((status | 2))
    [ -s "$reports/cobertura.xml" ] || status=$((status | 2))
fi

exit "$status"
