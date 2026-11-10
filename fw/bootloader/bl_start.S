/*
 * bl_start.S — TP4 (Bloque 4): vector table + arranque mínimo del BOOTLOADER
 *
 * COMPLETAR los TODO (hitos 2 y 5 de la consigna).
 *
 * Datos de la plataforma (platform/rtl/top.v, parámetros de picorv32):
 *   - PROGADDR_RESET = 0x0000_0000: al salir de reset el core EJECUTA lo que hay ahí.
 *   - PROGADDR_IRQ   = 0x0000_0010 (ENABLE_IRQ = 0: no hay IRQs).
 *   - STACKADDR      = 0xFFFF_FFFF: el core NO inicializa sp.
 */

#define REG_FW_STATUS_ADDR  0x00040000      /* project_config.def: REG_FW_STATUS */
#define FW_STATUS_FAIL      0xBAD           /* convención de los tests de platform/fw */

/* ------------------------------------------------------------------------ */
/*  Vector table del BL (bl.ld la tiene que ubicar en 0x0000_0000)          */
/* ------------------------------------------------------------------------ */
    .section .vectors, "ax"
    .option push
    .option norvc                   /* instrucciones de 4 bytes: los offsets importan */
    .globl  _bl_vectors
    .type   _bl_vectors, @function
_bl_vectors:
    /* picorv32 no lee una tabla de direcciones: al salir de reset pone el PC en
     * PROGADDR_RESET y EJECUTA lo que encuentra ahi (lo mismo con una IRQ en
     * PROGADDR_IRQ). Por eso cada "vector" es una instruccion de salto de 4 bytes
     * (con norvc, `j` es siempre un jal de 32 bits y los offsets quedan fijos). */
    j       bl_reset_handler        /* 0x00  PROGADDR_RESET                       */
    /* 0x04..0x0C no son vectores: si el PC cae aca es un error (por ejemplo, un
     * salto a una direccion invalida), asi que tambien se va a FAIL + trap en
     * vez de "caer" en la siguiente instruccion. */
    j       bl_unexpected           /* 0x04                                       */
    j       bl_unexpected           /* 0x08                                       */
    j       bl_unexpected           /* 0x0C                                       */
    j       bl_unexpected           /* 0x10  PROGADDR_IRQ (ENABLE_IRQ = 0)         */

    .size   _bl_vectors, . - _bl_vectors
    .option pop

/* ------------------------------------------------------------------------ */
/*  Reset: init minimo del BL                                               */
/* ------------------------------------------------------------------------ */
    .section .text.bl_reset_handler, "ax"
    .globl  bl_reset_handler
    .type   bl_reset_handler, @function
bl_reset_handler:
    /* 1) sp = _bl_stack_top (bl.ld). En picorv32 STACKADDR = 0xFFFF_FFFF: el
     *    core NO inicializa sp al salir de reset, asi que lo tiene que
     *    cargar el software antes de llamar a cualquier funcion en C. */
    la      sp, _bl_stack_top

    /* 2) .data/.bss del BL: no hay nada que copiar ni poner en cero porque el
     *    BL no usa variables globales; bl.ld hace FALLAR el link si aparece
     *    alguna (.data/.sdata/.bss/.sbss/COMMON con tamanio distinto de 0). */

    /* 3) bl_main() no vuelve: salta al FW o termina en bl_halt(). */
    call    bl_main

    j       bl_unexpected           /* si bl_main volviera: FAIL */
    .size   bl_reset_handler, . - bl_reset_handler

/* ------------------------------------------------------------------------ */
/*  void bl_jump(uint32_t sp, uint32_t entry)  __attribute__((noreturn))    */
/* ------------------------------------------------------------------------ */
    .section .text.bl_jump, "ax"
    .globl  bl_jump
    .type   bl_jump, @function
bl_jump:
    /* ABI ILP32: a0 = sp, a1 = entry. Salto SIN link (jr): el FW no vuelve,
     * asi que ra queda en 0 (si main retornara, caeria en 0x0 = reset del BL). */
    mv      t0, a1                  /* guardar entry antes de pisar nada */
    mv      sp, a0                  /* sp que pide el FW */
    li      ra, 0
    jr      t0

    .size   bl_jump, . - bl_jump

/* ------------------------------------------------------------------------ */
/*  bl_unexpected: vector inesperado -> FAIL + trap   (YA ESTÁ HECHO)       */
/*  void bl_halt(void): corta la simulación           (YA ESTÁ HECHO)       */
/* ------------------------------------------------------------------------ */
    .section .text.bl_halt, "ax"
    .globl  bl_unexpected
    .type   bl_unexpected, @function
bl_unexpected:
    li      t0, REG_FW_STATUS_ADDR
    li      t1, FW_STATUS_FAIL
    sw      t1, 0(t0)
    /* sigue en bl_halt */
    .globl  bl_halt
    .type   bl_halt, @function
bl_halt:
    ebreak                          /* Pregunta: ¿por qué hace falta el ebreak si ya */
                                    /* dejamos 0xBAD en REG_FW_STATUS?               */
1:  j       1b
    .size   bl_halt, . - bl_halt
    .size   bl_unexpected, . - bl_unexpected
