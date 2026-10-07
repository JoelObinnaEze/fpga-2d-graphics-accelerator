`timescale 1ns/1ps

module gowin_tmds_serializer (
    input  wire       pixel_clk,
    input  wire       serial_clk,
    input  wire       rst,
    input  wire [9:0] red_symbol,
    input  wire [9:0] green_symbol,
    input  wire [9:0] blue_symbol,
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_data_p,
    output wire [2:0] tmds_data_n
);
    wire red_serial;
    wire green_serial;
    wire blue_serial;
    wire clock_serial;

    OSER10 red_serializer (
        .Q(red_serial),
        .D0(red_symbol[0]), .D1(red_symbol[1]),
        .D2(red_symbol[2]), .D3(red_symbol[3]),
        .D4(red_symbol[4]), .D5(red_symbol[5]),
        .D6(red_symbol[6]), .D7(red_symbol[7]),
        .D8(red_symbol[8]), .D9(red_symbol[9]),
        .PCLK(pixel_clk), .FCLK(serial_clk), .RESET(rst)
    );
    defparam red_serializer.GSREN = "false";
    defparam red_serializer.LSREN = "true";

    OSER10 green_serializer (
        .Q(green_serial),
        .D0(green_symbol[0]), .D1(green_symbol[1]),
        .D2(green_symbol[2]), .D3(green_symbol[3]),
        .D4(green_symbol[4]), .D5(green_symbol[5]),
        .D6(green_symbol[6]), .D7(green_symbol[7]),
        .D8(green_symbol[8]), .D9(green_symbol[9]),
        .PCLK(pixel_clk), .FCLK(serial_clk), .RESET(rst)
    );
    defparam green_serializer.GSREN = "false";
    defparam green_serializer.LSREN = "true";

    OSER10 blue_serializer (
        .Q(blue_serial),
        .D0(blue_symbol[0]), .D1(blue_symbol[1]),
        .D2(blue_symbol[2]), .D3(blue_symbol[3]),
        .D4(blue_symbol[4]), .D5(blue_symbol[5]),
        .D6(blue_symbol[6]), .D7(blue_symbol[7]),
        .D8(blue_symbol[8]), .D9(blue_symbol[9]),
        .PCLK(pixel_clk), .FCLK(serial_clk), .RESET(rst)
    );
    defparam blue_serializer.GSREN = "false";
    defparam blue_serializer.LSREN = "true";

    // LSB-first serialization produces five low bits followed by five high
    // bits, the standard forwarded TMDS pixel clock.
    OSER10 clock_serializer (
        .Q(clock_serial),
        .D0(1'b0), .D1(1'b0), .D2(1'b0), .D3(1'b0), .D4(1'b0),
        .D5(1'b1), .D6(1'b1), .D7(1'b1), .D8(1'b1), .D9(1'b1),
        .PCLK(pixel_clk), .FCLK(serial_clk), .RESET(rst)
    );
    defparam clock_serializer.GSREN = "false";
    defparam clock_serializer.LSREN = "true";

    TLVDS_OBUF red_output (
        .I(red_serial), .O(tmds_data_p[2]), .OB(tmds_data_n[2])
    );
    TLVDS_OBUF green_output (
        .I(green_serial), .O(tmds_data_p[1]), .OB(tmds_data_n[1])
    );
    TLVDS_OBUF blue_output (
        .I(blue_serial), .O(tmds_data_p[0]), .OB(tmds_data_n[0])
    );
    TLVDS_OBUF clock_output (
        .I(clock_serial), .O(tmds_clk_p), .OB(tmds_clk_n)
    );
endmodule
