// Test double of lipstick's BluetoothAgent type (lipstick/src/bluetoothagent.h): only its State enum, in
// the same order; the agent object is a context property that a test file defines
import QtQuick

QtObject {
    enum State { Idle, ReqPinCode, ReqPasskey, DispPinCode, DispPasskey, ReqConfirmation, ReqAuthorization, AuthService }
}
