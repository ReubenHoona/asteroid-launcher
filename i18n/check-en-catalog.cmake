# The English catalog (asteroid-launcher.en.ts) is the launcher's fallback for every language
# (lipstick/src/localemanager.cpp loads it first), so each text id the code asks for must be there
# with its English text, or en, en_US and any language without that id show the raw id.
# Fails when an id of qsTrId(), qtTrId() or QT_TRID_NOOP() with a literal id in src/ or lipstick/
# has no entry in en.ts, or only a vanished, obsolete, unfinished or empty one.
#   cmake -DROOT=<source dir> -P i18n/check-en-catalog.cmake
# To refresh the catalog: lupdate -locations none src lipstick -ts i18n/asteroid-launcher.en.ts,
# then give each new message its source text as the translation (no type="unfinished").
cmake_minimum_required(VERSION 3.12)

if(NOT ROOT)
	set(ROOT "${CMAKE_CURRENT_LIST_DIR}/..")
endif()
set(catalog "${ROOT}/i18n/asteroid-launcher.en.ts")

file(READ "${catalog}" ts)
# one list item per message: no list separators or brackets of the text in the way
string(REPLACE ";" "_" ts "${ts}")
string(REPLACE "[" "_" ts "${ts}")
string(REPLACE "]" "_" ts "${ts}")
string(REPLACE "</message>" ";" messages "${ts}")
set(english "")
set(unusable "")
foreach(m IN LISTS messages)
	if(NOT m MATCHES "<message id=\"([^\"]+)\"")
		continue()
	endif()
	set(id "${CMAKE_MATCH_1}")
	if(m MATCHES "<translation type=\"(vanished|obsolete|unfinished)\"" OR m MATCHES "<translation>[ \t\r\n]*</translation>"
			OR m MATCHES "<translation/>" OR NOT m MATCHES "<translation")
		list(APPEND unusable "${id}")
	else()
		list(APPEND english "${id}")
	endif()
endforeach()

file(GLOB_RECURSE sources "${ROOT}/src/*.qml" "${ROOT}/src/*.js" "${ROOT}/src/*.cpp" "${ROOT}/src/*.h"
	"${ROOT}/lipstick/*.qml" "${ROOT}/lipstick/*.js" "${ROOT}/lipstick/*.cpp" "${ROOT}/lipstick/*.h")
set(used "")
foreach(f IN LISTS sources)
	file(STRINGS "${f}" lines REGEX "(qsTrId|qtTrId|QT_TRID_NOOP)\\([ \t]*\"[^\"]+\"")
	foreach(l IN LISTS lines)
		string(REGEX MATCHALL "(qsTrId|qtTrId|QT_TRID_NOOP)\\([ \t]*\"[^\"]+\"" calls "${l}")
		foreach(c IN LISTS calls)
			string(REGEX REPLACE "^[A-Za-z_]+\\([ \t]*\"([^\"]+)\"$" "\\1" id "${c}")
			list(APPEND used "${id}")
		endforeach()
	endforeach()
endforeach()
list(REMOVE_DUPLICATES used)

set(missing "")
foreach(id IN LISTS used)
	if(NOT id IN_LIST english)
		list(APPEND missing "${id}")
	endif()
endforeach()
list(LENGTH used n_used)
list(LENGTH english n_english)
if(missing)
	list(LENGTH missing n_missing)
	list(JOIN missing " " shown)
	message(FATAL_ERROR "asteroid-launcher.en.ts: ${n_missing} of the ${n_used} text ids in the code have no English text: ${shown}")
endif()
message(STATUS "asteroid-launcher.en.ts: English for all ${n_used} text ids in the code (${n_english} entries)")
