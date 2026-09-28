`timescale 1ns/1ps

import dso_pkg::*;

module dds_gain_tb;

    logic clk;
    logic rst_n;
    logic signed [DDS_SAMPLE_W-1:0] signal_in;
    logic [GAIN_W-1:0] gain;
    logic sample_en_clk;
    logic signed [DDS_SAMPLE_W-1:0] signal_out;

    int pass_count = 0;
    int fail_count = 0;

    dds_gain dut (
        .clk(clk),
        .rst_n(rst_n),
        .signal_in(signal_in),
        .gain(gain),
        .sample_en_clk(sample_en_clk),
        .signal_out(signal_out)
    );

    always #5 clk = ~clk;

    task automatic check(
        input logic signed [DDS_SAMPLE_W-1:0] actual,
        input logic signed [DDS_SAMPLE_W-1:0] expected,
        input string label
    );
        if (actual === expected) begin
            $display("PASS | %-30s | actual = %0d", label, actual);
            pass_count++;
        end
        else begin
            $display("FAIL | %-30s | actual = %0d (expected %0d)", label, actual, expected);
            fail_count++;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        signal_in = '0;
        gain = '0;
        sample_en_clk = 1'b0;

        //Reset: signal_out is zero when reset is asserted
        #2;
        check(signal_out, 12'sd0, "Reset: signal_out is zero when reset is asserted");

        //Zero gain: output is zero for a positive input signal
        rst_n = 1'b1;
        signal_in = 12'sd1000;
        gain = 12'h000;
        sample_en_clk = 1'b1;
        @(posedge clk);
        #1;
        check(signal_out, 12'sd0, "Zero gain: output is zero for a positive input signal");
        sample_en_clk = 1'b0;

        //Full gain: output is approximately the input signal at maximum gain
        signal_in = 12'sd1000;
        gain = 12'hFFF;
        sample_en_clk = 1'b1;
        @(posedge clk);
        #1;
        check(signal_out, 12'sd999, "Full gain: output is approximately the input signal at maximum gain");
        sample_en_clk = 1'b0;

        //Half gain: output is approximately half the input signal
        signal_in = 12'sd1000;
        gain = 12'h800;
        sample_en_clk = 1'b1;
        @(posedge clk);
        #1;
        check(signal_out, 12'sd500, "Half gain: output is approximately half the input signal");
        sample_en_clk = 1'b0;

        //Negative signal: half gain preserves the negative sign
        signal_in = -12'sd1000;
        gain = 12'h800;
        sample_en_clk = 1'b1;
        @(posedge clk);
        #1;
        check(signal_out, -12'sd500, "Negative signal: half gain preserves the negative sign");
        sample_en_clk = 1'b0;

        //Zero signal: output is zero regardless of gain
        signal_in = 12'sd0;
        gain = 12'hFFF;
        sample_en_clk = 1'b1;
        @(posedge clk);
        #1;
        check(signal_out, 12'sd0, "Zero signal: output is zero regardless of gain");
        sample_en_clk = 1'b0;

        //Sample enable low: output holds its previous value
        signal_in = 12'sd1500;
        gain = 12'h800;
        sample_en_clk = 1'b1;
        @(posedge clk);
        #1;
        sample_en_clk = 1'b0;
        signal_in = 12'sd500;
        gain = 12'hFFF;
        @(posedge clk);
        #1;
        check(signal_out, 12'sd750, "Sample enable low: output holds its previous value");

        //Maximum positive signal: full gain remains within the signed 12-bit range
        signal_in = 12'sd2047;
        gain = 12'hFFF;
        sample_en_clk = 1'b1;
        @(posedge clk);
        #1;
        check(signal_out, 12'sd2046, "Maximum positive signal: full gain remains within the signed 12-bit range");
        sample_en_clk = 1'b0;

        //Maximum negative signal: full gain remains within the signed 12-bit range
        signal_in = -12'sd2048;
        gain = 12'hFFF;
        sample_en_clk = 1'b1;
        @(posedge clk);
        #1;
        check(signal_out, -12'sd2048, "Maximum negative signal: full gain remains within the signed 12-bit range");
        sample_en_clk = 1'b0;

        //Fractional gain: quarter gain produces approximately one quarter amplitude
        signal_in = 12'sd1200;
        gain = 12'h400;
        sample_en_clk = 1'b1;
        @(posedge clk);
        #1;
        check(signal_out, 12'sd300, "Fractional gain: quarter gain produces approximately one quarter amplitude");
        sample_en_clk = 1'b0;

        $display("SUMMARY | Passed = %0d | Failed = %0d", pass_count, fail_count);

        if (fail_count != 0)
            $fatal(1, "DDS gain testbench failed");
        else
            $finish;
    end

endmodule