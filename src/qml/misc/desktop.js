.pragma library
var panelsGrid
var appLauncher
var desktop
var launchSplash
var confirmation
var compositorRoot
// the home screen's open full screen keyboard (the crown dismisses it)
var keyboard
// a notification's picture open full screen (the crown closes it)
var pictureViewer
// the Find my phone page (apps-misc-04): an item with open(); null until it exists
var findMyPhone
// the shared "Phone away" dialog (system/PhoneAway.qml, W3-launcher-misc): show()
var phoneAway
// the first run setup (firstrun/FirstRunConfig.qml) while it is up: it answers the Bluetooth agent itself,
// so the pairing dialog stays away (its `active` property); null otherwise
var setupPairing
// the smart links menu (system/SmartLinks.qml): open(kind, value)
var smartLinks
// the live update full view (system/LiveUpdate.qml): open(entry)
var liveUpdate
