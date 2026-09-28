`timescale 1ns/1ps

import dso_pkg::*;

module dds_sample_clk_tb;

    logic clk;
    logic rst_n;
    logic sample_en_clk;

    int pass_count;
    int fail_count;

    dds_sample_clk dut (
        .clk(clk),
        .rst_n(rst_n),
        .sample_en_clk(sample_en_clk)
    );

    always #10 clk = ~clk;

    task check(input logic actual, input logic expected, input string label);
        if (actual === expected) begin
            pass_count++;
            $display("PASS | %-30s | actual=%0b expected=%0b", label, actual, expected);
        end
        else begin
            fail_count++;
            $display("FAIL | %-30s | actual=%0b expected=%0b (expected %0b)", label, actual, expected, expected);
        end
    endtask

    task step(input int cycles);
        repeat (cycles) begin
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        pass_count = 0;
        fail_count = 0;

        //Reset: sample_en_clk is low while rst_n is asserted
        step(3);
        check(sample_en_clk, 1'b0, "sample_en_clk low during reset");

        //Release reset and confirm sample_en_clk stays low immediately after
        @(negedge clk);
        rst_n = 1;
        step(1);
        check(sample_en_clk, 1'b0, "sample_en_clk low just after reset release");

        //First pulse arrives after 250 clock cycles from reset release
        step(249);
        check(sample_en_clk, 1'b1, "first pulse occurs after 250 cycles");

        //Pulse is a single cycle wide
        step(1);
        check(sample_en_clk, 1'b0, "pulse is single cycle wide");

        //Second pulse arrives exactly 250 cycles after the first
        step(248);
        check(sample_en_clk, 1'b0, "no pulse before 250 cycles elapse");
        step(1);
        check(sample_en_clk, 1'b1, "second pulse occurs 250 cycles after first");

        //Asserting reset mid-count forces sample_en_clk low immediately
        @(negedge clk);
        rst_n = 0;
        step(1);
        check(sample_en_clk, 1'b0, "sample_en_clk low when reset reasserted mid-count");

        //Releasing reset restarts the count from zero
        @(negedge clk);
        rst_n = 1;
        step(249);
        check(sample_en_clk, 1'b0, "no pulse before 250 cycles after reset restart");
        step(1);
        check(sample_en_clk, 1'b1, "pulse occurs 250 cycles after reset restart");

        $display("SUMMARY | passed=%0d failed=%0d", pass_count, fail_count);
        $finish;
    end

endmodule