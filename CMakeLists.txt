cmake_minimum_required(VERSION 3.21)
project(Condenser VERSION 0.6.0 LANGUAGES CXX)

# Include GNUInstallDirs for standard installation directories
include(GNUInstallDirs)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find required Qt6 components
find_package(Qt6 6.8 REQUIRED COMPONENTS Core Widgets Quick QuickControls2 Multimedia)
find_package(KF6IconThemes)

include(GNUInstallDirs)

# Enable Qt tools
qt_standard_project_setup()

# Source files
set(SOURCES
    src/main.cpp
    src/systemchecker.cpp
    src/gameinfo.cpp
    src/recordingclip.cpp
    src/steamrecordingmanager.cpp
    src/videoexporter.cpp
    src/qvdfparser.cpp
    src/recordingfiltermodel.cpp
    src/thumbnailprovider.cpp
)

# Header files
set(HEADERS
    src/systemchecker.h
    src/gameinfo.h
    src/recordingclip.h
    src/steamrecordingmanager.h
    src/videoexporter.h
    src/qvdfparser.h
    src/recordingfiltermodel.h
    src/thumbnailprovider.h
)

# Create the executable
qt_add_executable(Condenser
    WIN32
    ${SOURCES}
    ${HEADERS}
)

# Add QML module
qt_add_qml_module(Condenser
    URI CondenserApp
    VERSION 1.0
    QML_FILES
        qml/main.qml
        qml/SystemCheckPage.qml
        qml/EditorPage.qml

        qml/components/SteamUserSelectionDialog.qml
)

# Add resources
qt_add_resources(Condenser "icons"
    FILES
        qml/app_icon.png
)

# Link Qt libraries
target_link_libraries(Condenser PRIVATE
    Qt6::Core
    Qt6::Widgets
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Multimedia
)

if(TARGET KF6::IconThemes)
    target_link_libraries(Condenser PRIVATE KF6::IconThemes)
    target_compile_definitions(Condenser PRIVATE HAVE_KICONTHEME=1)
endif ()

target_compile_definitions(Condenser PRIVATE PSRE_VERSION="${PROJECT_VERSION}")

# Include directories
target_include_directories(Condenser PRIVATE src)

# Compiler-specific settings
if(WIN32 AND CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    # MinGW/MSYS2 settings
    target_compile_options(Condenser PRIVATE
        -Wall -Wextra -Wpedantic
    )
elseif(MSVC)
    # MSVC settings
    target_compile_options(Condenser PRIVATE
        /W4
    )
endif()

# Set target properties
set_target_properties(Condenser PROPERTIES
    WIN32_EXECUTABLE TRUE
)

# Installation rules
if(WIN32)
    # Windows installation
    install(TARGETS Condenser
        RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    )

    # FIXME: Figure out why QtMultimedia plugin is not deployed.
    # qt_generate_deploy_app_script(
    #     TARGET Condenser
    #     OUTPUT_SCRIPT deploy_script
    # )
    # install(SCRIPT ${deploy_script})
else()
    # Linux installation
    install(TARGETS Condenser
        RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    )

    # Install desktop file
    install(FILES packaging/linux/top.makkendam.Condenser.desktop
        DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/applications
    )

    # Install AppStream metainfo
    install(FILES packaging/linux/top.makkendam.Condenser.metainfo.xml
        DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/metainfo
    )

    # Install icon
    install(FILES qml/app_icon.png
        DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/icons/hicolor/128x128/apps
        RENAME top.makkendam.Condenser.png
    )
    # Install SVG icon in scalable directory according to Freedesktop.org icon theme specification
    install(FILES qml/app_icon.svg
        DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/icons/hicolor/scalable/apps
        RENAME top.makkendam.Condenser.svg
    )

    # # Install documentation
    # if(EXISTS "${CMAKE_SOURCE_DIR}/README.md")
    #     install(FILES README.md
    #         DESTINATION ${CMAKE_INSTALL_DOCDIR}
    #     )
    # endif()

    # # Install license
    # if(EXISTS "${CMAKE_SOURCE_DIR}/LICENSE")
    #     install(FILES LICENSE
    #         DESTINATION ${CMAKE_INSTALL_DOCDIR}
    #     )
    # endif()
endif()

# CPack configuration for packaging
set(CPACK_PACKAGE_NAME "Condenser")
set(CPACK_PACKAGE_VENDOR "makkendam")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Export Steam game recordings to MP4 videos")
set(CPACK_PACKAGE_VERSION ${PROJECT_VERSION})
set(CPACK_PACKAGE_VERSION_MAJOR ${PROJECT_VERSION_MAJOR})
set(CPACK_PACKAGE_VERSION_MINOR ${PROJECT_VERSION_MINOR})
set(CPACK_PACKAGE_VERSION_PATCH ${PROJECT_VERSION_PATCH})

if(WIN32)
    # Windows packaging with NSIS
    set(CPACK_GENERATOR "NSIS;ZIP")
    set(CPACK_NSIS_DISPLAY_NAME "Condenser")
    set(CPACK_NSIS_PACKAGE_NAME "Condenser")
    set(CPACK_NSIS_CONTACT "97677573+makkendam@users.noreply.github.com")
    set(CPACK_NSIS_MODIFY_PATH ON)
    set(CPACK_NSIS_ENABLE_UNINSTALL_BEFORE_INSTALL ON)
else()
    # Linux packaging
    set(CPACK_GENERATOR "DEB;RPM;TGZ")

    # DEB package configuration
    set(CPACK_DEBIAN_PACKAGE_MAINTAINER "makkendam <97677573+makkendam@users.noreply.github.com>")
    set(CPACK_DEBIAN_PACKAGE_DEPENDS "ffmpeg, libqt6core6, libqt6gui6, libqt6qml6, libqt6quick6, libqt6multimedia6")
    set(CPACK_DEBIAN_PACKAGE_SECTION "video")

    # RPM package configuration
    set(CPACK_RPM_PACKAGE_GROUP "Applications/Multimedia")
    set(CPACK_RPM_PACKAGE_LICENSE "MIT")
    set(CPACK_RPM_PACKAGE_REQUIRES "ffmpeg, qt6-qtbase, qt6-qtdeclarative, qt6-qtmultimedia")
endif()

include(CPack)
