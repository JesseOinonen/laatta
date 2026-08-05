cmake_minimum_required(VERSION 3.20)

project(OpenGL)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(OpenGL REQUIRED)
find_package(glfw3 REQUIRED)

add_executable(OpenGL
    src/main.cpp
    src/glad.c
)

target_include_directories(OpenGL PRIVATE
    ${PROJECT_SOURCE_DIR}/include
)

target_link_libraries(OpenGL PRIVATE
    OpenGL::GL
    glfw
)