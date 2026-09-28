`timescale 1ns/1ps

import dso_pkg::*;

module dac_if_tb;

    logic clk;
    logic rst_n;
    logic sample_clk_en;
    logic [11:0] dac_data;

    logic dac_cs_n;
    logic dac_sck;
    logic dac_mosi;
    logic dac_ldac_n;
    logic busy;

    int pass_count;
    int fail_count;

    dac_if dut (
        .clk(clk),
        .rst_n(rst_n),
        .sample_clk_en(sample_clk_en),
        .dac_data(dac_data),
        .dac_cs_n(dac_cs_n),
        .dac_sck(dac_sck),
        .dac_mosi(dac_mosi),
        .dac_ldac_n(dac_ldac_n),
        .busy(busy)
    );

    always #5 clk = ~clk;

    task automatic check(
        input logic actual,
        input logic expected,
        input string label
    );
        begin
            if (actual === expected) begin
                $display("PASS | %-30s | actual = %b", label, actual);
                pass_count++;
            end else begin
                $display("FAIL | %-30s | actual = %b (expected %b)", label, actual, expected);
                fail_count++;
            end
        end
    endtask

    task automatic check_command(
        input logic [15:0] expected_command
    );
        int i;
        begin
            for (i = 15; i >= 0; i--) begin
                @(posedge dac_sck);
                check(dac_mosi, expected_command[i], $sformatf("SPI bit %0d", i));
            end
        end
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        sample_clk_en = 0;
        dac_data = 0;
        pass_count = 0;
        fail_count = 0;

        repeat (2) @(posedge clk);

        //Reset outputs are inactive after reset.
        #1;
        check(dac_cs_n, 1'b1, "Reset outputs are inactive");
        check(dac_sck, 1'b0, "Reset outputs are inactive");
        check(dac_mosi, 1'b0, "Reset outputs are inactive");
        check(dac_ldac_n, 1'b1, "Reset outputs are inactive");
        check(busy, 1'b0, "Reset outputs are inactive");

        rst_n = 1;

        //Idle state keeps the DAC interface inactive.
        @(posedge clk);
        #1;
        check(dac_cs_n, 1'b1, "Idle state keeps the DAC interface inactive");
        check(dac_sck, 1'b0, "Idle state keeps the DAC interface inactive");
        check(dac_ldac_n, 1'b1, "Idle state keeps the DAC interface inactive");
        check(busy, 1'b0, "Idle state keeps the DAC interface inactive");

        //Starting a sample begins an SPI transfer.
        dac_data = 12'hA55;
        sample_clk_en = 1;
        @(posedge clk);
        #1;
        sample_clk_en = 0;
        check(dac_cs_n, 1'b0, "Starting a sample begins an SPI transfer");
        check(busy, 1'b1, "Starting a sample begins an SPI transfer");
        check(dac_sck, 1'b0, "Starting a sample begins an SPI transfer");
        check(dac_mosi, 1'b0, "Starting a sample begins an SPI transfer");

        //SPI transfer sends the complete DAC command.
        check_command({1'b0, 1'b1, 1'b1, 1'b1, 12'hA55});

        //SPI transfer releases chip select and clears busy.
        wait (dac_cs_n == 1'b1);
        #1;
        check(dac_cs_n, 1'b1, "SPI transfer releases chip select and clears busy");
        check(busy, 1'b0, "SPI transfer releases chip select and clears busy");
        check(dac_sck, 1'b0, "SPI transfer releases chip select and clears busy");

        //Completed SPI transfer pulses LDAC low.
        check(dac_ldac_n, 1'b0, "Completed SPI transfer pulses LDAC low");

        //LDAC pulse returns high and the interface returns to idle.
        @(posedge clk);
        #1;
        check(dac_ldac_n, 1'b1, "LDAC pulse returns high and the interface returns to idle");
        check(busy, 1'b0, "LDAC pulse returns high and the interface returns to idle");
        check(dac_cs_n, 1'b1, "LDAC pulse returns high and the interface returns to idle");
        check(dac_sck, 1'b0, "LDAC pulse returns high and the interface returns to idle");

        //A second sample starts a new SPI transfer.
        dac_data = 12'h3C9;
        sample_clk_en = 1;
        @(posedge clk);
        #1;
        sample_clk_en = 0;
        check(dac_cs_n, 1'b0, "A second sample starts a new SPI transfer");
        check(busy, 1'b1, "A second sample starts a new SPI transfer");

        //A second sample sends the updated DAC command.
        check_command({1'b0, 1'b1, 1'b1, 1'b1, 12'h3C9});

        //Second SPI transfer completes with LDAC asserted.
        wait (dac_cs_n == 1'b1);
        #1;
        check(dac_ldac_n, 1'b0, "Second SPI transfer completes with LDAC asserted");
        check(busy, 1'b0, "Second SPI transfer completes with LDAC asserted");

        @(posedge clk);
        #1;
        $display("SUMMARY | passed = %0d | failed = %0d", pass_count, fail_count);

        if (fail_count != 0)
            $fatal(1, "Testbench failed");
        else
            $finish;
    end

endmodule