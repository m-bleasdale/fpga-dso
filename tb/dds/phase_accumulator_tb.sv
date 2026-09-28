//phase_accumulator.sv
//See rtl/dds/phase_accumulator.sv for implementation/comments/explanations

`timescale 1ns/1ps

module tb_phase_accumulator;

    import dso_pkg::*;

    logic clk;
    logic rst_n;
    logic sample_en_clk;
    logic [PHASE_W-1:0] phase_increment;
    logic [PHASE_W-1:0] phase;

    int pass_count = 0;
    int fail_count = 0;

    phase_accumulator dut (
        .clk(clk),
        .rst_n(rst_n),
        .sample_en_clk(sample_en_clk),
        .phase_increment(phase_increment),
        .phase(phase)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task automatic check(input logic [PHASE_W-1:0] actual, input logic [PHASE_W-1:0] exp_val, input string label);
        if (actual === exp_val) begin
            $display("PASS | %-30s | PHASE=%0h", label, actual);
            pass_count++;
        end else begin
            $display("FAIL | %-30s | PHASE=%0h (expected %0h)", label, actual, exp_val);
            fail_count++;
        end
    endtask

    initial begin
        rst_n = 0;
        sample_en_clk = 0;
        phase_increment = '0;

        repeat (2) @(posedge clk);
        #1;

        //Reset: phase == 0
        check(phase, '0, "Reset: phase == 0");

        rst_n = 1;
        @(posedge clk); #1;

        //Post-reset, sample_en=0: phase stays 0
        check(phase, '0, "Post-reset, sample_en=0: phase stays 0");

        phase_increment = 32'h0000_1000;
        @(posedge clk); #1;

        //sample_en_clk=0: no accumulation
        check(phase, '0, "sample_en_clk=0: no accumulation");

        //One increment of 1 -> phase=1
        phase_increment = 32'h0000_0001;
        sample_en_clk = 1;
        @(posedge clk); #1;
        check(phase, 32'h0000_0001, "One increment of 1 -> phase=1");

        //Second increment of 1 -> phase=2
        @(posedge clk); #1;
        check(phase, 32'h0000_0002, "Second increment of 1 -> phase=2");

        //Increment changed to 0x10 -> phase=0x12
        phase_increment = 32'h0000_0010;
        @(posedge clk); #1;
        check(phase, 32'h0000_0012, "Increment changed to 0x10 -> phase=0x12");

        //Second increment of 0x10 -> phase=0x22
        @(posedge clk); #1;
        check(phase, 32'h0000_0022, "Second increment of 0x10 -> phase=0x22");

        //sample_en_clk disabled: phase holds
        sample_en_clk = 0;
        @(posedge clk); #1;
        check(phase, 32'h0000_0022, "sample_en_clk disabled: phase holds");

        //sample_en_clk still disabled: phase holds again
        @(posedge clk); #1;
        check(phase, 32'h0000_0022, "sample_en_clk still disabled: phase holds again");

        //Increment by 0xFFFFFFFF (-1): phase=0x21
        sample_en_clk = 1;
        phase_increment = 32'hFFFF_FFFF;
        @(posedge clk); #1;
        check(phase, 32'h0000_0021, "Increment by 0xFFFFFFFF (-1): phase=0x21");

        //Reset again before overflow test: phase=0
        rst_n = 0;
        @(posedge clk); #1;
        check(phase, '0, "Reset again before overflow test: phase=0");
        rst_n = 1;

        //Increment to max value: phase=0xFFFFFFFF
        phase_increment = 32'hFFFF_FFFF;
        sample_en_clk = 1;
        @(posedge clk); #1;
        check(phase, 32'hFFFF_FFFF, "Increment to max value: phase=0xFFFFFFFF");

        //Overflow wraparound: phase wraps to 0
        phase_increment = 32'h0000_0001;
        @(posedge clk); #1;
        check(phase, 32'h0000_0000, "Overflow wraparound: phase wraps to 0");

        //Pre-async-reset accumulation: phase=5
        phase_increment = 32'h0000_0005;
        sample_en_clk = 1;
        @(posedge clk); #1;
        check(phase, 32'h0000_0005, "Pre-async-reset accumulation: phase=5");

        //Async reset asserted mid-cycle: phase=0 immediately
        #2;
        rst_n = 0;
        #1;
        check(phase, 32'h0000_0000, "Async reset asserted mid-cycle: phase=0 immediately");

        //Post async-reset resume accumulation: phase=5
        rst_n = 1;
        @(posedge clk); #1;
        check(phase, 32'h0000_0005, "Post async-reset resume accumulation: phase=5");

        $display("TESTS COMPLETE: %0d PASSED, %0d FAILED", pass_count, fail_count);

        $finish;
    end

endmodule