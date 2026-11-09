/*
 * bl.ld -- TP4 (Bloque 4): linker script del BOOTLOADER
 *
 * El BL vive en BL_ROM (memory_map.ld). Hito 2.
 */
ENTRY(_bl_vectors)

INCLUDE memory_map.ld

SECTIONS
{
  .text : {
    /* La vector table PRIMERA, en ORIGIN(BL_ROM) = PROGADDR_RESET: es lo que el
     * core ejecuta al salir de reset. KEEP porque ningun codigo la referencia
     * (la "usa" el hardware), y --gc-sections la tiraria. */
    KEEP(*(.vectors))
    *(.text .text.*)
    *(.rodata .rodata.* .srodata .srodata.*)
    . = ALIGN(4);
  } > BL_ROM

  /* El BL no usa variables globales: todo vive en el stack o es const (.rodata).
   * Si alguien agrega una, cae en alguna de estas secciones y los ASSERT de abajo
   * hacen fallar el link. No hacen falta en la imagen: vacias, ld no las emite. */
  .data : {
    _bl_sdata = .;
    *(.data .data.* .sdata .sdata.*)
    _bl_edata = .;
  } > RAM

  .bss (NOLOAD) : {
    _bl_sbss = .;
    *(.bss .bss.* .sbss .sbss.* COMMON)
    _bl_ebss = .;
  } > RAM

  /DISCARD/ : { *(.eh_frame .eh_frame_hdr) }
}

ASSERT(_bl_edata == _bl_sdata,
       "bl.ld: el BL no puede usar variables globales inicializadas (.data/.sdata)")
ASSERT(_bl_ebss == _bl_sbss,
       "bl.ld: el BL no puede usar variables globales (.bss/.sbss/COMMON)")

/* Stack del BL: el tope de la RAM (crece hacia abajo, alineado a 16 como pide la
 * ABI). El BL no tiene .data/.bss, asi que tiene toda la RAM para el stack; y como
 * nunca vuelve, ese stack se abandona cuando salta al FW (que carga el suyo). */
_bl_stack_top = ORIGIN(RAM) + LENGTH(RAM);
ASSERT(_bl_stack_top % 16 == 0, "bl.ld: _bl_stack_top tiene que estar alineado a 16")

/* (YA ESTA HECHO) Donde espera el BL encontrar al FW: bl_main.c los usa como extern */
__fw_slot_start = ORIGIN(APP_ROM);
__fw_slot_size  = LENGTH(APP_ROM);

/* La vector table tiene que quedar en PROGADDR_RESET = ORIGIN(BL_ROM) = 0x0 */
ASSERT(_bl_vectors == ORIGIN(BL_ROM),
       "bl.ld: la vector table del BL (.vectors) no quedo en ORIGIN(BL_ROM) = 0x0")
