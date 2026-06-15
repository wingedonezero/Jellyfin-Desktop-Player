cmake_minimum_required(VERSION 3.21)

project(jellyfin-desktop
    VERSION 0.1.0
    DESCRIPTION "Native Qt6/QML + libmpv Jellyfin client"
    LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Quick QuickControls2 Network)
qt_standard_project_setup(REQUIRES 6.5)

# The mpv engine itself — our one core dependency. Everything else is ours.
find_package(PkgConfig REQUIRED)
pkg_check_modules(Mpv REQUIRED IMPORTED_TARGET mpv)

qt_add_executable(jellyfin-desktop
    src/main.cpp
)

qt_add_qml_module(jellyfin-desktop
    URI JellyfinDesktop
    VERSION 1.0
    QML_FILES
        src/qml/Main.qml
    SOURCES
        src/mpv/MpvVideoItem.h
        src/mpv/MpvVideoItem.cpp
        src/jellyfin/JellyfinClient.h
        src/jellyfin/JellyfinClient.cpp
)

# Header dirs are on the include path so the generated QML type-registration
# file (which does `#include <Basename.h>`) can find our QML_ELEMENT headers.
target_include_directories(jellyfin-desktop PRIVATE src src/mpv src/jellyfin)

target_compile_definitions(jellyfin-desktop PRIVATE
    PROJECT_VERSION="${PROJECT_VERSION}"
)

target_link_libraries(jellyfin-desktop PRIVATE
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Gui
    Qt6::Network
    PkgConfig::Mpv
)
