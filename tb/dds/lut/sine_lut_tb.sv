`timescale 1ns/1ps

module tb_sine_lut;

    import dso_pkg::*;

    logic clk;
    logic rst_n;
    logic [PHASE_W-1:0] phase;
    logic sample_en_clk;
    logic signed [DDS_SAMPLE_W-1:0] sine_out;

    logic [PHASE_W-1:0] phase_acc;
    logic [PHASE_W-1:0] phase_inc;
    logic sweep_en;

    int pass_count = 0;
    int fail_count = 0;

    logic signed [DDS_SAMPLE_W-1:0] ref_lut [0:LUT_DEPTH-1];
    logic signed [DDS_SAMPLE_W-1:0] captured [0:LUT_DEPTH-1];

    assign phase = phase_acc;
    assign sample_en_clk = sweep_en;

    sine_lut dut (
        .clk(clk),
        .rst_n(rst_n),
        .phase(phase),
        .sample_en_clk(sample_en_clk),
        .sine_out(sine_out)
    );

    //phase accumulator, kept in the testbench since the DUT only consumes phase, it does not generate it
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) phase_acc <= '0;
        else if (sweep_en) phase_acc <= phase_acc + phase_inc;
    end

    initial clk = 0;
    always #5 clk = ~clk;

    initial $readmemh("./rtl/dds/lut/sine_lut.hex", ref_lut);

    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_sine_lut);
    end

    task check(input integer actual, input integer expected, input string label);
        if (actual === expected) begin
            pass_count = pass_count + 1;
            $display("PASS | %-30s | actual=%0d expected=%0d", label, actual, expected);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL | %-30s | actual=%0d (expected %0d)", label, actual, expected);
        end
    endtask

    //sweeps the LUT once, stepping the LUT address by addr_step per sample, and writes each sample to filename for external plotting
    task automatic run_sweep(input int addr_step, input string filename);
        integer fh;
        int i;
        rst_n = 0;
        sweep_en = 0;
        repeat (2) @(posedge clk);
        phase_inc = addr_step << (PHASE_W - LUT_ADDR_W);
        rst_n = 1;
        @(posedge clk);
        #1;
        sweep_en = 1;
        fh = $fopen(filename, "w");
        for (i = 0; i < LUT_DEPTH; i = i + 1) begin
            @(posedge clk);
            #1;
            captured[i] = sine_out;
            $fdisplay(fh, "%0d %0d", i, sine_out);
        end
        sweep_en = 0;
        $fclose(fh);
    endtask

    initial begin
        rst_n = 0;
        sweep_en = 0;
        phase_inc = '0;
        //Reset: sine_out held at zero
        repeat (3) @(posedge clk);
        #1;
        check(sine_out, 0, "Reset: sine_out held at zero");
        rst_n = 1;
        @(posedge clk);

        run_sweep(1, "sine_1hz.txt");
        //First sample of 1Hz sweep matches LUT[0]
        check(captured[0], ref_lut[0], "First sample of 1Hz sweep matches LUT[0]");
        //Quarter point of 1Hz sweep matches LUT[1024]
        check(captured[LUT_DEPTH/4], ref_lut[LUT_DEPTH/4], "Quarter point of 1Hz sweep matches LUT[1024]");
        //Half point of 1Hz sweep matches LUT[2048]
        check(captured[LUT_DEPTH/2], ref_lut[LUT_DEPTH/2], "Half point of 1Hz sweep matches LUT[2048]");
        //Last sample of 1Hz sweep matches LUT[4095]
        check(captured[LUT_DEPTH-1], ref_lut[LUT_DEPTH-1], "Last sample of 1Hz sweep matches LUT[4095]");

        run_sweep(2, "sine_2hz.txt");
        //First sample of 2Hz sweep matches LUT[0]
        check(captured[0], ref_lut[0], "First sample of 2Hz sweep matches LUT[0]");
        //Quarter point of 2Hz sweep matches LUT[2048] due to doubled step
        check(captured[LUT_DEPTH/4], ref_lut[LUT_DEPTH/2], "Quarter point of 2Hz sweep matches LUT[2048] due to doubled step");
        //Halfway through 2Hz sweep restarts at LUT[0] after one full cycle
        check(captured[LUT_DEPTH/2], ref_lut[0], "Halfway through 2Hz sweep restarts at LUT[0] after one full cycle");
        //Last sample of 2Hz sweep matches LUT[4094]
        check(captured[LUT_DEPTH-1], ref_lut[LUT_DEPTH-2], "Last sample of 2Hz sweep matches LUT[4094]");

        $display("%0d passed, %0d failed", pass_count, fail_count);
        $finish;
    end

endmodule