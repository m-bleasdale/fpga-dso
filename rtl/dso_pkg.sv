package dso_pkg;

    parameter int CLK_FREQ = 50_000_000;

    //DDS (signal generator) sample width
    //MCP4822-E/P - 12 bit DAC
    parameter int DDS_SAMPLE_W = 12;

    //DDS output clock divider 
    //DAC output rate = 200 kHz (1/250 of 50 MHz clock)
    parameter int DDS_CLK_DIVIDER = 250;

    //Phase accumulator width
    parameter int PHASE_W = 32;

    //Gain register width
    parameter int GAIN_W = 12;

    //DDS LUT depth, number of entries in LUT (resolution)
    parameter int LUT_ADDR_W = 12;
    parameter int LUT_DEPTH = 1 << LUT_ADDR_W;

    //DAC SPI clock, bit transfer rate
    //5 MHz
    //50 MHz / 2*5 MHz = 5
    parameter int SPI_CLK_DIVIDER = 5;

    //UART BAUD rate, 2 MHz
    //3 MHz gives 16.67 clks per bit (4% error, too high), 2 MHz is exactly 25 clks per bit
    parameter int UART_BAUD = 2_000_000;

    //ADC sample clock, 2 MHz
    parameter int SYS_CLK_HZ = 50_000_000;
    parameter int ADC_SAMPLE_HZ = 2_000_000;

    //ADC sample width, 8 bits
    parameter int ADC_SAMPLE_W = 8;

    //capture buffer, 8192 samples (4.096 ms @ 2 MHz, no decimation)
    //2048 samples kept before the trigger
    parameter int CAPTURE_DEPTH = 8192;
    parameter int PRETRIG_DEPTH = 2048;

    //trigger hysteresis in ADC LSBs, stops noise causing false triggers
    parameter int TRIG_HYST = 4;

    //laptop command frame: 0xA5, cmd, d0, d1, d2, d3 (data little endian)
    parameter logic [7:0] CMD_SYNC = 8'hA5;
    parameter logic [7:0] CMD_SET_FREQ = 8'h01; //phase_increment, 32 bits
    parameter logic [7:0] CMD_SET_GAIN = 8'h02; //gain, low 12 bits
    parameter logic [7:0] CMD_SET_TRIG_LEVEL = 8'h03; //trig level, low 8 bits
    parameter logic [7:0] CMD_SET_TRIG_EDGE = 8'h04; //bit 0, 1 = rising
    parameter logic [7:0] CMD_SET_DECIMATION = 8'h05; //low 16 bits
    parameter logic [7:0] CMD_FORCE_TRIG = 8'h06; //data ignored

    //values on reset
    //1 kHz sine: 1000 * 2^32 / 200 kHz
    parameter logic [PHASE_W-1:0] DEFAULT_PHASE_INC = 32'd21474836;
    parameter logic [GAIN_W-1:0] DEFAULT_GAIN = 12'hFFF;
    parameter logic [ADC_SAMPLE_W-1:0] DEFAULT_TRIG_LEVEL = 8'd128;
    parameter logic [15:0] DEFAULT_DECIMATION = 16'd1;

endpackage: dso_pkg