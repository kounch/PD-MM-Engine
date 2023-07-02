#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# -*- mode: Python; tab-width: 4; indent-tabs-mode: nil; -*-
# Do not modify previous lines. See PEP 8, PEP 263.
# pylint: disable=too-many-lines
"""
Copyright (c) 2023, kounch
All rights reserved.

SPDX-License-Identifier: BSD-2-Clause

This is a tool that tries to analyze and extract data from ZX Spectrum
Manic Miner games and then create roomPack files for the Playdate Manic
Miner Engine.
"""

from __future__ import print_function
from typing import Any, Union, Optional
from PIL import Image, ImageDraw
import logging
import sys
import argparse
import os
import pathlib
from binascii import unhexlify
import json
import tempfile
import shutil
import subprocess

__MY_VERSION__ = '1.0.0'

LOGGER = logging.getLogger(__name__)
LOGGER.setLevel(logging.INFO)
LOG_FORMAT = logging.Formatter(
    '%(asctime)s [%(levelname)-5.5s] - %(name)s: %(message)s')
LOG_STREAM = logging.StreamHandler(sys.stdout)
LOG_STREAM.setFormatter(LOG_FORMAT)
LOGGER.addHandler(LOG_STREAM)

if sys.version_info < (3, 6, 0):
    LOGGER.error('This software requires Python version 3.6 or greater')
    sys.exit(1)


