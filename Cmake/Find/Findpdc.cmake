# Copyright (c) 2022-2023 kounch
# SPDX-License-Identifier: BSD-2-Clause

find_program(PDC_BINARY NAMES pdc
	         HINTS ${PDC_PATH})

include(FindPackageHandleStandardArgs)

find_package_handle_standard_args(pdc DEFAULT_MSG
								  PDC_BINARY)

mark_as_advanced(PDC_BINARY)

set(PDC_BINARY ${PDC_BINARY})

if(NOT PDC_FOUND)
	MESSAGE(FATAL_ERROR "pdc not found")
endif()
