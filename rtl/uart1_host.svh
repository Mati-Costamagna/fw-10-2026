// Modelo del "host" de UART1 para el testbench de la plataforma (TP5).
// Se incluye DENTRO del modulo testbench (usa clk, u_top y las variables de aca). Solo actua
// cuando se pasa +UART1_SCRIPT=<archivo>; sin ese plusarg el testbench se comporta como siempre.
// `make test_<nombre>` pasa solo fw/tests/<nombre>.txt si existe (make test_main usa main.txt).
//
// Lineas serie (se manejan por jerarquia, igual que fake_uart0_* en testbench.sv):
//   u_top.uart1_rx_line  host -> DUT        u_top.uart1_tx_line  DUT -> host
//   u_top.uart1_cts_n    (no se usa: 0)      u_top.uart1_rts_n    DUT -> host (0 = listo)
//
// Formato del script (un comando por linea, '#' o '//' comentan):
//   baud N          clocks por bit del host (debe coincidir con BAUD_DIV del FW)
//   gap N           clocks de idle extra entre bytes
//   skid N          bytes que el host manda igual despues de ver RTS en alto
//   timeout N       clocks maximos de espera de cada '<' y de cada espera de RTS
// El host SIEMPRE respeta la linea RTS del DUT: antes de cada byte la mira y, si el DUT
// no esta listo (REG_UART1_CTRL.RTS = 0), espera hasta 'timeout' clocks a que la suba.
//   > b0 b1 ...     envia bytes (hex). 'b*N' repite el byte N veces (ej: 00*40)
//   >! b0 b1 ...    envia bytes con el bit de stop en 0 (framing error)
//   < b0 b1 ...     espera exactamente esos bytes (xx = cualquier valor, xx*N = N bytes
//                   cualquiera). 'crc' = el byte debe ser el CRC-8 (poly 0x07, init 0xFF) de los bytes
//                   desde OPCODE (4to byte de la linea) hasta el anterior: la trama tiene
//                   que empezar en el primer byte de la linea.
//   wait N          idle N clocks
//   drain N         espera N clocks y descarta lo recibido
//   expect_no_overrun   falla si la UART1 del DUT marco overrun en algun momento

// ---------------------------------------------------------------- estado
integer host_baud    = 32;
integer host_gap     = 0;
integer host_skid    = 0;
integer host_timeout = 200000;
integer skid_left    = 0;

byte    rxq [$];                 // bytes recibidos del DUT (UART1 TX)
string  toks [$];                // tokens de la linea en curso
integer checks_total = 0;
integer checks_fail  = 0;
bit     script_abort = 0;
bit     script_done  = 0;
bit     overrun_seen = 0;
bit     verbose      = 0;
integer tx_frame_errors = 0;

always @(posedge clk) begin
    if (u_top.u_uart1.overrun) overrun_seen <= 1'b1;
end

// ---------------------------------------------------------------- helpers
function automatic int hexval(byte c);
    if (c >= "0" && c <= "9") return c - "0";
    if (c >= "a" && c <= "f") return c - "a" + 10;
    if (c >= "A" && c <= "F") return c - "A" + 10;
    return -1;
endfunction

function automatic void tokenize(string s);
    string cur;
    byte   c;
    toks.delete();
    cur = "";
    for (int i = 0; i < s.len(); i++) begin
        c = s[i];
        if (c == "#") break;
        if (c == "/" && (i + 1) < s.len() && s[i+1] == "/") break;
        if (c == " " || c == "\t" || c == "\n" || c == "\r") begin
            if (cur.len() > 0) begin toks.push_back(cur); cur = ""; end
        end else begin
            cur = $sformatf("%s%c", cur, c);
        end
    end
    if (cur.len() > 0) toks.push_back(cur);
endfunction

// token -> byte; wild=1 si es 'xx'
function automatic bit parse_byte(string t, output byte v, output bit wild);
    int h, l;
    v = 0; wild = 0;
    if (t == "xx" || t == "XX") begin wild = 1; return 1; end
    if (t.len() == 1) begin
        h = hexval(t[0]);
        if (h < 0) return 0;
        v = h[7:0];
        return 1;
    end
    if (t.len() == 2) begin
        h = hexval(t[0]); l = hexval(t[1]);
        if (h < 0 || l < 0) return 0;
        v = {h[3:0], l[3:0]};
        return 1;
    end
    return 0;
endfunction

