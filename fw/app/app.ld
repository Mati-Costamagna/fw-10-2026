/*
 * app.ld -- TP4 (Bloque 4): linker script del FW del TP anterior cuando corre
 * detras del bootloader. Parte de ../linker.ld y de la diapo 4. Hito 3.
 *
 *   APP_ROM 0x0000_1000  | header + vector table | .text | .rodata | valores iniciales de .data |
 *   RAM     0x0002_0000  | .data (VMA) | .bss | ...libre... | stack (crece hacia abajo) | 0x0004_0000
 */
ENTRY(Reset_Handler)

INCLUDE memory_map.ld

/* Lugar minimo que tiene que quedar libre para el stack entre _ebss y _stack_top */
__min_stack_size = 0x1000;

SECTIONS
{
  .text : {
    /* El header + vector table del FW PRIMERO, en ORIGIN(APP_ROM): es donde el BL
     * lo busca (__fw_slot_start). KEEP porque nadie lo referencia desde el codigo
     * y --gc-sections lo descartaria. */
    __fw_start = .;
    KEEP(*(.fw_header))
    /* Reset_Handler justo despues del header (0x1018), sin depender del orden
     * en que se pasan los archivos al linker. */
    *(.text.Reset_Handler)
    *(.text .text.*)
    *(.rodata .rodata.*)
    /* RISC-V: GCC pone las constantes chicas en .srodata (small read-only data) */
    *(.srodata .srodata.*)
    . = ALIGN(4);
  } > APP_ROM

  /* .data: corre en RAM (VMA) pero sus valores iniciales viajan en la imagen,
   * a continuacion de .text (LMA, AT> APP_ROM). Reset_Handler los copia. */
  .data : {
    . = ALIGN(4);
    _sdata = .;
    *(.data .data.*)
    /* globales chicas (<= 8 bytes, -msmall-data-limit) */
    *(.sdata .sdata.*)
    . = ALIGN(4);
    _edata = .;
  } > RAM AT> APP_ROM
  _sidata = LOADADDR(.data);

  /* .bss: solo ocupa RAM, no la imagen (NOLOAD). Reset_Handler la pone en 0. */
  .bss (NOLOAD) : {
    . = ALIGN(4);
    _sbss = .;
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(4);
    _ebss = .;
  } > RAM

  /DISCARD/ : { *(.eh_frame .eh_frame_hdr) }
}

/* Simbolos que usan el header (fw_image.h) y el arranque */
__fw_end   = _sidata + (_edata - _sdata);    /* fin de la imagen: termina la copia de .data */
__fw_size  = __fw_end - __fw_start;          /* image_size: lo que el BL valida y firma mkimage.py */
_stack_top = ORIGIN(RAM) + LENGTH(RAM);      /* initial_sp: tope de la RAM */

ASSERT(__fw_start == ORIGIN(APP_ROM),
       "app.ld: el header del FW (.fw_header) no quedo al inicio de APP_ROM")
ASSERT(_stack_top % 16 == 0,
       "app.ld: _stack_top tiene que estar alineado a 16 (ABI RISC-V)")
ASSERT(_ebss + __min_stack_size <= _stack_top,
       "app.ld: .data + .bss no dejan lugar para el stack en la RAM")
