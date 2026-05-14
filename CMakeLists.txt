cmake_minimum_required(VERSION 3.10)
project(Pilot LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(PILOT_USE_ORT_CUDA "Enable ONNX Runtime CUDA execution provider when available" ON)
option(PILOT_ENABLE_LOCAL_WINDOW "Enable OpenCV local preview windows" ON)

if(MSVC)
    add_compile_options(/W4 /EHsc)
    add_definitions(-D_CRT_SECURE_NO_WARNINGS)
else()
    add_compile_options(-Wall -Wextra)
endif()

# --- 查找库 ---
find_package(FFmpeg REQUIRED)
find_package(OpenCV REQUIRED)
find_package(Torch REQUIRED)
find_package(Python3 COMPONENTS Interpreter Development REQUIRED)
find_package(Threads REQUIRED)
# --- libdatachannel 跨平台配置 ---
if(WIN32)
    set(_DEFAULT_VCPKG_TRIPLET "x64-windows")
else()
    set(_DEFAULT_VCPKG_TRIPLET "x64-linux")
endif()

set(VCPKG_ROOT "$ENV{VCPKG_ROOT}" CACHE PATH "vcpkg root")
if(NOT VCPKG_ROOT AND WIN32)
    set(VCPKG_ROOT "D:/vcpkg" CACHE PATH "vcpkg root" FORCE)
endif()
set(VCPKG_TARGET_TRIPLET "${_DEFAULT_VCPKG_TRIPLET}" CACHE STRING "vcpkg triplet")

set(_VCPKG_INSTALLED_ROOT "${VCPKG_ROOT}/installed/${VCPKG_TARGET_TRIPLET}")
if (NOT EXISTS "${_VCPKG_INSTALLED_ROOT}/include/rtc/datachannel.hpp")
    if (EXISTS "${VCPKG_ROOT}/include/rtc/datachannel.hpp")
        set(_VCPKG_INSTALLED_ROOT "${VCPKG_ROOT}")
    endif()
endif()

find_package(LibDataChannel CONFIG QUIET)
if(TARGET LibDataChannel::LibDataChannel)
    set(PILOT_DATACHANNEL_LIB LibDataChannel::LibDataChannel)
else()
    find_library(PILOT_DATACHANNEL_LIB
        NAMES datachannel
        PATHS
            "${_VCPKG_INSTALLED_ROOT}/lib"
            "${_VCPKG_INSTALLED_ROOT}/debug/lib"
    )
    if(NOT PILOT_DATACHANNEL_LIB)
        message(FATAL_ERROR "libdatachannel was not found. Install it or set CMAKE_PREFIX_PATH/VCPKG_ROOT.")
    endif()
endif()

# --- ONNX Runtime 跨平台配置 ---
if(WIN32)
    set(_DEFAULT_ORT_DIR "D:/onnxruntime-win-x64-gpu-1.24.1")
else()
    set(_DEFAULT_ORT_DIR "/opt/onnxruntime")
endif()
set(ORT_DIR "${_DEFAULT_ORT_DIR}" CACHE PATH "ONNX Runtime root")

find_library(ORT_LIB onnxruntime 
    PATHS "${ORT_DIR}/lib")
if(NOT ORT_LIB)
    message(FATAL_ERROR "ONNX Runtime library was not found. Set ORT_DIR to the ONNX Runtime root directory.")
endif()

if(PILOT_USE_ORT_CUDA)
    find_library(ORT_CUDA_PROVIDER_LIB onnxruntime_providers_cuda
        PATHS "${ORT_DIR}/lib")
    if(ORT_CUDA_PROVIDER_LIB)
        set(PILOT_ORT_CUDA_ENABLED ON)
    else()
        message(WARNING "PILOT_USE_ORT_CUDA=ON but onnxruntime_providers_cuda was not found. Building without CUDA EP.")
    endif()
endif()

# --- 定义程序资源 ---
set(COMMON_SOURCES
    "service/service.cpp"
    "utils/WebServerUtils.cpp"
    "utils/H264Encoder.cpp"
    "feature/feature.cpp"
    "feature/tridet.cpp"
    "yolo/yolo_detector.cpp"
)

set(APP_SOURCES "service/entry.cpp" ${COMMON_SOURCES})
set(TEST_SOURCES "test/test_rtspPlay.cpp" ${COMMON_SOURCES})
set(FEATURE_TEST_SOURCES "test/test_extractFeatures.cpp" ${COMMON_SOURCES})
set(YOLO_TEST_SOURCES "test/test_yolo.cpp" ${COMMON_SOURCES})

# 收集所有头文件
file(GLOB_RECURSE HEADER_FILES "service/*.hpp" "service/*.h" "utils/*.h" "feature/*.hpp")

# --- 汇总依赖 ---
set(ALL_LIBS 
    ${OpenCV_LIBS} 
    ${TORCH_LIBRARIES} 
    ${FFMPEG_LIBRARIES}
    ${ORT_LIB} 
    Python3::Python 
    Threads::Threads
    ${PILOT_DATACHANNEL_LIB}
)

if(PILOT_ORT_CUDA_ENABLED)
    list(APPEND ALL_LIBS ${ORT_CUDA_PROVIDER_LIB})
endif()

set(ALL_INCLUDES
    ${CMAKE_CURRENT_SOURCE_DIR}
    "${_VCPKG_INSTALLED_ROOT}/include" # 解决 rtc 文件夹找不到的问题
    "${ORT_DIR}/include"  # 加入 ORT 头文件路径
    ${OpenCV_INCLUDE_DIRS}
    ${TORCH_INCLUDE_DIRS}
    ${Python3_INCLUDE_DIRS}
    ${FFMPEG_INCLUDE_DIRS}
)

# --- 创建目标 ---
# 主程序
add_executable(PilotApp ${APP_SOURCES} ${HEADER_FILES})
set_target_properties(PilotApp PROPERTIES OUTPUT_NAME "pilot")
target_include_directories(PilotApp PUBLIC ${ALL_INCLUDES})
target_link_libraries(PilotApp PRIVATE ${ALL_LIBS})

# 测试程序
add_executable(Tst ${TEST_SOURCES} ${HEADER_FILES})
set_target_properties(Tst PROPERTIES OUTPUT_NAME "test_runner")
target_include_directories(Tst PUBLIC ${ALL_INCLUDES})
target_link_libraries(Tst PRIVATE ${ALL_LIBS})

# 特征提取测试程序
add_executable(TestFeatures ${FEATURE_TEST_SOURCES} ${HEADER_FILES})
set_target_properties(TestFeatures PROPERTIES OUTPUT_NAME "test_extractFeatures")
target_include_directories(TestFeatures PUBLIC ${ALL_INCLUDES})
target_link_libraries(TestFeatures PRIVATE ${ALL_LIBS})

# YOLO 测试程序
add_executable(TestYolo ${YOLO_TEST_SOURCES} ${HEADER_FILES})
set_target_properties(TestYolo PROPERTIES OUTPUT_NAME "test_yolo")
target_include_directories(TestYolo PUBLIC ${ALL_INCLUDES})
target_link_libraries(TestYolo PRIVATE ${ALL_LIBS})

foreach(target PilotApp Tst TestFeatures TestYolo)
    target_compile_options(${target} PRIVATE ${TORCH_CXX_FLAGS})
    if(PILOT_ORT_CUDA_ENABLED)
        target_compile_definitions(${target} PRIVATE PILOT_USE_ORT_CUDA=1)
    endif()
    if(PILOT_ENABLE_LOCAL_WINDOW)
        target_compile_definitions(${target} PRIVATE PILOT_ENABLE_LOCAL_WINDOW=1)
    endif()
endforeach()

# 自动拷贝DLL
if(WIN32)
    set(ORT_DLLS
        "${ORT_DIR}/lib/onnxruntime.dll"
        "${ORT_DIR}/lib/onnxruntime_providers_shared.dll"
        $<$<BOOL:${PILOT_ORT_CUDA_ENABLED}>:${ORT_DIR}/lib/onnxruntime_providers_cuda.dll>
        $<$<CONFIG:Debug>:${_VCPKG_INSTALLED_ROOT}/debug/bin/datachannel.dll>
        $<$<NOT:$<CONFIG:Debug>>:${_VCPKG_INSTALLED_ROOT}/bin/datachannel.dll>
    )

    foreach(target PilotApp Tst TestFeatures TestYolo)
        add_custom_command(TARGET ${target} POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
            ${ORT_DLLS}
            $<TARGET_FILE_DIR:${target}>
            COMMENT "Copying ONNX Runtime DLLs to output directory..."
        )
    endforeach()
endif()