// token con repeticion opcional: 'b', 'b*N', 'xx*N', 'crc'
function automatic bit parse_tok(string t, output byte v, output bit wild, output bit is_crc, output int rep);
    string base;
    int    star;
    star = -1;
    rep = 1; is_crc = 0;
    for (int i = 0; i < t.len(); i++) if (t[i] == "*") star = i;
    if (star >= 0) begin
        rep  = t.substr(star + 1, t.len() - 1).atoi();
        base = t.substr(0, star - 1);
        if (rep <= 0) return 0;
    end else begin
        base = t;
    end
    if (base == "crc" || base == "CRC") begin
        v = 0; wild = 0; is_crc = 1;
        return 1;
    end
    return parse_byte(base, v, wild);
endfunction

// CRC-8 poly 0x07 init 0xFF (el de str_crc8() y el de la consigna) sobre rxq[from .. to_excl-1]
function automatic byte crc8_rxq(int from, int to_excl);
    byte crc;
    crc = 8'hFF;
    for (int i = from; i < to_excl; i++) begin
        crc = crc ^ rxq[i];
        for (int b = 0; b < 8; b++)
            crc = crc[7] ? ((crc << 1) ^ 8'h07) : (crc << 1);
    end
    return crc;
endfunction

task automatic script_fail(string msg);
    checks_total++;
    checks_fail++;
    $display("\033[31m[FAIL]\033[0m %s", msg);
    if (checks_fail == 10) begin
        $display("\033[31mdemasiadas fallas: se corta el script\033[0m");
        script_abort = 1;
    end
endtask

task automatic script_pass(string msg);
    checks_total++;
    $display("\033[32m[ OK ]\033[0m %s", msg);
endtask

// ---------------------------------------------------------------- host -> DUT
task automatic host_send_byte(input byte b, input bit bad_stop);
    integer waited;
    // control de flujo: el host mira RTS al empezar cada byte
    if (!u_top.uart1_rts_n) begin
        skid_left = host_skid;
    end else if (skid_left > 0) begin
        skid_left = skid_left - 1;
    end else begin
        waited = 0;
        while (u_top.uart1_rts_n && waited < host_timeout) begin
            @(posedge clk);
            waited++;
        end
        if (u_top.uart1_rts_n) begin
            script_fail("el DUT nunca levanto RTS (esta listo para recibir?)");
            script_abort = 1;
            return;
        end
        skid_left = host_skid;
    end
    // las asignaciones son no bloqueantes para no competir con el muestreo del DUT
    u_top.uart1_rx_line <= 1'b0;                      // start
    repeat (host_baud) @(posedge clk);
    for (int i = 0; i < 8; i++) begin
        u_top.uart1_rx_line <= b[i];                  // LSB primero
        repeat (host_baud) @(posedge clk);
    end
    u_top.uart1_rx_line <= bad_stop ? 1'b0 : 1'b1;    // stop
    repeat (host_baud) @(posedge clk);
    u_top.uart1_rx_line <= 1'b1;
    if (bad_stop) repeat (host_baud) @(posedge clk);  // idle para que el DUT resincronice
    repeat (host_gap) @(posedge clk);
    if (verbose) $display("UART1 -> 0x%02x%s", b, bad_stop ? " (bad stop)" : "");
endtask

// ---------------------------------------------------------------- DUT -> host
task automatic host_monitor();
    byte data;
    forever begin
        @(posedge clk);
        if (u_top.uart1_tx_line == 1'b0) begin
            repeat (host_baud / 2) @(posedge clk);
            if (u_top.uart1_tx_line == 1'b0) begin
                for (int i = 0; i < 8; i++) begin
                    repeat (host_baud) @(posedge clk);
                    data[i] = u_top.uart1_tx_line;
                end
                repeat (host_baud) @(posedge clk);
                if (u_top.uart1_tx_line !== 1'b1) begin
                    tx_frame_errors++;
                    $display("\033[31mUART1: framing error en la TX del DUT\033[0m");
                end
                rxq.push_back(data);
                if (verbose) $display("UART1 <- 0x%02x", data);
            end
        end
    end
endtask

// ---------------------------------------------------------------- script
task automatic expect_bytes();
    byte exp_b [$];
    bit  exp_w [$];
    bit  exp_c [$];
    byte v;
    bit  w, c;
    int  rep;
    integer waited, n;
    bit  ok;
    string exp_s, got_s;

    // las colas locales pueden conservar el contenido de la llamada anterior
    exp_b.delete(); exp_w.delete(); exp_c.delete();

    for (int k = 1; k < toks.size(); k++) begin
        if (!parse_tok(toks[k], v, w, c, rep)) begin
            script_fail($sformatf("token invalido '%s' en '<'", toks[k]));
            script_abort = 1;
            return;
        end
        for (int r = 0; r < rep; r++) begin
            exp_b.push_back(v);
            exp_w.push_back(w);
            exp_c.push_back(c);
        end
    end
    n = exp_b.size();
    waited = 0;
    while (rxq.size() < n && waited < host_timeout) begin
        @(posedge clk);
        waited++;
    end

    exp_s = ""; got_s = "";
    for (int k = 0; k < n && k < 24; k++)
        exp_s = $sformatf("%s%s ", exp_s, exp_c[k] ? "crc" : exp_w[k] ? "xx" : $sformatf("%02x", exp_b[k]));
    if (n > 24) exp_s = {exp_s, "..."};
    for (int k = 0; k < rxq.size() && k < n && k < 24; k++)
        got_s = $sformatf("%s%02x ", got_s, rxq[k]);
    if (rxq.size() > 24 && n > 24) got_s = {got_s, "..."};

    ok = (rxq.size() >= n);
    if (ok) begin
        for (int k = 0; k < n; k++) begin
            if (exp_c[k]) begin
                // la trama empieza en el primer byte de esta linea: CRC sobre OPCODE..ultimo dato
                if (k < 5 || rxq[k] !== crc8_rxq(4, k)) ok = 0;
            end else if (!exp_w[k] && rxq[k] !== exp_b[k]) begin
                ok = 0;
            end
        end
    end

    if (ok) begin
        script_pass($sformatf("recibido: %s", n > 16 ? $sformatf("%0d bytes", n) : exp_s));
        for (int k = 0; k < n; k++) void'(rxq.pop_front());
    end else begin
        if (rxq.size() < n)
            script_fail($sformatf("timeout esperando %0d bytes (llegaron %0d). esperado: %s recibido: %s",
                                  n, rxq.size(), exp_s, got_s));
        else
            script_fail($sformatf("respuesta distinta. esperado: %s recibido: %s", exp_s, got_s));
        rxq.delete();
    end
endtask

task automatic run_script(string path);
    integer fd;
    string  line, cmd;
    byte    v;
    bit     w, c;
    int     rep;

    fd = $fopen(path, "r");
    if (fd == 0) begin
        script_fail($sformatf("no se puede abrir el script '%s'", path));
        return;
    end
    while (!$feof(fd) && !script_abort) begin
        line = "";
        void'($fgets(line, fd));
        tokenize(line);
        if (toks.size() == 0) continue;
        cmd = toks[0];

        if (cmd == ">" || cmd == ">!") begin
            for (int k = 1; k < toks.size() && !script_abort; k++) begin
                if (!parse_tok(toks[k], v, w, c, rep) || w || c) begin
                    script_fail($sformatf("token invalido '%s' en '%s'", toks[k], cmd));
                    script_abort = 1;
                end else begin
                    for (int r = 0; r < rep && !script_abort; r++)
                        host_send_byte(v, cmd == ">!");
                end
            end
        end
        else if (cmd == "<")                expect_bytes();
        else if (cmd == "baud")             host_baud    = toks[1].atoi();
        else if (cmd == "gap")              host_gap     = toks[1].atoi();
        else if (cmd == "skid")             host_skid    = toks[1].atoi();
        else if (cmd == "timeout")          host_timeout = toks[1].atoi();
        else if (cmd == "wait")             repeat (toks[1].atoi()) @(posedge clk);
        else if (cmd == "drain") begin
            repeat (toks[1].atoi()) @(posedge clk);
            rxq.delete();
        end
        else if (cmd == "expect_no_overrun") begin
            if (overrun_seen) script_fail("la UART1 del DUT perdio bytes (overrun)");
            else              script_pass("sin overrun");
        end
        else begin
            script_fail($sformatf("comando desconocido '%s'", cmd));
            script_abort = 1;
        end
    end
    $fclose(fd);

    // al terminar no deben quedar bytes sin esperar
    repeat (host_baud * 12) @(posedge clk);
    if (rxq.size() != 0 && !script_abort)
        script_fail($sformatf("%0d bytes recibidos que el script no esperaba", rxq.size()));
    if (tx_frame_errors != 0)
        script_fail($sformatf("%0d framing errors en la TX del DUT", tx_frame_errors));
endtask
