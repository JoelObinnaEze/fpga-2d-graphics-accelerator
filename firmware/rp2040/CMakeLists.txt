cmake_minimum_required(VERSION 3.13)

include($ENV{PICO_SDK_PATH}/external/pico_sdk_import.cmake)

project(fpga_pong C CXX ASM)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

pico_sdk_init()

add_executable(fpga_pong
    src/main.c
    src/accelerator_link.c
    src/accelerator_protocol.c
    src/pong.c
)

target_include_directories(fpga_pong PRIVATE include)
target_link_libraries(fpga_pong PRIVATE pico_stdlib hardware_spi)
set_source_files_properties(
    src/main.c
    src/accelerator_link.c
    src/accelerator_protocol.c
    src/pong.c
    PROPERTIES COMPILE_OPTIONS "-Wall;-Wextra;-Wpedantic;-Werror"
)

pico_enable_stdio_usb(fpga_pong 1)
pico_enable_stdio_uart(fpga_pong 0)
pico_add_extra_outputs(fpga_pong)
