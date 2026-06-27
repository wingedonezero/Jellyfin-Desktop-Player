cmake_minimum_required(VERSION 3.21)

project(jellyfin-desktop
    VERSION 0.1.0
    DESCRIPTION "Native Qt6/QML + libmpv Jellyfin client"
    LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Widgets Quick QuickControls2 Network DBus)
qt_standard_project_setup(REQUIRES 6.5)

# The mpv engine itself — our one core dependency. Everything else is ours.
find_package(PkgConfig REQUIRED)

# Prefer a vendored, version-pinned libmpv built by scripts/build-mpv.sh
# (mpv 0.41 + libplacebo 7.360, for gpu-next/Vulkan) over the distro's older mpv.
# When the prefix exists we build against its pkg-config; the rpath is baked onto
# the target below so the executable — and transitively libmpv -> libplacebo —
# resolves the vendored .so files at runtime.
set(VENDORED_MPV_PREFIX "${CMAKE_SOURCE_DIR}/.cache/mpv-prefix")
if(EXISTS "${VENDORED_MPV_PREFIX}/lib/pkgconfig/mpv.pc")
    message(STATUS "jellyfin-desktop: using vendored mpv at ${VENDORED_MPV_PREFIX}")
    set(ENV{PKG_CONFIG_PATH} "${VENDORED_MPV_PREFIX}/lib/pkgconfig:$ENV{PKG_CONFIG_PATH}")
    set(JFD_VENDORED_MPV_LIBDIR "${VENDORED_MPV_PREFIX}/lib")
endif()

pkg_check_modules(Mpv REQUIRED IMPORTED_TARGET mpv)

qt_add_executable(jellyfin-desktop
    src/main.cpp
    src/core/Paths.h
    src/core/Paths.cpp
)

# Singletons (theme tokens + feature flags) — must be marked before the module
# is declared so the QML type is registered as a singleton.
set_source_files_properties(src/qml/theme/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
set_source_files_properties(src/qml/theme/Features.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(jellyfin-desktop
    URI JellyfinDesktop
    VERSION 1.0
    QML_FILES
        # theme (singletons)
        src/qml/theme/Theme.qml
        src/qml/theme/Features.qml
        # reusable components
        src/qml/components/JIconButton.qml
        src/qml/components/DarkMenu.qml
        src/qml/components/DarkMenuItem.qml
        src/qml/components/MediaCard.qml
        src/qml/components/MediaWideRow.qml
        src/qml/components/ItemContextMenu.qml
        src/qml/components/MediaRow.qml
        src/qml/components/AppBar.qml
        src/qml/components/NavDrawer.qml
        # screens
        src/qml/Main.qml
        src/qml/screens/LoginView.qml
        src/qml/screens/HomeScreen.qml
        src/qml/screens/LibraryScreen.qml
        src/qml/screens/DetailScreen.qml
        src/qml/screens/SearchScreen.qml
        src/qml/screens/SettingsScreen.qml
        src/qml/screens/PlayerView.qml
        src/qml/screens/PlayerControls.qml
    SOURCES
        src/mpv/MpvVideoItem.h
        src/mpv/MpvVideoItem.cpp
        src/jellyfin/JellyfinClient.h
        src/jellyfin/JellyfinClient.cpp
        src/core/AppConfig.h
        src/core/AppConfig.cpp
        src/core/ScreenSaverInhibitor.h
        src/core/ScreenSaverInhibitor.cpp
)

# Header dirs are on the include path so the generated QML type-registration
# file (which does `#include <Basename.h>`) can find our QML_ELEMENT headers.
target_include_directories(jellyfin-desktop PRIVATE src src/mpv src/jellyfin src/core)

target_compile_definitions(jellyfin-desktop PRIVATE
    PROJECT_VERSION="${PROJECT_VERSION}"
)

target_link_libraries(jellyfin-desktop PRIVATE
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Gui
    Qt6::GuiPrivate
    Qt6::Widgets
    Qt6::Network
    Qt6::DBus
    PkgConfig::Mpv
)

# Bake the vendored mpv prefix into the rpath. DT_RPATH (old dtags) is required
# rather than DT_RUNPATH so the search also satisfies libmpv's own transitive
# dependency on the vendored libplacebo.so.360 (RUNPATH does not propagate).
if(JFD_VENDORED_MPV_LIBDIR)
    set_target_properties(jellyfin-desktop PROPERTIES
        BUILD_RPATH "${JFD_VENDORED_MPV_LIBDIR}"
        INSTALL_RPATH "${JFD_VENDORED_MPV_LIBDIR}")
    target_link_options(jellyfin-desktop PRIVATE "-Wl,--disable-new-dtags")
endif()
