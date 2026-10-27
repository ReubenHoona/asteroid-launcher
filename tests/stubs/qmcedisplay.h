// Test stub of nemo-qml-plugin-mce's QMceDisplay: the display state, set by the test.
#ifndef STUB_QMCEDISPLAY_H
#define STUB_QMCEDISPLAY_H

#include <QObject>

class QMceDisplay : public QObject
{
public:
    enum State { DisplayOff, DisplayDim, DisplayOn };

    explicit QMceDisplay(QObject *parent = nullptr) : QObject(parent) {}
    State state() const { return s_state; }

    static inline State s_state = DisplayOn;
};

#endif
