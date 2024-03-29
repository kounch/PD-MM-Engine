# Copyright (c) 2022-2023 kounch
# SPDX-License-Identifier: BSD-2-Clause

cmake_minimum_required(VERSION 3.24)
project("ManicMiner")

if ( ${CMAKE_SOURCE_DIR} STREQUAL ${CMAKE_BINARY_DIR} )
    message(FATAL_ERROR "In-source builds not allowed. Please make a new directory (called a build directory) and run CMake from there. You may need to remove CMakeCache.txt.")
endif()

list(APPEND CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/CMake/Find")

if (APPLE)
    execute_process(
            COMMAND bash -c "egrep '^\\s*SDKRoot' $HOME/.Playdate/config"
            COMMAND head -n 1
            COMMAND cut -c9-
            OUTPUT_VARIABLE SDK
            OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    set (SIMULATOR_BIN open)
else()
    set(SDK $ENV{PLAYDATE_SDK_PATH})
    set (SIMULATOR_BIN "${SDK}\bin\Playdate Simulator.exe")
endif()

set(BASENAME ${PROJECT_NAME})
set(OUTPUT_DIR ${CMAKE_BINARY_DIR})

set(EXTRA_DOCS
    LICENSE
    README.md
    )

set(CMAKE_PREFIX_PATH
        ${SDK}/bin
        )

# Check module availability
find_package(pdc)
find_package(asciidoctor-pdf)

# Function to build PDF files
function(MAKE_PDF PDF_LANG)
    if(PDF_LANG STREQUAL "es")
        set(PDF_NAME "Manual de Manic Miner Engine para Playdate.pdf")
    else()
        set(PDF_NAME "Manic Miner Engine for Playdate Manual.pdf")
    endif()

    add_custom_target("pdfdocs_${PDF_LANG}" ALL
        DEPENDS ${OUTPUT_DIR}/${PDF_NAME}
    )
    add_custom_command(OUTPUT ${OUTPUT_DIR}/${PDF_NAME}
        DEPENDS ${PROJECT_SOURCE_DIR}/Manual/${PDF_LANG}/index.adoc
        COMMAND ${ASCIIDOCTOR_PDF_BINARY} -a pdf-themesdir=${PROJECT_SOURCE_DIR}/Manual -a pdf-theme=style.yml -o ${PDF_DIR}/${PDF_NAME} ${PROJECT_SOURCE_DIR}/Manual/${PDF_LANG}/index.adoc
        COMMENT "${PDF_LANG} Docs"
    )
endfunction()   

# Build localized PDFs
if(ASCIIDOCTOR-PDF_FOUND)
    message("Prepare docs build")
    set(PDF_DIR "${OUTPUT_DIR}/docs")
    file(MAKE_DIRECTORY ${PDF_DIR})

    make_pdf("es")
    make_pdf("en")

    add_custom_target(extra_docs ALL
        DEPENDS ${OUTPUT_DIR}/docs
    )
    foreach(file_i ${EXTRA_DOCS})
        add_custom_command(TARGET extra_docs
            COMMAND ${CMAKE_COMMAND} ARGS -E copy ${PROJECT_SOURCE_DIR}/${file_i} ${OUTPUT_DIR}/docs
            BYPRODUCTS ${OUTPUT_DIR}/docs/${file_i}
        )
    endforeach(file_i)
endif()

add_custom_target("ManicMiner" ALL
    DEPENDS ${OUTPUT_DIR}/${PROJECT_NAME}.pdx
    )
add_custom_command(
    OUTPUT ${OUTPUT_DIR}/${PROJECT_NAME}.pdx
    DEPENDS ${PROJECT_SOURCE_DIR}/${PROJECT_NAME}/main.lua
    COMMAND ${PDC_BINARY} -k ${PROJECT_SOURCE_DIR}/${PROJECT_NAME} ${OUTPUT_DIR}/${PROJECT_NAME}.pdx
    COMMAND ${CMAKE_COMMAND} -E copy "${PROJECT_SOURCE_DIR}/${PROJECT_NAME}/roomPacks/Manic Miner/rooms.json" "${OUTPUT_DIR}/${PROJECT_NAME}.pdx/roomPacks/Manic Miner/"
    COMMAND ${CMAKE_COMMAND} -E copy "${PROJECT_SOURCE_DIR}/${PROJECT_NAME}/roomPacks/Manic Miner/config.json" "${OUTPUT_DIR}/${PROJECT_NAME}.pdx/roomPacks/Manic Miner/"
    COMMAND ${CMAKE_COMMAND} -E copy "${PROJECT_SOURCE_DIR}/${PROJECT_NAME}/roomPacks/Manic Miner \\(Original\\)/rooms.json" "${OUTPUT_DIR}/${PROJECT_NAME}.pdx/roomPacks/Manic Miner \\(Original\\)/"
    COMMAND ${CMAKE_COMMAND} -E copy "${PROJECT_SOURCE_DIR}/${PROJECT_NAME}/roomPacks/Manic Miner \\(Original\\)/config.json" "${OUTPUT_DIR}/${PROJECT_NAME}.pdx/roomPacks/Manic Miner \\(Original\\)/"
    COMMAND ${CMAKE_COMMAND} -E copy "${PROJECT_SOURCE_DIR}/${PROJECT_NAME}/launcher/icon-highlighted/animation.txt" "${OUTPUT_DIR}/${PROJECT_NAME}.pdx/launcher/icon-highlighted/"
    COMMENT "Build playdate Binary"
    )

add_custom_target("simulator"
    DEPENDS ${OUTPUT_DIR}/${PROJECT_NAME}.pdx
    )
add_custom_command(TARGET "simulator" POST_BUILD
    DEPENDS ${OUTPUT_DIR}/${PROJECT_NAME}.pdx
    COMMAND ${SIMULATOR_BIN} ${OUTPUT_DIR}/${PROJECT_NAME}.pdx
    COMMENT "Run on simulator"
    )

