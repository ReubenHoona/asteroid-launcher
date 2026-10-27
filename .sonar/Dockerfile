# Image for .sonar/coverage.sh: sonarqube/scan.sh builds it (build context: this .sonar/ folder only) and runs the
# script in it as the scanning user. A native x86_64 build of the unit tests in tests/: the launcher and lipstick
# units under test compiled with gcc --coverage against Debian's Qt 6 and libdbus / dbus-glib, the AsteroidOS-only
# libraries (lipstick's compositor, mlite, ngf, qmce) replaced by the fakes in tests/stubs. The base image is pinned;
# the packages are trixie's at build time (a stable release: point updates only).
FROM debian:trixie-20261005-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        g++ make cmake pkg-config \
        qt6-base-dev qt6-base-dev-tools \
        libdbus-1-dev libdbus-glib-1-dev libglib2.0-dev \
        dbus-daemon tzdata gcovr \
    && rm -rf /var/lib/apt/lists/*