def main():
    """Main routine"""

    LOGGER.debug('Starting up...')
    str_outdir: str = ''
    arg_data: dict[str, Any] = parse_args()

    str_file: str = arg_data['input_file']
    str_outdir = arg_data['output_dir']
    str_name = arg_data['name']

    print(f'New roomPack: {str_name}')
    try:
        with open(str_file, "rb") as bin_file:
            b_data: bytes = bin_file.read()
    except FileNotFoundError:
        LOGGER.error('Input file does not exist')
        sys.exit(2)

    l_format = detect_format(b_data, arg_data['force'])
    if not l_format:
        LOGGER.error('Unknown file format')
        sys.exit(3)

    print(f'Using {l_format[0]} format...')

    # Main configuration
    dict_config = create_config(str_name, b_data, l_format)
    dict_config['Special'] = {}
    arr_single = []
    arr_multiple = []
    arr_blocks = []
    arr_rooms = []

    # Main image
    str_main: str = os.path.join(str_outdir, 'main-8.png')
    create_main_img(str_outdir, str_main, b_data, l_format)

    # Willy
    i_offset = get_offset(512, l_format)
    build_sprites(b_data, l_format, i_offset, 16, 8, 0, arr_multiple)

    # Rooms
    for i in range(0, 20):
        print(f'Room: {i + 1}')

        dict_room = {}
        r_offset = 12288 + i * 1024

        # Room layout
        i_offset = get_offset(r_offset, l_format)
        arr_b: bytes = b_data[i_offset:i_offset + 512]
        str_b = ''.join('{:02X}'.format(x) for x in arr_b)
        arr_str_b = []
        for j in range(0, 16):
            arr_str_b.append(str_b[j * 64:(j + 1) * 64])
        dict_room['data'] = arr_str_b
        dict_room['id'] = i

        i_offset = get_offset(r_offset + 512, l_format)
        arr_b = b_data[i_offset:i_offset + 32]
        str_name = arr_b.decode('ascii').strip()
        dict_room['name'] = str_name
        dict_room['special'] = {}
        if 'Kong' in str_name:
            dict_room['special']['Kong'] = True
        if 'Skylab' in str_name:
            dict_room['special']['Skylab'] = True
        if 'Eugene' in str_name:
            dict_room['special']['Eugene'] = True
        if 'Solar' in str_name:
            dict_room['special']['Solar'] = True

        # Block graphics and attrs
        i_offset = get_offset(r_offset + 544, l_format)
        b_attr = build_sprites(b_data, l_format, i_offset, 8, 8, 1, arr_blocks)
        dict_room['attr'] = ''.join('{:02X}'.format(x) for x in b_attr)

        # Horizontal guardians
        i_offset = get_offset(r_offset + 702, l_format)
        dict_room['HGuardians'] = build_hguardians(b_data, i_offset)

        # Start position
        i_offset = get_offset(r_offset + 616, l_format)
        arr_b = b_data[i_offset:i_offset + 7]
        dict_room['start'] = {}
        dict_room['start']['left'] = arr_b[2] != 0
        dict_room['start']['addr'] = format(
            int.from_bytes(arr_b[4:6], 'little'), f'02X')

        # Conveyor
        i_offset = get_offset(r_offset + 623, l_format)
        arr_b = b_data[i_offset:i_offset + 7]
        dict_room['conveyor'] = {}
        dict_room['conveyor']['left'] = arr_b[0] == 0
        dict_room['conveyor']['addr'] = format(
            int.from_bytes(arr_b[1:3], 'little'), f'02X')

        # Items
        i_offset = get_offset(r_offset + 629, l_format)
        dict_room['items'] = build_items(b_data, i_offset)

        # Portal Graphic
        i_offset = get_offset(r_offset + 656, l_format)
        build_sprites(b_data, l_format, i_offset, 16, 1, 0, arr_single)

        # Item
        i_offset = get_offset(r_offset + 692, l_format)
        build_sprites(b_data, l_format, i_offset, 8, 1, 0, arr_blocks)

        # Portal data
        i_offset = get_offset(r_offset + 688, l_format)
        arr_b = b_data[i_offset:i_offset + 7]
        dict_room['portal'] = {}
        dict_room['portal']['id'] = len(arr_single)
        dict_room['portal']['addr'] = format(
            int.from_bytes(arr_b[:2], 'little'), f'02X')

        # Vertical guardians
        i_offset = get_offset(r_offset + 733, l_format)
        dict_room['VGuardians'] = build_vguardians(b_data, i_offset)

        # Special graphics
        dict_special = {0: 'Swordfish', 1: 'Plinth', 2: 'Boot', 4: 'Eugene'}
        if i in dict_special:
            i_offset = get_offset(r_offset + 736, l_format)
            build_sprites(b_data, l_format, i_offset, 16, 1, 0, arr_single)
            dict_config['Special'][dict_special[i]] = len(arr_single)

        # Guardian graphics
        i_offset = get_offset(r_offset + 768, l_format)
        build_sprites(b_data, l_format, i_offset, 16, 8, 0, arr_multiple)

        arr_rooms.append(dict_room)

    str_config: str = os.path.join(str_outdir, 'config.json')
    with open(str_config, 'w', encoding='utf-8') as f_handle:
        json.dump(dict_config, f_handle)

    str_rooms: str = os.path.join(str_outdir, 'rooms.json')
    with open(str_rooms, 'w', encoding='utf-8') as f_handle:
        f_handle.write(json.dumps(arr_rooms, indent=4))

    save_spritesheet(arr_blocks, 8, 9, str_outdir, 'rooms-8')
    save_spritesheet(arr_single, 16, 4, str_outdir, 'single-8')
    save_spritesheet(arr_multiple, 16, 4, str_outdir, 'multiple-8')

    if arg_data['compile']:
        compile_images(str_outdir)


