/*
 * app_startup.S — TP4 (Bloque 4): arranque del FW cuando corre detrás del BL.
 * Reemplaza a ../startup.S (que no se toca).
 *
 * Hito 4: header + vector table del FW y Reset_Handler ("De 0 a main").
 */
#include "fw_image.h"

#define REG_FW_STATUS_ADDR  0x00040000      /* project_config.def: REG_FW_STATUS */
#define FW_STATUS_PASS      0xFF

/* ------------------------------------------------------------------------ */
/*  1) Header + vector table del FW (app.ld lo pone al inicio de APP_ROM)    */
/* ------------------------------------------------------------------------ */
    .section .fw_header, "a"
    .balign 4
    .globl  __fw_header
    .type   __fw_header, @object
__fw_header:
    /* Los 6 campos de fw_image.h, en orden (.word = 4 bytes en RISC-V).
     * load_addr, image_size, initial_sp y reset_handler son simbolos: los
     * resuelve el linker (app.ld). image_crc no se puede conocer al linkear
     * (depende de la imagen ya linkeada): queda en FW_IMAGE_CRC_UNSET y lo
     * escribe tools/mkimage.py despues. */
    .word   FW_IMAGE_MAGIC          /* 0x00 magic          "TP4F"                    */
    .word   __fw_start              /* 0x04 load_addr      app.ld: ORIGIN(APP_ROM)   */
    .word   __fw_size               /* 0x08 image_size     app.ld: __fw_end - start  */
    .word   FW_IMAGE_CRC_UNSET      /* 0x0C image_crc      mkimage.py (post-link)    */
    .word   _stack_top              /* 0x10 initial_sp     app.ld: tope de la RAM    */
    .word   Reset_Handler           /* 0x14 reset_handler                            */
    .size   __fw_header, . - __fw_header

/* ------------------------------------------------------------------------ */
/*  2) Reset_Handler: "De 0 a main" (diapos 5 y 6)                           */
/* ------------------------------------------------------------------------ */
    .section .text.Reset_Handler, "ax"
    .balign 4                       /* contrato: reset_handler alineado a 4 */
    .globl  Reset_Handler
    .type   Reset_Handler, @function
Reset_Handler:
    /* 1) sp = _stack_top. El BL ya lo dejo cargado desde initial_sp, pero el FW
     *    no debe depender de eso: asi tambien arranca si se entra por otro
     *    camino (un debugger que pone el PC en Reset_Handler, otro BL, un
     *    reinicio "en caliente") y no confia en el estado que dejo otro binario. */
    la      sp, _stack_top

    /* 2) Copiar .data, palabra por palabra, desde los valores iniciales que
     *    viajan en la imagen (_sidata, LMA en APP_ROM) a la RAM (_sdata.._edata,
     *    VMA). app.ld deja los tres simbolos alineados a 4. */
    la      t0, _sidata
    la      t1, _sdata
    la      t2, _edata
    bgeu    t1, t2, 2f              /* .data vacia: nada que copiar */
1:  lw      t3, 0(t0)
    sw      t3, 0(t1)
    addi    t0, t0, 4
    addi    t1, t1, 4
    bltu    t1, t2, 1b
2:
    /* 3) Poner .bss en cero (_sbss.._ebss, alineados a 4). */
    la      t0, _sbss
    la      t1, _ebss
    bgeu    t0, t1, 4f              /* .bss vacia */
3:  sw      zero, 0(t0)
    addi    t0, t0, 4
    bltu    t0, t1, 3b
4:
    /* 4) main() */
    call    main

    /* 5) main volvio. Si dejó REG_FW_STATUS = 0xFF (PASS), el testbench termina
     *    la simulacion solo: quedarse en un loop. Si no, nadie la va a terminar
     *    (el testbench espera 0xFF o un trap): ebreak -> trap y la simulacion corta. */
    li      t0, REG_FW_STATUS_ADDR
    lw      t1, 0(t0)
    li      t2, FW_STATUS_PASS
    bne     t1, t2, 6f
5:  j       5b                      /* PASS: esperar a que el testbench termine */
6:  ebreak                          /* main volvio sin PASS: trap */
7:  j       7b
    .size   Reset_Handler, . - Reset_Handler
