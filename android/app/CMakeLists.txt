cmake_minimum_required(VERSION 3.4.1)

# This is a dummy library just to force Gradle to package libc++_shared.so
add_library(dummy SHARED dummy.cpp)
