# The circuit detector's CPU engine, built from source by each platform's
# Flutter build (see ../README.md). Flutter needs CMake 3.10.
cmake_minimum_required(VERSION 3.10)
project(circuit_engine_library LANGUAGES C)

add_library(circuit_engine SHARED circuit_engine.c image_ink.c)
set_target_properties(circuit_engine PROPERTIES OUTPUT_NAME "circuit_engine" C_STANDARD 11)

if(MSVC)
  target_compile_options(circuit_engine PRIVATE /O2)
  target_compile_definitions(circuit_engine PRIVATE _USE_MATH_DEFINES _CRT_SECURE_NO_WARNINGS)
else()
  # -O3 vectorises the inner loops; errno-free maths lets expf vectorise too.
  target_compile_options(circuit_engine PRIVATE -O3 -fno-math-errno -fvisibility=hidden)
  if(CMAKE_C_COMPILER_ID STREQUAL "GNU")
    # Vector helpers are inlined; their ABI note does not apply.
    target_compile_options(circuit_engine PRIVATE -Wno-psabi)
  endif()
endif()

find_package(Threads REQUIRED)
target_link_libraries(circuit_engine PRIVATE Threads::Threads)
if(UNIX AND NOT APPLE)
  target_link_libraries(circuit_engine PRIVATE m)
  target_link_options(circuit_engine PRIVATE "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/circuit_engine.map")
endif()
if(ANDROID)
  # Android 15's 16 KB pages.
  target_link_options(circuit_engine PRIVATE "-Wl,-z,max-page-size=16384")
endif()
