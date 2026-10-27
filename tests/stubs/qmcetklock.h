// Test stub of nemo-qml-plugin-mce's QMceTkLock: the touchscreen/keypad lock, set by the test.
#ifndef STUB_QMCETKLOCK_H
#define STUB_QMCETKLOCK_H

#include <QObject>

class QMceTkLock : public QObject
{
public:
    explicit QMceTkLock(QObject *parent = nullptr) : QObject(parent) {}
    bool locked() const { return s_locked; }

    static inline bool s_locked = false;
};

#endif
