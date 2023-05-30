# Manic Miner Level Pack Extractor for Playdate Manic Miner Engine

Copyright (c) 2023, kounch

All rights reserved.

---

Select your desired language / Elija idioma:

- Click [this link for English](#english)

- Pulse [este enlace para Castellano](#castellano)

---

## English

This script can analyze and extract data from ZX Spectrum Manic Miner games and then create a Levels Pack file structure for the Playdate Manic Miner Engine.

### Requirements

The script can be invoked directly using Python (version 3.6 or later). It requires [Pillow (the Python Imaging Library)](https://pypi.org/project/Pillow/) and, optionally (for release purposes) the [Playdate SDK](https://play.date/dev/).

You can install Pillow using `pip`. For example, to have a private virtual environment only for this script, using commands like this on Linux or MacOS:

    python3 -m venv PDMMEngineExtractor
    ./PDMMEngineExtractor/bin/python3 -m pip install Pillow

### Usage

Invoke the script using a Python environment with Pillow installed:

    ...python3 ...MMlevelsPackExtractor.py [-h] [-v] -i INPUT_FILE [-d OUTPUT_DIR] [-c] [-b] [-s] [--debug]

Command line options:

    -h, --help                               Show usage help message and exit
    -v, --version                            Show program's version number and exit
    -i INPUT_FILE, --input_file INPUT_FILE   Binary file with MM Data (org 32768)
    -d OUTPUT_DIR, --output_dir OUTPUT_DIR   Output directory for Levels Pack
    -c, --compile                            Try to compile the final Levels Pack using pdc
    -b, --bugbyte                            Force using Bug Byte version extractor
    -s, --softwareprojects                   Force using Softare Projects version extractor

The script needs a binary data file with a RAM dump (or extracted for example from a tape file) with the information starting from address 32768 (0x8000) and tries to guess what kind of binary date the file has, between the original release (Bug Byte) and the Software Projects release. Then it will try to extract the level and graphic data and dump it to Levels Pack files that the Manic Miner Engine for Playdate can read and use.

Optionally, if the [Playdate SDK](https://play.date/dev/) is installed and in the shell PATH, it can also try to convert the extracted PNG image files and existing WAV sound files to the PDI, PDT and PDA file formats used by the Playdate console.

You can obtain several Manic Miner engine ZX Spectrum games from [JSW Central](https://jswcentral.org), and then,and then, after extracting the binary data from the corresponding tape file, use the script to create a basic Levels Pack to edit and refine.

### Levels Pack format

A Levels Pack for Playdate MM engine is comprised of the following:

- A `config.json` file with metadata like the music notes, the text to show, the name for the rest of the Levels Pack files, etc.
- Several graphic image files with the main game screen, sprites for the player and enemies, as well as the tiles that are assembled to make a room in the game
- A `rooms.json` file with the layout for each of the rooms, as well as the enemies location, movement constrains, etc.
- An (optional) sound file to be played when all the rooms are finished, and before starting again with the first one

#### Main JSON

The main `config.json` file is an object with the following structure:

    {
    "Name":  -> Internal name for the pack
    "Scale":  -> 1 for original 8x8 ZX Spectrum graphics, 1.5 for enhanced 12x12 Playdate graphics
    "Menu":  -> Name (without extension ) of the main menu image file
    "SingleSprites":  -> Name (without extension ) of the static spritesheet table file
    "MultipleSprites":  -> Name (without extension ) of the animated spritesheet table file
    "Blocks":  -> Name (without extension ) of the room blocks imagetable file
    "Levels":  -> Name (without extension ) of the rooms JSON file
    "TitleMusic": [
        -> Array of Arrays with [length, counter, counter] for each pair of notes of main menu tune music
        ],
    "ShowPiano": -> If true, the animation of the piano on the title screen will be shown
    "Banner": [
        -> Array of ASCII text strings to show as scrolling text after the music in the main menu screen
        ],
    "InGameMusic": [
        -> List of numbers with counter data for each note of the in-game tune
        ],
    "Special": {
        "Swordfish": -> ID in the static sprites table for the ending game image
        "Plinth":  -> ID in the static sprites table for the plinth game over image
        "Boot":  -> ID in the static sprites table for the boot game over image
        "Eugene": -> ID in the static sprites table for Eugene's sprite
        }
    }

Music notes length is converted to seconds using this formula: `seconds = 0.003625 * length`
Music counter numbers are converted to frequency (to play a note) using this formula: `freq = 440 * 109 / counter`

Since most of this information is directly mapped from the original game data structure, see [Dr. Andrew Broad Manic Miner Room-Format](https://www.icemark.com/dataformats/manic/mmformat.htm) for more information. See also [All aboard the impulse train: an analysis of the two- channel title music routine in Manic Miner](https://rke.abertay.ac.uk/ws/portalfiles/portal/8564089/McAlpine_AllAboardTheImpulseTrain_Author_2015.pdf) for an explanation of how the original game music is made and encoded.

##### Converting basic Levels Pack to enhanced

To convert a basic Levels Pack (with original 8x8 graphics) to a enhanced one for playdate (with 12x12 graphics), you should only have to scale the corresponding sprite and image files, and then edit the main `config.json`, changing `"Scale": 1` to `"Scale": 1.5`

#### Rooms JSON

The rooms (levels) JSON file is a list of objects, each one of them with the following structure:

    {
    "data": [
        -> An array of 16 text strings, each one of them made by 32 1-byte hexadecimal numbers, representint the attribute
           of a tile in the room.
        ],
    "id": -> Unique number for each level used, for example, to get the image tile from the block images file
    "name": -> Name of the level, shown down the in-game screen
    "special": {
        -> If it contains "Eugene", "Kong, "Skylab" or "Solar" apply the corresponding special rules for this room
        },
    "attr": -> String made by 8 1-byte hexadecimal numbers, each one corresponding to the attribute that maps to 
               the corresponding tile for this room, and is being used in the "data" property above.
    "HGuardians": [
        {
            "attr": -> Used to calculate a horizontal guardian's starting face (left or right) and speed
            "addr": -> Address used to calculate a guardian maximum and minimum coordinates
            "location": -> Start location of guardian on screen
            "frame": -> Start animation fram for guardian
            "min": -> Limit to guardian movement
            "max": -> Limit to guardian movement
            }
        ],
    "start": {
        "left": -> Starting face for the player (left or right)
        "addr": -> Starting position for the player
        },
    "conveyor": {
        "left": -> Conveyor direction
        "addr": -> Unused
        },
    "items": [
        -> List with up to five locations on screen for key items
        ],
    "portal": {
        "id": -> Index in the static sprites image table for the door image
        "addr": -> Location on screen of the door
        },
    "VGuardians": [
            "attr": -> Unused
            "frame": -> Start animation frame for this vertical guardian
            "start": -> Used to calculate the starting coordinates
            "location": -> Used to calculate the starting coordinates
            "dy": -> Indicates if the movement starts upwards or downwards and the speed
            "min": -> Limit to guardian movement
            "max": -> Limit to guardian movement 
        ]
    }

Since most of this information is directly mapped from the original game data structure, see [Dr. Andrew Broad Manic Miner Room-Format](https://www.icemark.com/dataformats/manic/mmformat.htm) for more information.

#### Image Data

All the image files should be 1-bit with optional transparency (specially for sprite images)

##### Main Image

The main image shown in the main game menu, and its top third is also merged with the last level room layout ("The Final Barrier" in the original game). It can be of any size up to 384x192 pixels (bigger images will be cropped) and does not need any transparency since it will always be drawn behind everything else.

##### Sprites

Depending on the scale, the sprite images can be 16x16 pixels or 24x24 pixels in size. There are two files:

- Static (single) sprites: the portal doors, Eugene, the game over screen boot and plinth, etc.
- Animated (multiple) sprites: These are in groups of 4 or 8 images (when bidirectional), and the first eight are always used for the player (Willy) graphics

Bidirectional graphics use Sprites 1 to 4 for the right-facing frames and Sprites 7 to 8 for the left-facing frames, where Sprites 1 and 5 are the leftmost frames, and Sprites 4 and 8 are the rightmost frames. There is an exception for graphics used in "Skylab" rooms where the first image is used for movement and the remaining seven are used for a destruction effect at the end.

See [Dr. Andrew Broad Manic Miner Room-Format](https://www.icemark.com/dataformats/manic/mmformat.htm) for more information.

For the original game, there are 24 static sprites and 168 animated sprites.

Sprite images should use transparency for their background or else strange artifacts will happen.

##### Blocks

Depending on the scale, the block images can be 8x8 pixels or 12x12 pixels in size. They are stored in groups of 9, and there is one group for each of the level rooms, so the original game has 180 images.

For each group each of the block images is used for a different block type or element, with the following order:

1. Background
2. Floor
3. Crumbling Floor
4. Wall
5. Conveyor
6. Nasty 1
7. Nasty 2
8. Spare
9. Key Item

The spare type is used for switches, extra floor or other.

See [Dr. Andrew Broad Manic Miner Room-Format](https://www.icemark.com/dataformats/manic/mmformat.htm) for more information.

#### Sound Data

The source for the optional ending sound should be an ADPCM encoded WAV (Microsoft) sound file. See [The official Playdate docs](https://sdk.play.date/1.13.7/Inside%20Playdate.html#M-sound) for more information.

---

## Castellano

Este script intenta analizar y extraer datos de juegos ZX Spectrum Manic Miner y luego crear una estructura de archivos de paquetes de niveles para el motor de Manic Miner para Playdate.

### Requisitos

El script puede ser invocado directamente usando Python (versión 3.6 o posterior). Requiere [Pillow (the Python Imaging Library)](https://pypi.org/project/Pillow/) y, opcionalmente (para generar automáticamente los ficheros finales) [SDK de Playdate](https://play.date/dev/).

Se puede instalar Pillow usando `pip`. Por ejemplo, para tener un entorno virtual privado sólo para este script, usando unos comandos similares a estos en Linux o MacOS:

    python3 -m venv PDMMEngineExtractor
    ./PDMMEngineExtractor/bin/python3 -m pip install Pillow

### Uso

Invocar el script utilizando un entorno Python con Pillow instalado:

    ...python3 ...MMlevelsPackExtractor.py [-h] [-v] -i ARCHIVO_DE_ENTRADA [-d_DIR_DE_SALIDA] [-c] [-b] [-s] [--debug]

Opciones de línea de comandos:

    -h, --help Mostrar el mensaje de ayuda de uso y salir
    -v, --version Mostrar la versión y salir
    -i ARCHIVO_DE_ENTRADA, -archivo_de_entrada ARCHIVO_DE_ENTRADA Archivo binario con datos de MM (org 32768)
    -d DIR_SALIDA, --output_dir DIR_SALIDA Directorio de salida para el paquete de niveles
    -c, --compile Intenta compilar el paquete final usando pdc
    -b, --bugbyte Forzar el uso del extractor de versiones Bug Byte
    -s, --softwareprojects Forzar el uso del extractor de versiones Softare Projects

El script necesita un fichero binario de datos con un volcado de RAM (o extraído por ejemplo de un fichero de cinta) con los datos que comienzan en la dirección 32768 (0x8000) e intenta adivinar qué tipo formato binario tiene, entre la versión original (Bug Byte) y la versión de Software Projects. Luego intenta extraer los datos de niveles y gráficos y volcarlos a ficheros de un paquete de niveles que el motor de Manic Miner para Playdate pueda leer y utilizar.

Opcionalmente, si el [SDK de Playdate](https://play.date/dev/) está instalado y en el PATH de la shell, también puede intentar convertir los archivos de imagen PNG extraídos y los archivos de sonido WAV existentes a los formatos de archivo PDI, PDT y PDA utilizados por la consola Playdate.

Se pueden obtener juegos que usan el motor de Manic Miner de ZX Spectrum en [JSW Central](https://jswcentral.org),y así, después de extraer los datos binarios del archivo de cinta correspondiente, utilizar este script para crear un pack de niveles básico para luego editarlo y mejorarlo.

### Formato del paquete de niveles

Un paquete niveles del motor MM para Playdate se compone de lo siguiente:

- Un archivo `config.json` con metadatos como las notas musicales, el texto a mostrar, el nombre para el resto de archivos del paquete, etc.
- Varios archivos de imágenes gráficas con la pantalla principal del juego, sprites del personaje principal y los enemigos, así como los bloques que se usan para formar una nivel en el juego.
- Un archivo `rooms.json` con la distribución de cada una de las niveles, así como la ubicación de los enemigos, las restricciones de movimiento, etc.
- Un archivo de sonido (opcional) que se reproducirá cuando todas se supere la nivel final, y antes de empezar de nuevo con la primera.

#### JSON principal

El archivo principal `config.json` es un objeto con la siguiente estructura:

    {
    "Name  -> Nombre interno del pack
    "Scale":  -> 1 para gráficos originales (8x8) de ZX Spectrum, 1.5 para gráficos mejorados (12x12) de Playdate
    "Menu":  -> Nombre (sin extensión ) del archivo de imagen del menú principal
    "SingleSprites":  -> Nombre (sin extensión ) del archivo de tabla de sprites estáticos
    "MultipleSprites":  -> Nombre (sin extensión ) del archivo de tabla de la hoja de sprites animados
    "Blocks":  -> Nombre (sin extensión ) del archivo de tabla de imágenes de los bloques de la sala
    "Levels": -> Nombre (sin extensión ) del archivo JSON de las habitaciones
    "TitleMusic": [
        -> Array de Arrays con [longitud, contador, contador] para cada par de notas de la música del menú principal
        ],
    "ShowPiano": -> Si es true, se mostrará la animación del piano en la pantalla de título.
    "Banner": [
        -> Array de cadenas de texto ASCII para mostrar después de la música en la pantalla del menú principal
        ],
    "InGameMusic": [
        -> Lista de números con datos de contador para cada nota de la melodía del juego
        ],
    "Special": {
        "Swordfish": -> ID en la tabla estática de sprites para la imagen final del juego
        "Plinth":  -> ID en la tabla estática de sprites para la columna de fin de partida
        "Boot":  -> ID en la tabla estática de sprites para la bota de fin de partida
        "Eugene": -> ID en la tabla estática de sprites para el sprite de Eugene
        }
    }

La duración de las notas musicales se convierte en segundos mediante esta fórmula: `segundos = 0,003625 * duración`
Los números del contador de música se convierten a frecuencias (para tocar una nota) mediante esta otra fórmula: `frecuencia = 440 * 109 / contador`

Dado que la mayor parte de esta información está directamente obtenida desde la estructura de datos original del juego, véase [Dr. Andrew Broad Manic Miner Room-Format](https://www.icemark.com/dataformats/manic/mmformat.htm) para más información. Véase también [All aboard the impulse train: an analysis of the two- channel title music routine in Manic Miner](https://rke.abertay.ac.uk/ws/portalfiles/portal/8564089/McAlpine_AllAboardTheImpulseTrain_Author_2015.pdf) para una explicación de cómo se hace y codifica la música original del juego.

##### Conversión de un paquete de niveles básico a mejorado

Para convertir un paquete de niveles básico (con gráficos originales 8x8) en uno mejorado para playdate (con gráficos 12x12), debería ser sufucieente que escalar los archivos de sprites e imágenes correspondientes al tamaño adecuado, y luego editar el archivo principal `config.json`, cambiando `"Scale": 1` por `"Scale": 1.5`

#### Fichero de niveles JSON

El fichero JSON de las habitaciones (niveles) es una lista de objetos, cada uno de ellos con la siguiente estructura:

    {
    "data": [
        -> Un array de 16 cadenas de texto, cada una de ellas formada por 32 números hexadecimales de 1 byte, que representan el atributo de un bloque en la habitación.
        ],
    "id": -> Número único para cada nivel. utilizado, por ejemplo, para obtener la imagen del bloque corespondiente desde el 
             archivo de imágenes.
    "name": -> Nombre del nivel, que se muestra abajo en la pantalla del juego
    "special": {
        -> Si contiene "Eugene", "Kong", "Skylab" o "Solar" aplica las reglas especiales correspondientes para esta sala
        },
    "attr": -> Cadena formada por 8 números hexadecimales de 1 byte, cada uno correspondiente al atributo que mapea a 
               el bloqu correspondiente para esta sala, y se está utilizando en la propiedad "data" anterior.
    "HGuardians": [
        {
            "attr": -> Se usa para calcular la orientación inicial (izquierda o derecha) y la velocidad de un guardián horizontal
            "addr": -> Dirección utilizada para calcular las coordenadas máximas y mínimas de un guardián
            "location": -> Ubicación inicial del guardián en la pantalla
            "frame": -> Frame de inicio de la animación del guardián
            "min": -> Límite de movimiento del guardián
            "max": -> Límite de movimiento del guardián
            }
        ],
    "start": {
        "izquierda": -> Orientación de inicio para el personaje del jugador (izquierda o derecha).
        "addr": -> Posición inicial para el personaje del jugador
        },
    "conveyor": {
        "left": -> Dirección del transportador
        "addr": -> No utilizado
        },
    "items": [
        -> Lista con hasta cinco ubicaciones en pantalla para los objetos llave
        ],
    "portal": {
        "id": -> Índice en la tabla de imágenes estáticas de sprites para la imagen de la puerta
        "addr": -> Ubicación en pantalla de la puerta
        },
    "VGuardians": [
            "attr": -> Sin usar
            "frame": -> Frame de inicio de la animación para este guardián vertical
            "start": -> Se utiliza para calcular las coordenadas de inicio
            "location": -> Se utiliza para calcular las coordenadas de inicio
            "dy": -> Indica si el movimiento comienza hacia arriba o hacia abajo, y la velocidad
            "min": -> Límite del movimiento del guardián
            "max": -> Límite del movimiento del guardián 
        ]
    }

Dado que la mayor parte de esta información se extrae directamente de la estructura de datos original del juego, consulte [Dr. Andrew Broad Manic Miner Room-Format](https://www.icemark.com/dataformats/manic/mmformat.htm) para obtener más información sobre la misma.

#### Datos de imágenes

Todos los archivos de imagen deben ser de 1 bit con transparencia opcional (especialmente para imágenes de sprites)

##### Imagen principal

La imagen que se muestra en el menú principal del juego, y cuyo tercio superior también se fusiona con el diseño de la sala del último nivel ("The final barrier" en el juego original). Puede ser de cualquier tamaño hasta 384x192 píxeles (las imágenes más grandes se recortarán) y no necesita ninguna transparencia ya que siempre se dibujará detrás de todo lo demás.

##### Archivos de Sprites

Dependiendo de la escala, las imágenes de los sprites pueden tener un tamaño de 16x16 píxeles o 24x24 píxeles. Existen dos archivos:

- Sprites estáticos (individuales): las puertas del portal, Eugene, la bota y la columna de fin de juego, etc.
- Sprites animados (múltiples): Se presentan en grupos de 4 u 8 imágenes (cuando son bidireccionales), y los ocho primeros se utilizan siempre para los gráficos del jugador (Willy).

Los gráficos bidireccionales utilizan los Sprites 1 a 4 para los frames que miran hacia la derecha y los Sprites 7 a 8 para los frames que miran hacia la izquierda, donde los Sprites 1 y 5 son los frames más a la izquierda, y los Sprites 4 y 8 son los frames más a la derecha. Existe una excepción en los gráficos utilizados en las salas "Skylab", donde la primera imagen se utiliza para el movimiento y las siete restantes para un efecto de destrucción al final.

Véase [Dr. Andrew Broad Manic Miner Room-Format](https://www.icemark.com/dataformats/manic/mmformat.htm) para más información.

Así, en el juego original, hay 24 sprites estáticos y 168 animados.

Las imágenes de los sprites deben usar transparencia en el fondo o de lo contrario se producirán artefactos extraños.

##### Bloques

Dependiendo de la escala, las imágenes de los bloques pueden tener un tamaño de 8x8 píxeles o 12x12 píxeles. Se almacenan en grupos de 9, y hay un grupo por cada nivel, por lo que el juego original tiene 180 imágenes.

En cada grupo, cada una de las imágenes se utiliza para un tipo de bloque o elemento diferente, con el siguiente orden:

1. Fondo
2. Suelo
3. Suelo que se rompe
4. Muro
5. Transportador
6. Mortal 1
7. Mortal 2
8. Repuesto
9. Objeto llave

El tipo de repuesto (8) se utiliza para interruptores, piso extra u otros.

Ver [Dr. Andrew Broad Manic Miner Room-Format](https://www.icemark.com/dataformats/manic/mmformat.htm) para más información.

#### Datos de Sonido

La fuente para el sonido final opcional debe ser un archivo de sonido WAV (Microsoft) codificado con ADPCM. Véase [la documentación oficial de Playdate](https://sdk.play.date/1.13.7/Inside%20Playdate.html#M-sound) para más información.

---

## License

BSD 2-Clause License

Copyright (c) 2022-2023, kounch
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

- Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

- Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Manic Miner Copyright 1983 Matthew Smith.

Playdate is a registered trademark of [Panic](https://panic.com/).