def parse_args() -> dict[str, Any]:
    """
    Parses command line
    :return: Dictionary with different options
    """
    global LOGGER  # pylint: disable=global-variable-not-assigned
    global IS_COL_TERM  # pylint: disable=global-statement

    values: dict[str, str | bool] = {}
    values['input_file'] = ''
    values['output_dir'] = ''
    values['name'] = ''
    values['compile'] = False
    values['force'] = ''

    parser = argparse.ArgumentParser(
        description='roomPack extractor for Playdate Manic Miner Engine',
        epilog='Analyze and extract data from ZX Spoectrum Manic Miner games')
    parser.add_argument('-v',
                        '--version',
                        action='version',
                        version=f'%(prog)s {__MY_VERSION__}')
    parser.add_argument('-i',
                        '--input_file',
                        required=True,
                        action='store',
                        dest='input_file',
                        help='Binary file with MM Data (org 32768)')
    parser.add_argument('-d',
                        '--output_dir',
                        required=False,
                        action='store',
                        dest='output_dir',
                        help='Output directory for roomPack')
    parser.add_argument('-c',
                        '--compile',
                        required=False,
                        action='store_true',
                        dest='compile',
                        help='Try to compile the final roomPack using pdc')
    parser.add_argument('-b',
                        '--bugbyte',
                        required=False,
                        action='store_true',
                        dest='bugbyte',
                        help='Force using Bug Byte version extractor')
    parser.add_argument('-s',
                        '--softwareprojects',
                        required=False,
                        action='store_true',
                        dest='softwareprojects',
                        help='Force using Softare Projects version extractor')

    parser.add_argument('--debug', action='store_true', dest='debug')

    arguments = parser.parse_args()

    if arguments.debug:
        print('Debugging Enabled!!')
        LOGGER.setLevel(logging.DEBUG)

    LOGGER.debug(sys.argv)

    if arguments.input_file:
        values['input_file'] = os.path.abspath(arguments.input_file)

    if not os.path.isfile(values['input_file']):
        LOGGER.error('Input file does not exist')
        sys.exit(2)

    if arguments.output_dir:
        values['output_dir'] = os.path.abspath(arguments.output_dir)
    else:
        values['output_dir'] = os.path.splitext(values['input_file'])[0]

    if arguments.compile:
        values['compile'] = arguments.compile

    if arguments.bugbyte and arguments.softwareprojects:
        LOGGER.error('Invalid arguments!')
        sys.exit(2)

    if arguments.bugbyte:
        values['force'] = 'Bug Byte'
    elif arguments.softwareprojects:
        values['force'] = 'Software Projects'

    if not os.path.isdir(values['output_dir']):
        pathlib.Path(values['output_dir']).mkdir(parents=True, exist_ok=True)

    if not values['name']:
        values['name'] = os.path.split(values['output_dir'])[1]

    return values


def create_config(str_packname: str, bin_data: bytes,
                  list_format: list[Any]) -> dict[str, Any]:
    """Creates the main roomPack config data"""
    main_data: dict[str, Union[str, int, list[Any]]] = {}
    main_data['Name'] = str_packname
    main_data['Scale'] = 1
    main_data['Menu'] = 'main-8'
    main_data['SingleSprites'] = 'single-8'
    main_data['MultipleSprites'] = 'multiple-8'
    main_data['Blocks'] = 'rooms-8'
    main_data['Levels'] = 'rooms'
    main_data['TitleMusic'] = []
    main_data['ShowPiano'] = False
    main_data['Banner'] = []
    main_data['InGameMusic'] = []

    dict_data: dict[str, tuple[int, int, str]] = {}
    dict_data['TitleMusic'] = (1134, 285, 'arr_3ints')
    dict_data['InGameMusic'] = (1420, 64, 'arr_ints')
    dict_data['Banner'] = (7424, 256, 'str')

    for str_element in dict_data:
        i_offset, i_size, str_kind = dict_data[str_element]
        i_offset = get_offset(i_offset, list_format)
        arr_b: bytes = bin_data[i_offset:i_offset + i_size]

        element_data: Union[list[str], list[int], list[list[int]]] = ['']
        if str_kind == 'str':
            element_data = [arr_b.decode('ascii').replace('\u007f', '©')]
        elif str_kind == 'arr_ints':
            element_data = [int(x) for x in arr_b]
        elif str_kind == 'arr_3ints':
            element_data = []
            for i in range(0, len(arr_b), 3):
                element_data.append([int(x) for x in arr_b[i:i + 3]])

        main_data[str_element] = element_data

    return main_data


