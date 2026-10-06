`timescale 1ns/1ps

module sprite_store #(
    parameter int unsigned SPRITE_COUNT = 1,
    parameter int unsigned PIXEL_COUNT = 1,
    parameter DESCRIPTOR_FILE = "",
    parameter COLOR_FILE = "",
    parameter OPACITY_FILE = ""
) (
    input  logic clk,
    input  logic [15:0] sprite_id,
    output logic descriptor_valid,
    output logic [31:0] descriptor_base,
    output logic [15:0] descriptor_width,
    output logic [15:0] descriptor_height,
    input  logic read_enable,
    input  logic [31:0] read_address,
    output logic pixel_valid,
    output logic [15:0] pixel_color,
    output logic pixel_opaque
);
    logic [63:0] descriptors [0:SPRITE_COUNT-1];
    logic [15:0] colors [0:PIXEL_COUNT-1];
    logic opacity [0:PIXEL_COUNT-1];

    initial begin
        for (int i = 0; i < SPRITE_COUNT; i++)
            descriptors[i] = '0;
        for (int i = 0; i < PIXEL_COUNT; i++) begin
            colors[i] = '0;
            opacity[i] = 1'b0;
        end
        if (DESCRIPTOR_FILE != "")
            $readmemh(DESCRIPTOR_FILE, descriptors);
        if (COLOR_FILE != "")
            $readmemh(COLOR_FILE, colors);
        if (OPACITY_FILE != "")
            $readmemh(OPACITY_FILE, opacity);
    end

    always_comb begin
        descriptor_valid = int'(sprite_id) < SPRITE_COUNT;
        descriptor_base = '0;
        descriptor_width = '0;
        descriptor_height = '0;
        if (descriptor_valid) begin
            descriptor_base = descriptors[int'(sprite_id)][31:0];
            descriptor_width = descriptors[int'(sprite_id)][47:32];
            descriptor_height = descriptors[int'(sprite_id)][63:48];
        end
    end

    always_ff @(posedge clk) begin
        pixel_valid <= read_enable;
        pixel_color <= '0;
        pixel_opaque <= 1'b0;
        if (read_enable && int'(read_address) < PIXEL_COUNT) begin
            pixel_color <= colors[int'(read_address)];
            pixel_opaque <= opacity[int'(read_address)];
        end
    end
endmodule
