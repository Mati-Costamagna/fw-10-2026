`include "rtl/config.vh"

module testbench;


    reg clk = 1;
    reg resetn = 0;
    reg [63:0]clock_counts ;
    string  hex_path;      // +FW_HEX=<archivo>   (default fw/fw.hex)
    integer max_cycles;    // +MAX_CYCLES=<n>     (default 0 = sin limite)
    string  result;        // PASS | FAIL | TRAP | TIMEOUT
    string  script_path;   // +UART1_SCRIPT=<archivo>  patron de test que maneja la UART1 (ver uart1_host.svh)
    bit     have_script;
    always #5 clk = ~clk;

    top  u_top (
        .i_clk    (clk    ),
        .i_resetn (resetn )
    );

    `include "rtl/uart1_host.svh"

    initial begin
        u_top.fake_uart0_data_input       = 32'b0;
        u_top.fake_uart0_data_input_valid = 1'b0;
        u_top.fake_uart1_data_input       = 32'b0;
        u_top.fake_uart1_data_input_valid = 1'b0;
    end

    initial begin
        if (!$value$plusargs("FW_HEX=%s", hex_path)) hex_path = "fw/fw.hex";
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 0;
        have_script = $value$plusargs("UART1_SCRIPT=%s", script_path);
        verbose     = $test$plusargs("VERBOSE");
        if (!$test$plusargs("NOWAVE")) begin     // +NOWAVE: sin VCD (mas rapido, p. ej. make test)
            $dumpfile("wave.vcd");
            // $dumpfile("wave.fst");
            $dumpvars;
        end

        repeat (10) @(posedge clk);
        init_memory();
        repeat (10) @(posedge clk);
		uart_sniffer();
		uart_trnasmiter();
		led_monitor();
        if (have_script) fork host_monitor(); join_none

        repeat (10) @(posedge clk);
        resetn <= 1;
        
        count_mem_access_read   = 64'b0   ;
        count_mem_access_write  = 64'b0   ;
        count_ins_access_read   = 64'b0   ;
        count_ins_access_write  = 64'b0   ;
        clock_counts            = 64'b0   ;
        if (have_script) begin
            // test con host: el script manda y espera bytes por UART1; termina cuando el script
            // termina, el core hace trap, el FW escribe 0xBAD o se agota +MAX_CYCLES
            fork
                begin run_script(script_path); script_done = 1; end
                begin
                    while (u_top.trap !== 1'b1 && u_top.u_register_file.REGISTER_FW_STATUS != 32'hBAD)
                        @(posedge clk);
                end
                begin
                    while (max_cycles == 0 || clock_counts < max_cycles) begin
                        @(posedge clk);
                        clock_counts = clock_counts + 64'b1;
                    end
                end
            join_any
            repeat (100) @(posedge clk);
            if (u_top.trap === 1'b1)
                script_fail("el core hizo TRAP (instruccion ilegal o acceso desalineado)");
            else if (u_top.u_register_file.REGISTER_FW_STATUS == 32'hBAD)
                script_fail("el FW termino con REG_FW_STATUS = 0xBAD");
            else if (!script_done)
                script_fail($sformatf("timeout: el script no termino en %0d clocks (FW colgado?)", max_cycles));
            if (checks_fail == 0 && checks_total > 0) begin
                $display("\033[32mCHECK PASS (%0d/%0d)\033[0m", checks_total, checks_total);
                result = "PASS";
            end else begin
                $display("\033[31mCHECK FAIL (%0d fallas de %0d)\033[0m", checks_fail, checks_total);
                result = u_top.trap === 1'b1 ? "TRAP" : !script_done ? "TIMEOUT" : "FAIL";
            end
        end else begin
            // fin: el FW escribe 0xFF (OK) o 0xBAD (fallo), el core hace trap, o se agota +MAX_CYCLES
            while(u_top.u_register_file.REGISTER_FW_STATUS != 32'hFF &&
                  u_top.u_register_file.REGISTER_FW_STATUS != 32'hBAD &&
                  u_top.trap !== 1'b1 &&
                  (max_cycles == 0 || clock_counts < max_cycles)) begin
                @(posedge clk);
                clock_counts = clock_counts + 64'b1;
            end
            repeat (100) @(posedge clk);
            if      (u_top.u_register_file.REGISTER_FW_STATUS == 32'hFF)  result = "PASS";
            else if (u_top.u_register_file.REGISTER_FW_STATUS == 32'hBAD) result = "FAIL";
            else if (u_top.trap === 1'b1)                                  result = "TRAP";
            else                                                           result = "TIMEOUT";
        end
        // chequeo de protocolo UART0: cada START pide `size` bytes y el UART tiene que transmitir
        // exactamente esos (si el arranque retriggerea, salen mensajes duplicados)
        if (uart0_tx_bytes != uart0_req_bytes) begin
            $display("ERROR UART0 TX: el FW pidio %0d bytes y el UART transmitio %0d (arranque duplicado?)",
                     uart0_req_bytes, uart0_tx_bytes);
            if (result == "PASS") result = "FAIL";
        end
        if (u_top.trap === 1'b1)begin
            repeat(30) @(posedge clk);
            $display("------ TRAP! ------- clock_counts = %d",clock_counts);
        end else begin
            $display("ending simulation, u_top.u_register_file.REGISTER_FW_STATUS = %x",u_top.u_register_file.REGISTER_FW_STATUS);
            $display("total clocks: %d", clock_counts);
        end
        $display("--- mem report ---");
        $display("-- total mem access = %d",count_mem_access_write+count_mem_access_read);
        $display(" READ = %d, WRITE = %d",count_mem_access_read,count_mem_access_write);
        $display("-- total instruction access = %d",count_ins_access_write+count_ins_access_read);
        $display(" READ = %d, WRITE = %d",count_ins_access_read,count_ins_access_write);
        $display("RESULT: %s", result);

        $finish;
    end


    // bytes pedidos por el FW (flancos de START_TRANSMIT x SIZE) vs bytes que transmite UART0
    integer uart0_req_bytes = 0;
    integer uart0_tx_bytes  = 0;
    reg     uart0_start_q   = 1'b0;
    always @(posedge clk) begin
        uart0_start_q <= u_top.uart0_start_transmit[0];
        if (u_top.uart0_start_transmit[0] && !uart0_start_q)
            uart0_req_bytes <= uart0_req_bytes + u_top.uart0_size_to_transmit;
        if (u_top.u_uart0.o_valid_output)
            uart0_tx_bytes <= uart0_tx_bytes + 1;
    end

`ifdef DEBUG_PRINTS
    always @(posedge clk) begin
        if (u_top.mem_valid && u_top.mem_ready) begin
            if (u_top.mem_instr) begin
                if (u_top.mem_wstrb)begin
                    $display("INSTRUCTION write  0x%08x: 0x%08x (wstrb=%b)", u_top.mem_addr, u_top.mem_wdata, u_top.mem_wstrb);
                end else begin
                    $display("INSTRUCTION read   0x%08x: 0x%08x", u_top.mem_addr, u_top.mem_rdata);
                end
            end else begin
                if (u_top.mem_wstrb)begin
                    $display("MEM write  0x%08x: 0x%08x (wstrb=%b)", u_top.mem_addr, u_top.mem_wdata, u_top.mem_wstrb);
                end else begin
                    $display("MEM read   0x%08x: 0x%08x", u_top.mem_addr, u_top.mem_rdata);
                end
            end 
        end
    end
`endif

    reg [63:0] count_mem_access_read;
    reg [63:0] count_mem_access_write;
    reg [63:0] count_ins_access_read;
    reg [63:0] count_ins_access_write;
    always @(posedge clk) begin
        if (u_top.mem_valid && u_top.mem_ready) begin
            if (u_top.mem_instr) begin
                if (u_top.mem_wstrb)begin
                    count_ins_access_write <= count_ins_access_write + 64'b1;
                end else begin
                    count_ins_access_read <= count_ins_access_read + 64'b1;
                end
            end else begin
                if (u_top.mem_wstrb)begin
                    count_mem_access_write <= count_mem_access_write + 64'b1;
                end else begin
                    count_mem_access_read <= count_mem_access_read + 64'b1;
                end
            end 
        end
    end

    ///////////////// load mem /////////////////
    function init_memory();
    	integer fd;
    	string line;
    	logic [31:0] data;
    	int addr;
        fd = $fopen(hex_path, "r");
        if (fd == 0) begin $fatal(1, "Cannot open %s", hex_path); end
        addr = 0;
        while (!$feof(fd)) begin
            void'($fgets(line, fd));
            if (line.len() == 0) continue;
            $sscanf(line, "%x", data);
            $display("loading: %x -> %x", addr, data);
            u_top.u_mem_mux.memory_i[addr] <= data;
            addr += 1; // byte address
        end
    endfunction
    ////////////////////////////////////////////

	/////////////// print UART buffer //////////
	task uart_sniffer();
		reg [8*256-1:0] uart_buffer ;
		integer size_msg, cnt;
		fork
			while(1)begin
                uart_buffer = 256*8'b0;
                @(posedge u_top.u_uart0.i_start_transmit);   // por flanco, igual que uart.v
                size_msg = u_top.u_uart0.i_size_to_transmit;
                cnt = 0;
                while(cnt < size_msg)begin
                    @(posedge clk);
                    if(u_top.u_uart0.o_valid_output)begin
                        uart_buffer[8*((255-cnt)+1)-1 -: 8] = u_top.u_uart0.o_output_data[7:0];
                        cnt = cnt + 1;
                    end
                end
				$write("\033[36mUART: ");
                for (int i = 0; i < size_msg; i++) begin  $write("%c", uart_buffer[8*((255-i)+1)-1 -: 8]); end
                $write("\033[0m\n");
			end
		join_none
	endtask
    ////////////////////////////////////////////

    byte data_array[] = '{8'd72,8'd79,8'd76,8'd65,8'd33};
	/////////////// uart input transmiter //////////
	task uart_trnasmiter();
		fork
			while(1)begin
                wait (u_top.u_register_file.REGISTER_AUX_0 == 32'h5ED5ED);
                @(posedge clk);
                for(int i=0; i< data_array.size() ; i++)begin
                    force u_top.fake_uart0_data_input_valid = 1'b1;
                    force u_top.fake_uart0_data_input = data_array[i];
                    @(posedge clk);
                end
                force u_top.fake_uart0_data_input_valid = 1'b0;

			end
		join_none
	endtask
    ////////////////////////////////////////////

	/////////////// monitor LED register ////////
	task led_monitor();
		fork
			while(1)begin
				@(u_top.u_register_file.REGISTER_LED);
				$display("\033[32mLED: 0b%08b\033[0m", u_top.u_register_file.REGISTER_LED[7:0]);
			end
		join_none
	endtask
    ////////////////////////////////////////////

    // task uart0_send(input [31:0] data);
    //     begin
    //         u_top.fake_uart0_data_input       = data;
    //         u_top.fake_uart0_data_input_valid = 1'b1;
    //         @(posedge clk);
    //         u_top.fake_uart0_data_input_valid = 1'b0;
    //     end
    // endtask


    // task uart1_send(input [31:0] data);
    //     begin
    //         u_top.fake_uart1_data_input       = data;
    //         u_top.fake_uart1_data_input_valid = 1'b1;
    //         @(posedge clk);
    //         u_top.fake_uart1_data_input_valid = 1'b0;
    //     end
    // endtask

endmodule