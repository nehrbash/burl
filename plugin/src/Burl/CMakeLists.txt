qml_module(burl-core
    URI Burl
    SOURCES
        cutils.cpp
        qalculator.cpp
        appdb.cpp
        requests.cpp
        toaster.cpp
        imageanalyser.cpp
        emacssources.cpp
        websources.cpp
        spotifysources.cpp
        mailsources.cpp
        calendarsources.cpp
    LIBRARIES
        Qt::Gui
        Qt::Quick
        Qt::Concurrent
        Qt::Sql
        Qt::Network
        PkgConfig::Qalculate
)

# Bake the shell version in so CUtils can expose it without spawning a process
target_compile_definitions(burl-core PRIVATE BURL_VERSION="${VERSION}")

add_subdirectory(Components)
add_subdirectory(Config)
add_subdirectory(Internal)
add_subdirectory(Models)
add_subdirectory(Services)
add_subdirectory(Sim)
add_subdirectory(Blobs)
add_subdirectory(Images)
