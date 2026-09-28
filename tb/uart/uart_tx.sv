import dso_pkg::*;

module tb_uart_tx;

    localparam int CLKS_PER_BIT = CLK_FREQ / UART_BAUD;
    localparam real CLK_PERIOD_NS = 1_000_000_000.0 / CLK_FREQ;

    logic clk = 0;
    logic rst_n;
    logic tx_start;
    logic [7:0] tx_data;
    logic tx_serial_out;
    logic busy;
    logic tx_done;

    int pass_count = 0;
    int fail_count = 0;

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    uart_tx dut (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_serial_out(tx_serial_out),
        .busy(busy),
        .tx_done(tx_done)
    );

    task automatic check(input logic [31:0] actual, input logic [31:0] expected, input string label);
        if (actual === expected) begin
            pass_count++;
            $display("PASS | %-40s | got %0d", label, actual);
        end else begin
            fail_count++;
            $display("FAIL | %-40s | got %0d (expected %0d)", label, actual, expected);
        end
    endtask

    task automatic pulse_tx_start(input logic [7:0] data);
        @(posedge clk);
        tx_data <= data;
        tx_start <= 1;
        @(posedge clk);
        tx_start <= 0;
    endtask

    task automatic capture_frame(output logic [7:0] data_out, output logic stop_bit_out);
        wait (tx_serial_out == 1'b0);
        repeat (CLKS_PER_BIT / 2) @(posedge clk);
        for (int i = 0; i < 8; i++) begin
            repeat (CLKS_PER_BIT) @(posedge clk);
            data_out[i] = tx_serial_out;
        end
        repeat (CLKS_PER_BIT) @(posedge clk);
        stop_bit_out = tx_serial_out;
    endtask

    initial begin

        rst_n = 0;
        tx_start = 0;
        tx_data = 8'h00;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        //reset defaults: tx_serial_out idles high, busy and tx_done are low
        check(tx_serial_out, 1, "reset defaults: tx_serial_out idles high");
        check(busy, 0, "reset defaults: busy low");
        check(tx_done, 0, "reset defaults: tx_done low");

        //send byte 0x00: captured frame matches data with stop bit high
        fork
            pulse_tx_start(8'h00);
            begin
                logic [7:0] captured;
                logic stop_bit;
                capture_frame(captured, stop_bit);
                check(captured, 8'h00, "send byte 0x00: captured data matches");
                check(stop_bit, 1, "send byte 0x00: stop bit high");
            end
        join
        wait (busy == 1'b0);
        repeat (5) @(posedge clk);

        //send byte 0xFF: captured frame matches data with stop bit high
        fork
            pulse_tx_start(8'hFF);
            begin
                logic [7:0] captured;
                logic stop_bit;
                capture_frame(captured, stop_bit);
                check(captured, 8'hFF, "send byte 0xFF: captured data matches");
                check(stop_bit, 1, "send byte 0xFF: stop bit high");
            end
        join
        wait (busy == 1'b0);
        repeat (5) @(posedge clk);

        //send byte 0xA5: captured frame matches data with stop bit high
        fork
            pulse_tx_start(8'hA5);
            begin
                logic [7:0] captured;
                logic stop_bit;
                capture_frame(captured, stop_bit);
                check(captured, 8'hA5, "send byte 0xA5: captured data matches");
                check(stop_bit, 1, "send byte 0xA5: stop bit high");
            end
        join
        wait (busy == 1'b0);
        repeat (5) @(posedge clk);

        //busy asserted during transmission: busy goes high one cycle after tx_start
        pulse_tx_start(8'h3C);
        @(negedge clk);
        check(busy, 1, "busy asserted during transmission");
        wait (tx_done == 1'b1);
        wait (busy == 1'b0);
        repeat (5) @(posedge clk);

        //tx_done pulses for exactly one cycle after transmission completes
        pulse_tx_start(8'h55);
        wait (tx_done == 1'b1);
        @(posedge clk);
        @(negedge clk);
        check(tx_done, 0, "tx_done pulses for exactly one cycle after transmission completes");
        wait (busy == 1'b0);
        repeat (5) @(posedge clk);

        //back to back transmission: second byte sent immediately after first completes
        fork
            begin
                pulse_tx_start(8'h11);
                wait (tx_done == 1'b1);
                @(posedge clk);
                pulse_tx_start(8'h22);
            end
            begin
                logic [7:0] captured1;
                logic [7:0] captured2;
                logic stop_bit1;
                logic stop_bit2;
                capture_frame(captured1, stop_bit1);
                capture_frame(captured2, stop_bit2);
                check(captured1, 8'h11, "back to back transmission: first byte matches");
                check(captured2, 8'h22, "back to back transmission: second byte matches");
            end
        join
        repeat (5) @(posedge clk);

        $display("%0d passed, %0d failed", pass_count, fail_count);
        $finish;

    end

    initial begin
        #200000;
        $display("timeout - simulation did not finish in time");
        $finish;
    end

endmodule