def create_main_img(str_outdir: str, str_image: str, bin_data: bytes,
                    list_format: list[Any]):
    i_offset = get_offset(8192, list_format)
    i_size = 4096
    arr_b: bytes = bin_data[i_offset:i_offset + i_size]
    tmp_img = Image.new("RGBA", (256, 128))
    draw = ImageDraw.Draw(tmp_img)
    for iy in range(0, 128):
        x = 0
        for i in range(0, 32):
            ty = iy // 8 + iy % 8 * 8
            if iy > 64:
                ty += 56
            i_byte = int(arr_b[i + iy * 32])
            str_byte = format(i_byte, '08b')
            for j in range(0, 8):
                if str_byte[j] == '1':
                    draw.point((x, ty), fill=(0, 0, 0))
                x += 1
    str_main: str = os.path.join(str_outdir, 'main-8.png')
    tmp_img.save(str_main)


def build_sprites(bin_data: bytes, list_format: list[Any], i_addr: int,
                  i_width: int, i_len: int, i_jump: int,
                  arr_imgs: list[Any]) -> bytes:

    arr_a: bytes = b''
    arr_b: bytes = bin_data[i_addr:i_addr + i_len * (i_width + i_jump) *
                            (i_width // 8)]
    for i in range(0, i_len):
        tmp_img = Image.new("RGBA", (i_width, i_width))
        draw = ImageDraw.Draw(tmp_img)
        i_sprite = i * (i_width // 8 * i_width + i_jump)
        if i_jump > 0:
            arr_a += arr_b[i_sprite:i_sprite + 1]
            i_sprite += i_jump
        for y in range(0, i_width):
            i_line = i_sprite + y * i_width // 8
            i_bytes = int.from_bytes(arr_b[i_line:i_line + i_width // 8])
            str_bytes = format(i_bytes, f'0{i_width}b')
            for x in range(0, i_width):
                if str_bytes[x] == '1':
                    draw.point((x, y), fill=(0, 0, 0))

        arr_imgs.append(tmp_img)

    return arr_a


def save_spritesheet(arr_sprites: list[Any], i_pixel_w: int, i_w: int,
                     str_dir: str, str_name: str):
    tmp_img = Image.new(
        "RGBA",
        (i_pixel_w * i_w, i_pixel_w * round(len(arr_sprites) / i_w + 0.5)))
    i_count = 0
    for i_index in range(0, len(arr_sprites)):
        tmp_x = i_count % i_w
        tmp_y = int(i_count / i_w)
        tmp_img.paste(arr_sprites[i_index],
                      (tmp_x * i_pixel_w, tmp_y * i_pixel_w))
        i_count += 1

    str_file: str = os.path.join(
        str_dir, f'{str_name}-table-{i_pixel_w}-{i_pixel_w}.png')
    tmp_img.save(str_file)


def build_hguardians(bin_data: bytes, i_addr: int) -> list[dict[str, str]]:
    arr_b: bytes = bin_data[i_addr:i_addr + 28]

    arr_guardians = []
    for i in range(0, 4):
        j = i * 7
        if arr_b[j] == 0xff:
            break
        else:
            str_b = ''.join('{:02X}'.format(x) for x in arr_b[j:j + 7])
            tmp_guardian = {}
            tmp_guardian['attr'] = str_b[:2]
            tmp_guardian['addr'] = str_b[4:6] + str_b[2:4]
            tmp_guardian['location'] = str_b[6:8]
            tmp_guardian['frame'] = str_b[8:10]
            tmp_guardian['min'] = str_b[10:12]
            tmp_guardian['max'] = str_b[12:14]
            arr_guardians.append(tmp_guardian)

    return arr_guardians


def build_vguardians(bin_data: bytes, i_addr: int) -> list[dict[str, str]]:
    arr_b: bytes = bin_data[i_addr:i_addr + 28]

    arr_guardians = []
    for i in range(0, 4):
        j = i * 7
        if arr_b[j] == 0xff:
            break
        else:
            str_b = ''.join('{:02X}'.format(x) for x in arr_b[j:j + 7])
            tmp_guardian = {}
            tmp_guardian['attr'] = str_b[:2]
            tmp_guardian['frame'] = str_b[4:6]
            tmp_guardian['start'] = str_b[2:4]
            tmp_guardian['location'] = str_b[6:8]
            tmp_guardian['dy'] = str_b[8:10]
            tmp_guardian['min'] = str_b[10:12]
            tmp_guardian['max'] = str_b[12:14]
            arr_guardians.append(tmp_guardian)

    return arr_guardians


def build_items(bin_data: bytes, i_addr: int) -> list[str]:
    arr_b: bytes = bin_data[i_addr:i_addr + 27]

    arr_items = []
    for i in range(0, 5):
        j = i * 5
        if arr_b[j] == 0xff:
            break
        else:
            str_b = format(int.from_bytes(arr_b[j + 1:j + 3], 'little'),
                           f'02X')
            arr_items.append(str_b)

    return arr_items


def compile_images(str_outdir: str):
    print("Compiling...", end=None)
    with tempfile.TemporaryDirectory() as str_tmpdir:
        str_buildir = os.path.join(str_tmpdir, 'fake')
        pathlib.Path(str_buildir).mkdir(parents=True, exist_ok=True)

        str_tmpfile = os.path.join(str_buildir, 'main.lua')
        with open(str_tmpfile, 'w') as f_tmp:
            f_tmp.write('function playdate.update() end')

        for basename in os.listdir(str_outdir):
            if basename.endswith('.png') or basename.endswith('.wav'):
                pathname = os.path.join(str_outdir, basename)
                pathdest = os.path.join(str_buildir, basename)
                if os.path.isfile(pathname):
                    shutil.move(pathname, pathdest)

        str_pdx = str_buildir + '.pdx'
        if os.path.isdir(str_pdx):
            shutil.rmtree(str_pdx)
        return_code = subprocess.call(f'pdc "{str_buildir}"', shell=True)
        if return_code == 0:
            for basename in os.listdir(str_pdx):
                if basename.endswith('.pdi') or basename.endswith(
                        '.pdt') or basename.endswith('.pda'):
                    pathname = os.path.join(str_pdx, basename)
                    pathdest = os.path.join(str_outdir, basename)
                    if os.path.isfile(pathname):
                        shutil.move(pathname, pathdest)
            print("OK", end=None)
        else:
            print("Failed!")


def get_offset(i_addr: int, list_format: list[Any]) -> int:
    """Calculate (if needed) addr with offset depending on address)"""
    i_offset = 0
    if list_format:
        for arr_test in list_format[1]:
            if i_addr < arr_test[0]:
                break
            else:
                i_offset = arr_test[1]

    return i_addr + i_offset


def detect_format(bin_data: bytes,
                  str_force: str) -> list[Union[str, list[list[int]]]]:
    """Tries to detect if it's Bug Byte or Software Projects Binary"""

    i_offset: int = 1120
    dict_kind: dict[str, Any] = {
        '1F0F1F1E1B1F1E1F1F171F0F1F1D': ['Bug Byte', []],
        '0F1F1F0F1F1E1B1F1D1F171F1F1B':
        ['Software Projects', [[1134, 6], [3114, 13], [3187, 11], [7424, 0]]]
    }

    data_found: list[Any] = []

    for guess in dict_kind:
        if str_force != '':
            if str_force == dict_kind[guess][0]:
                data_found = dict_kind[guess]
                break
        else:
            magic_bin: bytes = unhexlify(guess)
            if bin_data[i_offset:i_offset + len(magic_bin)] == magic_bin:
                data_found = dict_kind[guess]
                break

    return data_found


if __name__ == '__main__':
    main()
