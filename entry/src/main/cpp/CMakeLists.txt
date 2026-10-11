cmake_minimum_required(VERSION 3.5.0)
project(harmony_py_ide)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(NATIVE_DIR ${CMAKE_CURRENT_SOURCE_DIR})

# ── 目标 ABI：hvigor 通过 OHOS_ARCH 传入，缺失时做兼容推断 ────────────────
if(NOT DEFINED OHOS_ARCH)
  if(DEFINED CMAKE_SYSTEM_PROCESSOR)
    set(OHOS_ARCH ${CMAKE_SYSTEM_PROCESSOR})
  else()
    set(OHOS_ARCH arm64-v8a)
  endif()
endif()
if(OHOS_ARCH STREQUAL "aarch64")
  set(OHOS_ARCH arm64-v8a)
elseif(OHOS_ARCH STREQUAL "amd64")
  set(OHOS_ARCH x86_64)
endif()
message(STATUS "HarmonyPyIDE: target ABI = ${OHOS_ARCH}")

# ── 预编译的 CPython 静态库（由 scripts/build-cpython-ohos.ps1 产出） ─────
set(PY_ROOT ${NATIVE_DIR}/thirdparty/${OHOS_ARCH})
set(PY_LIB ${PY_ROOT}/libpython3.12.a)
set(PY_INCLUDE ${PY_ROOT}/include)

add_library(pythonbridge SHARED napi_init.cpp pty_watch.cpp)

target_link_libraries(pythonbridge PUBLIC libace_napi.z.so libhilog_ndk.z.so)

if(EXISTS ${PY_LIB} AND EXISTS ${PY_INCLUDE}/Python.h)
  message(STATUS "HarmonyPyIDE: 内嵌 CPython 运行时 -> ${PY_LIB}")
  target_compile_definitions(pythonbridge PRIVATE PY_RUNTIME_AVAILABLE=1)
  target_include_directories(pythonbridge PRIVATE ${PY_INCLUDE})
  # 静态库必须整库链接：否则 PyInit_* 与内建扩展模块符号会被链接器丢弃
  target_link_options(pythonbridge PRIVATE
    "-Wl,--whole-archive" "${PY_LIB}" "-Wl,--no-whole-archive")
  target_link_libraries(pythonbridge PUBLIC z dl m)
else()
  message(WARNING
    "HarmonyPyIDE: 未找到 ${PY_LIB}，本次将构建「无内置 CPython 运行时」的版本，"
    "App 启动后会明确提示运行时未就绪。请先执行 scripts/build-cpython-ohos.ps1。")
endif()
