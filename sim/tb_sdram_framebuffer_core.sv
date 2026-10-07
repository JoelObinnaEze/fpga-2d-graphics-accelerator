`timescale 1ns/1ps

module tb_sdram_framebuffer_core;
    localparam int unsigned FRAME_WIDTH = 8;
    localparam int unsigned FRAME_HEIGHT = 2;
    localparam int unsigned FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;
    localparam int unsigned READ_FIFO_DEPTH = 8;
    localparam int unsigned READ_BURST_PIXELS = 4;

    logic controller_clk;
    logic controller_rst;
    logic pixel_clk;
    logic pixel_rst;
    logic active_video;
    logic vblank_start;
    logic vblank_active;
    logic [15:0] pixel;
    logic framebuffer_ready;
    logic initialization_active;
    logic prefetch_active;
    logic prefetch_complete;
    logic scanout_enabled;
    logic scanout_underflow;
    logic write_protocol_error;
    logic renderer_write_valid;
    logic renderer_write_ready;
    logic [21:0] renderer_write_pixel_address;
    logic [15:0] renderer_write_data;
    logic present_valid;
    logic present_ready;
    logic [7:0] present_sequence;
    logic present_pending;
    logic present_done;
    logic [7:0] completed_sequence;
    logic [21:0] front_buffer_base;
    logic [21:0] draw_buffer_base;
    logic draw_allowed;
    logic writes_committed;
    logic controller_init_done;
    logic controller_busy_n;
    logic controller_ack;
    logic controller_read_valid;
    logic [31:0] controller_read_data;
    logic controller_write_n;
    logic controller_read_n;
    logic [20:0] controller_address;
    logic [7:0] controller_data_len;
    logic [3:0] controller_data_mask;
    logic [31:0] controller_write_data;
    logic [31:0] memory [0:31];
    int unsigned controller_write_count;
    int unsigned controller_read_count;
    int unsigned completed_prefetch_frames;
    int unsigned completed_presentations;

    typedef enum logic [1:0] {
        MODEL_IDLE,
        MODEL_READ_DATA,
        MODEL_FINISH
    } model_state_t;
    model_state_t model_state;
    logic [4:0] pending_read_address;
    logic [8:0] pending_read_words;

    initial begin
        controller_clk = 1'b0;
        forever #1 controller_clk = ~controller_clk;
    end

    initial begin
        pixel_clk = 1'b0;
        forever #10 pixel_clk = ~pixel_clk;
    end

    initial begin
        #200000;
        $fatal(1, "timed out waiting for SDRAM framebuffer core");
    end

    sdram_framebuffer_core #(
        .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT),
        .READ_FIFO_DEPTH(READ_FIFO_DEPTH),
        .READ_FIFO_LOW_WATER(4),
        .READ_BURST_PIXELS(READ_BURST_PIXELS),
        .WRITE_FIFO_DEPTH(4)
    ) dut (
        .controller_clk,
        .controller_rst,
        .pixel_clk,
        .pixel_rst,
        .active_video,
        .vblank_start,
        .vblank_active,
        .pixel,
        .framebuffer_ready,
        .initialization_active,
        .prefetch_active,
        .prefetch_complete,
        .scanout_enabled,
        .scanout_underflow,
        .write_protocol_error,
        .renderer_write_valid,
        .renderer_write_ready,
        .renderer_write_pixel_address,
        .renderer_write_data,
        .present_valid,
        .present_ready,
        .present_sequence,
        .present_pending,
        .present_done,
        .completed_sequence,
        .front_buffer_base,
        .draw_buffer_base,
        .draw_allowed,
        .writes_committed,
        .controller_init_done,
        .controller_busy_n,
        .controller_ack,
        .controller_read_valid,
        .controller_read_data,
        .controller_write_n,
        .controller_read_n,
        .controller_address,
        .controller_data_len,
        .controller_data_mask,
        .controller_write_data
    );

    function automatic logic [15:0] expected_color(input int x);
        case (x)
            0: return 16'hffff;
            1: return 16'hffe0;
            2: return 16'h07ff;
            3: return 16'h07e0;
            4: return 16'hf81f;
            5: return 16'hf800;
            6: return 16'h001f;
            default: return 16'h0000;
        endcase
    endfunction

    always_ff @(posedge controller_clk) begin
        if (controller_rst) begin
            controller_busy_n <= 1'b1;
            controller_ack <= 1'b0;
            controller_read_valid <= 1'b0;
            controller_read_data <= '0;
            controller_write_count <= 0;
            controller_read_count <= 0;
            completed_prefetch_frames <= 0;
            completed_presentations <= 0;
            model_state <= MODEL_IDLE;
            pending_read_address <= '0;
            pending_read_words <= '0;
        end else begin
            controller_ack <= 1'b0;
            controller_read_valid <= 1'b0;
            if (prefetch_complete)
                completed_prefetch_frames <= completed_prefetch_frames + 1;
            if (present_done)
                completed_presentations <= completed_presentations + 1;

            case (model_state)
                MODEL_IDLE: begin
                    controller_busy_n <= 1'b1;
                    if (!controller_write_n) begin
                        if (controller_address[20:5] != 0)
                            $fatal(1, "test controller write address overflow");
                        if (controller_data_len != 0)
                            $fatal(1, "core issued a non-single-word write");
                        for (int byte_index = 0; byte_index < 4;
                             byte_index++) begin
                            if (!controller_data_mask[byte_index])
                                memory[controller_address[4:0]]
                                    [byte_index * 8 +: 8] <=
                                    controller_write_data
                                    [byte_index * 8 +: 8];
                        end
                        controller_write_count <= controller_write_count + 1;
                        controller_busy_n <= 1'b0;
                        controller_ack <= 1'b1;
                        model_state <= MODEL_FINISH;
                    end else if (!controller_read_n) begin
                        if (controller_address[20:5] != 0)
                            $fatal(1, "test controller read address overflow");
                        if (controller_data_len !=
                            8'(READ_BURST_PIXELS / 2 - 1) ||
                            controller_data_mask != 0)
                            $fatal(1, "core issued an invalid read request");
                        pending_read_address <= controller_address[4:0];
                        pending_read_words <=
                            {1'b0, controller_data_len} + 1'b1;
                        controller_read_count <= controller_read_count + 1;
                        controller_busy_n <= 1'b0;
                        controller_ack <= 1'b1;
                        model_state <= MODEL_READ_DATA;
                    end
                end

                MODEL_READ_DATA: begin
                    controller_busy_n <= 1'b0;
                    controller_read_data <= memory[pending_read_address];
                    controller_read_valid <= 1'b1;
                    pending_read_address <= pending_read_address + 1'b1;
                    pending_read_words <= pending_read_words - 1'b1;
                    if (pending_read_words == 1)
                        model_state <= MODEL_FINISH;
                end

                MODEL_FINISH: begin
                    controller_busy_n <= 1'b1;
                    model_state <= MODEL_IDLE;
                end

                default: model_state <= MODEL_IDLE;
            endcase
        end
    end

    task automatic pulse_vblank;
        @(negedge pixel_clk);
        vblank_active = 1'b1;
        vblank_start = 1'b1;
        @(posedge pixel_clk);
        #1;
        vblank_start = 1'b0;
    endtask

    task automatic end_vblank;
        @(negedge pixel_clk);
        vblank_active = 1'b0;
    endtask

    task automatic write_back_pixel(
        input logic [21:0] pixel_address,
        input logic [15:0] value
    );
        @(negedge controller_clk);
        while (!renderer_write_ready)
            @(negedge controller_clk);
        renderer_write_pixel_address = pixel_address;
        renderer_write_data = value;
        renderer_write_valid = 1'b1;
        @(posedge controller_clk);
        #1;
        renderer_write_valid = 1'b0;
    endtask

    task automatic request_present(input logic [7:0] sequence_id);
        @(negedge controller_clk);
        while (!present_ready)
            @(negedge controller_clk);
        present_sequence = sequence_id;
        present_valid = 1'b1;
        @(posedge controller_clk);
        #1;
        present_valid = 1'b0;
    endtask

    task automatic consume_and_check_frame(input bit modified_first_pixel);
        for (int pixel_index = 0; pixel_index < FRAME_PIXELS;
             pixel_index++) begin
            @(negedge pixel_clk);
            active_video = 1'b1;
            #1;
            if (pixel != (modified_first_pixel && pixel_index == 0
                        ? 16'h1234
                        : expected_color(pixel_index % FRAME_WIDTH)))
                $fatal(1, "scanout pixel %0d was %04x, expected %04x",
                       pixel_index, pixel,
                       expected_color(pixel_index % FRAME_WIDTH));
            @(posedge pixel_clk);
            #1;
        end
        active_video = 1'b0;
    endtask

    initial begin
        controller_rst = 1'b1;
        pixel_rst = 1'b1;
        active_video = 1'b0;
        vblank_start = 1'b0;
        vblank_active = 1'b0;
        renderer_write_valid = 1'b0;
        renderer_write_pixel_address = '0;
        renderer_write_data = '0;
        present_valid = 1'b0;
        present_sequence = '0;
        controller_init_done = 1'b0;
        for (int word_index = 0; word_index < 32; word_index++)
            memory[word_index] = '0;

        repeat (4) @(posedge controller_clk);
        controller_rst = 1'b0;
        repeat (4) @(posedge pixel_clk);
        pixel_rst = 1'b0;
        controller_init_done = 1'b1;

        wait (framebuffer_ready);
        if (controller_write_count != 2 * FRAME_PIXELS ||
            initialization_active || write_protocol_error)
            $fatal(1, "both startup framebuffers did not commit exactly once");
        for (int buffer_index = 0; buffer_index < 2; buffer_index++) begin
            for (int pixel_index = 0; pixel_index < FRAME_PIXELS;
                 pixel_index += 2) begin
                if (memory[(buffer_index * FRAME_PIXELS + pixel_index) / 2] !=
                    {expected_color((pixel_index + 1) % FRAME_WIDTH),
                     expected_color(pixel_index % FRAME_WIDTH)})
                    $fatal(1, "buffer %0d word %0d was %08x",
                           buffer_index, pixel_index / 2,
                           memory[(buffer_index * FRAME_PIXELS + pixel_index) / 2]);
            end
        end
        if (front_buffer_base != 0 ||
            draw_buffer_base != 22'(FRAME_PIXELS) ||
            !draw_allowed || !writes_committed)
            $fatal(1, "startup buffer ownership was incorrect");

        repeat (30) @(posedge pixel_clk);
        while (!scanout_enabled) begin
            pulse_vblank();
            if (!scanout_enabled)
                repeat (20) @(posedge pixel_clk);
        end
        end_vblank();
        if (controller_read_count !=
            READ_FIFO_DEPTH / READ_BURST_PIXELS)
            $fatal(1,
                   "initial FIFO fill used %0d commands instead of %0d bursts",
                   controller_read_count,
                   READ_FIFO_DEPTH / READ_BURST_PIXELS);
        if (!prefetch_active)
            $fatal(1, "initial prefetch stopped before filling the first frame");

        write_back_pixel(22'd0, 16'h1234);
        wait (writes_committed);
        if (memory[FRAME_PIXELS / 2][15:0] != 16'h1234)
            $fatal(1, "renderer write did not target the back buffer");
        request_present(8'h55);
        if (!present_pending || draw_allowed)
            $fatal(1, "PRESENT did not lock the draw buffer");

        consume_and_check_frame(1'b0);
        if (scanout_underflow)
            $fatal(1, "first framebuffer scanout underflowed");

        pulse_vblank();
        for (int timeout = 0; timeout < 2000 && completed_presentations == 0;
             timeout++)
            @(posedge controller_clk);
        if (completed_presentations != 1 || completed_sequence != 8'h55 ||
            front_buffer_base != 22'(FRAME_PIXELS) ||
            draw_buffer_base != 0 ||
            present_pending || !draw_allowed)
            $fatal(1, "committed presentation did not swap ownership cleanly");
        while (!scanout_enabled)
            @(posedge pixel_clk);
        end_vblank();

        consume_and_check_frame(1'b1);
        if (scanout_underflow || completed_prefetch_frames == 0)
            $fatal(1, "new front buffer did not scan without stale data");

        // Stop accepting new memory requests and consume buffered pixels until
        // the documented black fallback and sticky underflow status appear.
        controller_init_done = 1'b0;
        for (int cycle = 0; cycle < 3 * READ_FIFO_DEPTH &&
             !scanout_underflow; cycle++) begin
            @(negedge pixel_clk);
            active_video = 1'b1;
            @(posedge pixel_clk);
            #1;
        end
        @(negedge pixel_clk);
        #1;
        if (!scanout_underflow || pixel != 16'h0000)
            $fatal(1, "scanout underflow did not latch black fallback");

        $display("PASS: dual-buffer SDRAM scanout, committed swap, FIFO flush, and underflow");
        $finish;
    end
endmodule
