// Test stub of lipstick's compositor (lipstick/src/compositor/lipstickcompositor.h): only what the
// notification units read, the topmost window and its window properties. The real one needs a
// running Wayland compositor.
#ifndef STUB_LIPSTICKCOMPOSITOR_H
#define STUB_LIPSTICKCOMPOSITOR_H

#include <QHash>
#include <QObject>

#include "lipstickcompositorwindow.h"

class LipstickCompositor : public QObject
{
public:
    static LipstickCompositor *instance() { return s_instance; }
    int topmostWindowId() const { return m_topmostWindowId; }

    QHash<int, LipstickCompositorWindow *> m_windows;
    int m_topmostWindowId = 0;

    static inline LipstickCompositor *s_instance = nullptr;
};

#endif
