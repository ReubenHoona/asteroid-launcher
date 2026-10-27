// Test stub of lipstick's compositor window: its window properties only.
#ifndef STUB_LIPSTICKCOMPOSITORWINDOW_H
#define STUB_LIPSTICKCOMPOSITORWINDOW_H

#include <QVariantMap>

class LipstickCompositorWindow
{
public:
    QVariantMap windowProperties() const { return m_properties; }
    QVariantMap m_properties;
};

#endif
