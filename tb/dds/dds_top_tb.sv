`timescale 1ns/1ps

import dso_pkg::*;

module dds_top_tb;

    logic clk;
    logic rst_n;
    logic [PHASE_W-1:0] phase_increment;
    logic [GAIN_W-1:0] gain;
    logic signed [DDS_SAMPLE_W-1:0] dds_out;

    int pass_count;
    int fail_count;

    logic signed [DDS_SAMPLE_W-1:0] ref_lut [0:LUT_DEPTH-1];

    localparam logic [PHASE_W-1:0] PHASE_INC_STEP = 1 << (PHASE_W - LUT_ADDR_W);
    localparam logic [GAIN_W-1:0] GAIN_MAX = '1;

    initial $readmemh("./rtl/dds/lut/sine_lut.hex", ref_lut);

    dds_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .phase_increment(phase_increment),
        .gain(gain),
        .dds_out(dds_out)
    );

    always #10 clk = ~clk;

    function automatic logic signed [DDS_SAMPLE_W-1:0] expected_dds(input int lut_index, input logic [GAIN_W-1:0] g);
        logic signed [DDS_SAMPLE_W+GAIN_W:0] prod;
        prod = $signed(ref_lut[lut_index]) * $signed({1'b0, g});
        expected_dds = prod >>> GAIN_W;
    endfunction

    task check(input logic signed [DDS_SAMPLE_W-1:0] actual, input logic signed [DDS_SAMPLE_W-1:0] expected, input string label);
        if (actual === expected) begin
            pass_count++;
            $display("PASS | %-30s | actual=%0d expected=%0d", label, actual, expected);
        end
        else begin
            fail_count++;
            $display("FAIL | %-30s | actual=%0d expected=%0d (expected %0d)", label, actual, expected, expected);
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
        phase_increment = '0;
        gain = '0;
        pass_count = 0;
        fail_count = 0;

        //Reset: dds_out zero during reset
        step(3);
        check(dds_out, '0, "dds_out zero during reset");

        //Release reset and confirm dds_out zero immediately after, before any sample pulses
        @(negedge clk);
        rst_n = 1;
        step(1);
        check(dds_out, '0, "dds_out zero immediately after reset release");

        //Zero gain forces dds_out to zero even after several pulses with a nonzero phase increment
        @(negedge clk);
        rst_n = 0;
        step(1);
        @(negedge clk);
        rst_n = 1;
        phase_increment = PHASE_INC_STEP;
        gain = '0;
        step(1);
        step(249);
        step(250);
        step(250);
        step(250);
        step(250);
        check(dds_out, '0, "zero gain forces dds_out to zero");

        //dds_out matches the LUT and gain path after pulse 3
        @(negedge clk);
        rst_n = 0;
        step(1);
        @(negedge clk);
        rst_n = 1;
        phase_increment = PHASE_INC_STEP;
        gain = GAIN_MAX;
        step(1);
        step(249);
        step(250);
        step(250);
        check(dds_out, expected_dds(0, GAIN_MAX), "dds_out matches LUT and gain after pulse 3");

        //dds_out matches the LUT and gain path after pulse 4
        step(250);
        check(dds_out, expected_dds(1, GAIN_MAX), "dds_out matches LUT and gain after pulse 4");

        //dds_out matches the LUT and gain path after pulse 5
        step(250);
        check(dds_out, expected_dds(2, GAIN_MAX), "dds_out matches LUT and gain after pulse 5");

        //Asserting reset mid-operation forces dds_out back to zero immediately
        @(negedge clk);
        rst_n = 0;
        step(1);
        check(dds_out, '0, "dds_out zero when reset reasserted mid-operation");

        //Releasing reset restarts the sequence and reproduces the same value at pulse 3
        @(negedge clk);
        rst_n = 1;
        phase_increment = PHASE_INC_STEP;
        gain = GAIN_MAX;
        step(1);
        step(249);
        step(250);
        step(250);
        check(dds_out, expected_dds(0, GAIN_MAX), "dds_out matches LUT and gain after reset restart");

        $display("SUMMARY | passed=%0d failed=%0d", pass_count, fail_count);
        $finish;
    end

endmodule