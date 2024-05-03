/**
 * File: chip.sv
 * Authors: Christopher Porco
 *
 * Summary: Primary design file for my 18-224 project, ClockBox
 *
 * Design Guidelines:
 * - Use "TODO" and no other variation for identifying things to do, possible bugs, etc.
 * - Use "_L" for active low signals
 * - Use UpperCamelCase for modules
 * - Use snake_case for variables
 * - Use ALL_CAPS for parameters and enums
 *
 * Notes:
 * - No generate/packed arrays used since they aren't compatible with Yosys
 */

`default_nettype none

// Global parameters
parameter CLOCK_RATE = 10000000; // 10 MHz
parameter REFRESH_RATE = 376;
parameter NUM_COLS = 13;
parameter COL_SEL_BITS = $clog2(NUM_COLS); // 4 bits
parameter NUM_ROWS = 5;
parameter NUM_DIGITS = 4;
parameter DIGIT_BITS = 4;

// Top module
module my_chip (
    input logic [11:0] io_in, // Inputs to your chip
    output logic [11:0] io_out, // Outputs from your chip
    input logic clock,
    input logic reset // Important: Reset is ACTIVE-HIGH
);

    ///////////////////////
    ///// DEFINITIONS /////
    ///////////////////////

    enum logic       {NO_BUF, BUF} start_state, start_state_next, stop_state, stop_state_next, power_state, power_state_next;
    enum logic [2:0] {CLOCK, CLOCK_SET, CHRONO} cur_state, next_state;

    // Input buffer and button logic
    localparam BTN_BOUNCE_TIME = CLOCK_RATE/20;
    localparam BTN_BOUNCE_SIZE = $clog2(BTN_BOUNCE_TIME);

    logic start_tmp0, stop_tmp0, power_tmp0, mode_tmp0;
    logic start_tmp1, stop_tmp1, power_tmp1, mode_tmp1;
    logic start_bounce, stop_bounce, mode_bounce, power_bounce;
    logic [BTN_BOUNCE_SIZE-1:0] button_count;
    logic start_buf, stop_buf, mode_buf, power_buf;
    logic start_pressed, power_pressed;
    logic stop_pressed, stop_held, mode_pressed, mode_held;

    // LED logic
    logic show_leading_0, pm, pm_drive, blink_drive;

    //////////////////////////////
    ///// INPUT BUFFER LOGIC /////
    //////////////////////////////

    // Buffer inputs to avoid metastability
    always_ff @(posedge clock) begin
        if (reset) begin
            start_tmp0 <= 1'b0;
            stop_tmp0 <= 1'b0;
            power_tmp0 <= 1'b0;
            mode_tmp0 <= 1'b0;

            start_tmp1 <= 1'b0;
            stop_tmp1 <= 1'b0;
            power_tmp1 <= 1'b0;
            mode_tmp1 <= 1'b0;

            start_bounce <= 1'b0;
            stop_bounce <= 1'b0;
            power_bounce <= 1'b0;
            mode_bounce <= 1'b0;
        end
        else begin
            start_tmp0 <= io_in[3];
            stop_tmp0 <= io_in[2];
            power_tmp0 <= io_in[1];
            mode_tmp0 <= io_in[0];

            start_tmp1 <= start_tmp0;
            stop_tmp1 <= stop_tmp0;
            power_tmp1 <= power_tmp0;
            mode_tmp1 <= mode_tmp0;

            start_bounce <= start_tmp1;
            stop_bounce <= stop_tmp1;
            power_bounce <= power_tmp1;
            mode_bounce <= mode_tmp1;
        end
    end

    // Debounced the buttons to ensure only one press is seen
    always_ff @(posedge clock) begin
        if (reset) begin
            start_buf <= 1'b0;
            stop_buf <= 1'b0;
            power_buf <= 1'b0;
            mode_buf <= 1'b0;
            button_count <= 'd0;
        end
        else begin
            if (button_count == BTN_BOUNCE_TIME) begin
                start_buf <= start_bounce;
                stop_buf <= stop_bounce;
                power_buf <= power_bounce;
                mode_buf <= mode_bounce;
                button_count <= 'd0;
            end
            else begin
                button_count <= button_count + 'd1;
            end 
        end
    end

    // Excludes mode and stop since they need hold functionality
    always_ff @(posedge clock) begin
        if (reset) begin
            start_state <= NO_BUF;
            power_state <= NO_BUF;
        end
        else begin
            start_state <= start_state_next;
            power_state <= power_state_next;
        end
    end

    // Next state and output logic
    // Generates 1 clock when button is released
    always_comb begin
        start_pressed = 1'b0;
        power_pressed = 1'b0;

        // Same logic for all three buttons
        case (start_state)
            NO_BUF: begin
                if (start_buf) start_state_next = BUF;
                else           start_state_next = NO_BUF;
            end
            BUF: begin
                if (~start_buf) begin
                    start_state_next = NO_BUF;
                    start_pressed = 1'b1;
                end
                else begin
                    start_state_next = BUF;
                end
            end
        endcase

        case (power_state)
            NO_BUF: begin
                if (power_buf) power_state_next = BUF;
                else           power_state_next = NO_BUF;
            end
            BUF: begin
                if (~power_buf) begin
                    power_state_next = NO_BUF;
                    power_pressed = 1'b1;
                end
                else begin
                    power_state_next = BUF;
                end
            end
        endcase
    end

    /////////////////////////////
    ///// BUTTON HOLD LOGIC /////
    /////////////////////////////

    DetectButtonHold stophold0 (.clock, .reset, .button(stop_buf),
        .button_pressed(stop_pressed), .button_held(stop_held));

    DetectButtonHold modehold0 (.clock, .reset, .button(mode_buf),
        .button_pressed(mode_pressed), .button_held(mode_held));

    //////////////////////
    ///// TIME LOGIC /////
    //////////////////////

    localparam CLOCK_1SEC = CLOCK_RATE;
    localparam CLOCK_1SEC_SIZE = $clog2(CLOCK_1SEC); // 24 bits at 10 MHz
    
    localparam CLOCK_60SEC = 60*CLOCK_RATE;
    localparam CLOCK_60SEC_SIZE = $clog2(CLOCK_60SEC); // 30 bits at 10 MHz

    // Yosys doesn't like packed arrays
    logic [1:0] clock_digit_sel;
    logic [DIGIT_BITS-1:0] cur_time0, cur_time1, cur_time2, cur_time3;

    logic [CLOCK_60SEC_SIZE-1:0] clock_count;
    logic [DIGIT_BITS-1:0] clock_time0, clock_time1, clock_time2, clock_time3;
    
    logic run_chrono;
    logic [CLOCK_1SEC_SIZE-1:0] chrono_count;
    logic [DIGIT_BITS-1:0] chrono_time0, chrono_time1, chrono_time2, chrono_time3;

    // Clock counter
    always_ff @(posedge clock) begin
        if (reset) begin
            clock_time3 <= 'd1;
            clock_time2 <= 'd0;
            clock_time1 <= 'd3;
            clock_time0 <= 'd4;
            clock_count <= 'd0;
            clock_digit_sel <= 'd2;
            pm <= 1'b0;
        end
        // Set the clock. Assume 0 seconds/elapsed time when exiting
        else if (cur_state == CLOCK_SET) begin
            clock_count <= 'd0;
            if (start_pressed) begin
                if (clock_digit_sel == 'd0) begin
                    clock_digit_sel <= 'd2;
                end
                else begin
                    clock_digit_sel <= clock_digit_sel - 'd1;
                end
            end
            else if (stop_pressed) begin
                case (clock_digit_sel)
                    2'd0: begin
                        if (clock_time0 == 'd9) begin
                            clock_time0 <= 'd0;
                            if (clock_time1 == 'd5) begin
                                clock_time1 <= 'd0;
                                if (clock_time2 == 'd9) begin
                                    clock_time2 <= 'd0;
                                    clock_time3 <= 'd1;
                                end
                                else if (clock_time3 == 'd1 && clock_time2 == 'd2) begin
                                    clock_time2 <= 'd1;
                                    clock_time3 <= 'd0;
                                end
                                else begin
                                    clock_time2 <= clock_time2 + 'd1;
                                    if (clock_time3 == 'd1 && clock_time2 == 'd1) begin
                                        pm <= ~pm;
                                    end
                                end
                            end
                            else begin
                                clock_time1 <= clock_time1 + 'd1;
                            end
                        end
                        else begin
                            clock_time0 <= clock_time0 + 'd1;
                        end
                    end
                    2'd1: begin
                        if (clock_time1 == 'd5) begin
                            clock_time1 <= 'd0;
                            if (clock_time2 == 'd9) begin
                                clock_time2 <= 'd0;
                                clock_time3 <= 'd1;
                            end
                            else if (clock_time3 == 'd1 && clock_time2 == 'd2) begin
                                clock_time2 <= 'd1;
                                clock_time3 <= 'd0;
                            end
                            else begin
                                clock_time2 <= clock_time2 + 'd1;
                                if (clock_time3 == 'd1 && clock_time2 == 'd1) begin
                                    pm <= ~pm;
                                end
                            end
                        end
                        else begin
                            clock_time1 <= clock_time1 + 'd1;
                        end
                    end
                    2'd2: begin
                        if (clock_time2 == 'd9) begin
                            clock_time2 <= 'd0;
                            clock_time3 <= 'd1;
                        end
                        else if (clock_time3 == 'd1 && clock_time2 == 'd2) begin
                            clock_time2 <= 'd1;
                            clock_time3 <= 'd0;
                        end
                        else begin
                            clock_time2 <= clock_time2 + 'd1;
                            if (clock_time3 == 'd1 && clock_time2 == 'd1) begin
                                pm <= ~pm;
                            end
                        end
                    end
                    2'd3: begin
                        // Don't do anything
                        // Selecting 3 is really selecting 2
                    end
                    default: begin
                    end
                endcase
            end
        end
        // If not setting the clock, then in any other mode, the clock should
        // be running and updated as needed
        else if (clock_count == CLOCK_60SEC) begin
            clock_count <= 'd1; // saw another tick while doing this logic, start the next second counting
            if (clock_time0 == 'd9) begin
                clock_time0 <= 'd0;
                if (clock_time1 == 'd5) begin
                    clock_time1 <= 'd0;
                    if (clock_time2 == 'd9) begin
                        clock_time2 <= 'd0;
                        clock_time3 <= 'd1;
                    end
                    else if (clock_time3 == 'd1 && clock_time2 == 'd2) begin
                        clock_time2 <= 'd1;
                        clock_time3 <= 'd0;
                    end
                    else begin
                        clock_time2 <= clock_time2 + 'd1;
                        if (clock_time3 == 'd1 && clock_time2 == 'd1) begin
                            pm <= ~pm;
                        end
                    end
                end
                else begin
                    clock_time1 <= clock_time1 + 'd1;
                end
            end
            else begin
                clock_time0 <= clock_time0 + 'd1;
            end
        end
        else begin
            clock_count <= clock_count + 'd1;
        end
    end

    // Chrono counter
    always_ff @(posedge clock) begin
        if (reset || (cur_state == CHRONO && stop_held)) begin
            chrono_time0 <= 'd0;
            chrono_time1 <= 'd0;
            chrono_time2 <= 'd0;
            chrono_time3 <= 'd0;
            chrono_count <= 'd0;
            run_chrono <= 'd0;
        end
        else if (cur_state == CHRONO && ((start_pressed && !run_chrono) || (stop_pressed && run_chrono))) begin
            run_chrono <= ~run_chrono;
        end
        // Increment the chrono. Similar to clock, but goes up to 89:59 (90 mins) then back to 00:00
        else if (run_chrono) begin
            if (chrono_count == CLOCK_1SEC) begin
                chrono_count <= 'd1; // saw another tick while doing this logic, start the next second counting
                if (chrono_time0 == 'd9) begin
                    chrono_time0 <= 'd0;
                    if (chrono_time1 == 'd5) begin
                        chrono_time1 <= 'd0;
                        if (chrono_time2 == 'd9) begin
                            chrono_time2 <= 'd0;
                            if (chrono_time3 == 'd8) begin
                                chrono_time3 <= 'd0;
                            end
                            else begin
                                chrono_time3 <= chrono_time3 + 'd1;
                            end
                        end
                        else begin
                            chrono_time2 <= chrono_time2 + 'd1;
                        end
                    end
                    else begin
                        chrono_time1 <= chrono_time1 + 'd1;
                    end
                end
                else begin
                    chrono_time0 <= chrono_time0 + 'd1;
                end
            end
            else begin
                chrono_count <= chrono_count + 'd1;
            end
        end
    end

    //////////////////////
    ///// TIME STATE /////
    //////////////////////

    always_ff @(posedge clock) begin
        if (reset) cur_state <= CLOCK;
        else       cur_state <= next_state;
    end

    // Next state logic
    always_comb begin
        next_state = CLOCK;
        case (cur_state)
            CLOCK: begin
                if      (mode_held)    next_state = CLOCK_SET;
                else if (mode_pressed) next_state = CHRONO;
                else                   next_state = CLOCK;
            end
            CLOCK_SET: begin
                if      (mode_held)    next_state = CLOCK;
                else if (mode_pressed) next_state = CLOCK;
                else                   next_state = CLOCK_SET;
            end
            CHRONO: begin
                if      (mode_held)    next_state = CHRONO;
                else if (mode_pressed) next_state = CLOCK;
                else                   next_state = CHRONO;
            end
            default: begin
                next_state = CLOCK;
            end
        endcase
    end

    // Output logic, including time to display
    always_comb begin
        show_leading_0 = 1'b0;
        cur_time0 = clock_time0;
        cur_time1 = clock_time1;
        cur_time2 = clock_time2;
        cur_time3 = clock_time3;
        case (cur_state)
            CLOCK: begin
                cur_time0 = clock_time0;
                cur_time1 = clock_time1;
                cur_time2 = clock_time2;
                cur_time3 = clock_time3;
                if (cur_time3 != 'd0) show_leading_0 = 1'b1;
            end
            CLOCK_SET: begin
                cur_time0 = clock_time0;
                cur_time1 = clock_time1;
                cur_time2 = clock_time2;
                cur_time3 = clock_time3;
                if (cur_time3 != 'd0) show_leading_0 = 1'b1;
            end
            CHRONO: begin
                cur_time0 = chrono_time0;
                cur_time1 = chrono_time1;
                cur_time2 = chrono_time2;
                cur_time3 = chrono_time3;
                show_leading_0 = 1'b1;
            end
            default: begin
                cur_time0 = clock_time0;
                cur_time1 = clock_time1;
                cur_time2 = clock_time2;
                cur_time3 = clock_time3;
            end
        endcase
    end

    //////////////////////
    ///// LED DRIVER /////
    //////////////////////

    assign pm_drive = pm & (cur_state == CLOCK_SET);
    assign blink_drive = (cur_state == CLOCK_SET);

    LEDDriver leddrive0 (.clock, .reset, .power_pressed, .show_leading_0,
        .pm(pm_drive), .blink(blink_drive), .blink_sel(clock_digit_sel),
        .cur_time0, .cur_time1, .cur_time2, .cur_time3,
        .col_sel(io_out[3:0]), .row_L(io_out[8:4]));

endmodule

// Takes in current time to be displayed and toggles output to drive the LEDs
// Keeps track of power mode which controls LED brightness
module LEDDriver
    (input  logic                    clock, reset,
     input  logic                    power_pressed,
     input  logic                    show_leading_0, pm, blink,
     input  logic [1:0]              blink_sel,
     input  logic [DIGIT_BITS-1:0]   cur_time0, cur_time1, cur_time2, cur_time3,
     output logic [COL_SEL_BITS-1:0] col_sel,
     output logic [NUM_ROWS-1:0]     row_L);

    ///////////////////////
    ///// DEFINITIONS /////
    ///////////////////////

    localparam NUM_CYC_COL = (CLOCK_RATE)/(REFRESH_RATE*NUM_COLS);
    localparam BITS_CYC_COL = $clog2(NUM_CYC_COL);

    enum logic [2:0] {POWER0, POWER1, POWER2, POWER3, POWER4, POWERMAX} power_mode, power_mode_next;

    logic en_led, en_led_threshold;

    logic inc_col, clear_col, reset_colcount;
    logic [BITS_CYC_COL-1:0] in_colcount, out_colcount;
    logic [NUM_ROWS-1:0] dig0col0, dig0col1, dig0col2,
                         dig1col0, dig1col1, dig1col2,
                         dig2col0, dig2col1, dig2col2,
                         dig3col0, dig3col1, dig3col2;

    ///////////////////////
    ///// POWER LOGIC /////
    ///////////////////////

    always_ff @(posedge clock) begin
        if (reset) power_mode <= POWERMAX;
        else       power_mode <= power_mode_next;
    end

    // Next state logic
    always_comb begin
        power_mode_next = power_mode;
        if (power_pressed) begin
            case (power_mode)
                POWER0:  power_mode_next = POWER1;
                POWER1:  power_mode_next = POWER2;
                POWER2:  power_mode_next = POWER3;
                POWER3:  power_mode_next = POWER4;
                POWER4:  power_mode_next = POWERMAX;
                POWERMAX: power_mode_next = POWER0;
            endcase
        end
    end

    // Output logic: vary duty cycle based on mode
    always_comb begin
        en_led = 1'd1;
        case (power_mode)
            POWER0: begin
                en_led = 1'd0;
            end
            POWER1: begin
                if (out_colcount >= (NUM_CYC_COL/10)*2) begin
                    en_led = 1'd0;
                end
            end
            POWER2: begin
                if (out_colcount >= (NUM_CYC_COL/10)*4) begin
                    en_led = 1'd0;
                end
            end
            POWER3: begin
                if (out_colcount >= (NUM_CYC_COL/10)*6) begin
                    en_led = 1'd0;
                end
            end
            POWER4: begin
                if (out_colcount >= (NUM_CYC_COL/10)*8) begin
                    en_led = 1'd0;
                end
            end
            POWERMAX: begin
                en_led = 1'd1;
            end
            default: begin
                en_led = 1'd1;
            end
        endcase
    end

    /////////////////////
    ///// LED LOGIC /////
    /////////////////////

    localparam CLK_BITS = $clog2(CLOCK_RATE);
    logic en_blink;
    logic [CLK_BITS-1:0] out_clockcount;

    always_ff @(posedge clock) begin
        if (reset || out_clockcount == CLOCK_RATE) begin
            out_clockcount <= 'd0;
        end
        else begin
            out_clockcount <= out_clockcount + 'd1;
        end
    end

    // Blinks the whole display — blink_sel limits the digits
    //  0 |  1  |  0 |  1
    // on | off | on | off
    assign en_blink = blink & ((out_clockcount >= ((CLOCK_RATE-1)*3)/4) | (out_clockcount < ((CLOCK_RATE-1)*2)/4 & out_clockcount >= ((CLOCK_RATE-1)*1)/4));

    // Counter to increment the column
    assign inc_col = (out_colcount == NUM_CYC_COL-1);
    assign reset_colcount = reset | inc_col;
    assign in_colcount = out_colcount + 'd1;

    Register #(BITS_CYC_COL, {BITS_CYC_COL{1'b0}}) colcount0 (.clock,
        .reset(reset_colcount), .en(1'd1), .D(in_colcount), .Q(out_colcount));

    assign clear_col = inc_col & (col_sel == 'd12);

    // State
    always_ff @(posedge clock) begin
        if (reset || clear_col) begin
            col_sel <= 'd0;
        end
        else if (inc_col) begin
            col_sel <= col_sel + 'd1;
        end
    end

    ConvertDigit cd0 (.digit(cur_time3), .col0(dig0col0), .col1(dig0col1), .col2(dig0col2));
    ConvertDigit cd1 (.digit(cur_time2), .col0(dig1col0), .col1(dig1col1), .col2(dig1col2));
    ConvertDigit cd2 (.digit(cur_time1), .col0(dig2col0), .col1(dig2col1), .col2(dig2col2));
    ConvertDigit cd3 (.digit(cur_time0), .col0(dig3col0), .col1(dig3col1), .col2(dig3col2));

    // Output logic
    always_comb begin
        if (en_led) begin
            case (col_sel)
                4'd0: begin
                    if (show_leading_0 && !(en_blink && blink_sel == 'd2)) begin
                        row_L = ~dig0col0;
                    end
                    else begin
                        row_L = 5'b11111;
                    end
                end
                4'd1: begin
                    if (show_leading_0 && !(en_blink && blink_sel == 'd2)) begin
                        row_L = ~dig0col1;
                    end
                    else begin
                        row_L = 5'b11111;
                    end
                end
                4'd2: begin
                    if (show_leading_0 && !(en_blink && blink_sel == 'd2)) begin
                        row_L = ~dig0col2;
                    end
                    else begin
                        row_L = 5'b11111;
                    end
                end
                4'd3: begin
                    if (!(en_blink && blink_sel == 'd2)) begin
                        row_L = ~dig1col0;
                    end
                    else begin
                        row_L = 5'b11111;
                    end
                end
                4'd4: begin
                    if (!(en_blink && blink_sel == 'd2)) begin
                        row_L = ~dig1col1;
                    end
                    else begin
                        row_L = 5'b11111;
                    end
                end
                4'd5: begin
                    if (!(en_blink && blink_sel == 'd2)) begin
                        row_L = ~dig1col2;
                    end
                    else begin
                        row_L = 5'b11111;
                    end
                end
                4'd6: begin
                    row_L = {2'b10, ~pm, 2'b01};
                end
                4'd7: begin
                    if (!(en_blink && blink_sel == 'd1)) begin
                        row_L = ~dig2col0;
                    end
                    else begin
                        row_L = 5'b11111;
                    end
                end
                4'd8: begin
                    if (!(en_blink && blink_sel == 'd1)) begin
                        row_L = ~dig2col1;
                    end
                    else begin
                        row_L = 5'b11111;
                    end
                end
                4'd9: begin
                    if (!(en_blink && blink_sel == 'd1)) begin
                        row_L = ~dig2col2;
                    end
                    else begin
                        row_L = 5'b11111;
                    end
                end
                4'd10: begin
                    if (!(en_blink && blink_sel == 'd0)) begin
                        row_L = ~dig3col0;
                    end
                    else begin
                        row_L = 5'b11111;
                    end
                end
                4'd11: begin
                    if (!(en_blink && blink_sel == 'd0)) begin
                        row_L = ~dig3col1;
                    end
                    else begin
                        row_L = 5'b11111;
                    end
                end
                4'd12: begin
                    if (!(en_blink && blink_sel == 'd0)) begin
                        row_L = ~dig3col2;
                    end
                    else begin
                        row_L = 5'b11111;
                    end
                end
                default: begin
                    row_L = 5'b00000;
                end
            endcase
        end
        else begin
            row_L = 5'b11111;
        end
    end

endmodule : LEDDriver

module ConvertDigit
    (input  logic [DIGIT_BITS-1:0] digit,
     output logic [NUM_ROWS-1:0] col0, col1, col2);

    always_comb begin
        case (digit)
            4'd0: begin
                col0 = 5'b11111;
                col1 = 5'b10001;
                col2 = 5'b11111;
            end
            4'd1: begin
                col0 = 5'b10001;
                col1 = 5'b11111;
                col2 = 5'b00001;
            end
            4'd2: begin
                col0 = 5'b10111;
                col1 = 5'b10101;
                col2 = 5'b11101;
            end
            4'd3: begin
                col0 = 5'b10101;
                col1 = 5'b10101;
                col2 = 5'b11111;
            end
            4'd4: begin
                col0 = 5'b11100;
                col1 = 5'b00100;
                col2 = 5'b11111;
            end
            4'd5: begin
                col0 = 5'b11101;
                col1 = 5'b10101;
                col2 = 5'b10111;
            end
            4'd6: begin
                col0 = 5'b11111;
                col1 = 5'b10101;
                col2 = 5'b10111;
            end
            4'd7: begin
                col0 = 5'b10000;
                col1 = 5'b10000;
                col2 = 5'b11111;
            end
            4'd8: begin
                col0 = 5'b11111;
                col1 = 5'b10101;
                col2 = 5'b11111;
            end
            4'd9: begin
                col0 = 5'b11101;
                col1 = 5'b10101;
                col2 = 5'b11111;
            end
            default: begin
                col0 = 5'b11111;
                col1 = 5'b11111;
                col2 = 5'b11111;
            end
        endcase
    end

endmodule

// For any button, can detect a press or a hold for >= 2 seconds
module DetectButtonHold
    (input  logic clock, reset,
     input  logic button,
     output logic button_pressed, button_held);

    ///////////////////////
    ///// DEFINITIONS /////
    ///////////////////////

    localparam BUTTON_2SEC = 2*CLOCK_RATE;
    localparam BUTTON_COUNT_SIZE = $clog2(BUTTON_2SEC);

    enum logic [1:0] {BUTTON_WAIT, BUTTON_PRESSED, BUTTON_RELEASE} button_state, button_next_state;

    logic button_latched, clear_buttonlatch, en_buttonlatch;
    logic en_buttoncount, reset_buttoncount, clear_buttoncount;
    logic [BUTTON_COUNT_SIZE-1:0] in_buttoncount, out_buttoncount;

    /////////////////
    ///// LOGIC /////
    /////////////////

    // Counter for detecting button being held — counts to 3 seconds
    assign reset_buttoncount = reset | clear_buttoncount;
    assign in_buttoncount = out_buttoncount + 'd1;

    Register #(.WIDTH(BUTTON_COUNT_SIZE), .RESET_VAL({BUTTON_COUNT_SIZE{1'b0}}))
        buttoncount (.clock, .reset(reset_buttoncount), .en(en_buttoncount), 
        .D(in_buttoncount), .Q(out_buttoncount));

    // Latch to prevent counter overflow if button held longer than 3 sec
    assign en_buttonlatch = (out_buttoncount >= BUTTON_2SEC);

    always_ff @(posedge clock) begin
        if (reset | clear_buttonlatch) button_latched <= 1'b0;
        else if (en_buttonlatch)       button_latched <= 1'b1;
    end

    /////////////////
    ///// STATE /////
    /////////////////

    always_ff @(posedge clock) begin
        if (reset) button_state <= BUTTON_WAIT;
        else       button_state <= button_next_state;
    end

    // Next state and output logic
    always_comb begin
        button_next_state = BUTTON_WAIT;
        button_pressed = 1'b0;
        button_held = 1'b0;
        clear_buttoncount = 1'b0;
        clear_buttonlatch = 1'b0;
        en_buttoncount = 1'b0;
        case (button_state)
            BUTTON_WAIT: begin
                clear_buttoncount = 1'b1;
                clear_buttonlatch = 1'b1;
                if (button) begin
                    button_next_state = BUTTON_PRESSED;
                end
                else begin
                    button_next_state = BUTTON_WAIT;
                end
            end
            BUTTON_PRESSED: begin
                en_buttoncount = 1'b1;
                if (button_latched) begin
                    button_next_state = BUTTON_RELEASE;
                    button_held = 1'b1;
                end
                else if (~button) begin
                    button_next_state = BUTTON_WAIT;
                    button_pressed = 1'b1;
                    clear_buttonlatch = 1'b1;
                end
                else begin
                    button_next_state = BUTTON_PRESSED;
                end 
            end
            BUTTON_RELEASE: begin
                clear_buttonlatch = 1'b1;
                if (~button) begin
                    button_next_state = BUTTON_WAIT;
                end
                else begin
                    button_next_state = BUTTON_RELEASE;
                end
            end
            default: begin
                button_next_state = BUTTON_WAIT;
            end
        endcase
    end

endmodule : DetectButtonHold

module Register
    #(parameter WIDTH = 8,
      parameter RESET_VAL = {WIDTH{1'b0}})
    (input  logic             clock, reset, en,
     input  logic [WIDTH-1:0] D,
     output logic [WIDTH-1:0] Q);

    always_ff @(posedge clock) begin
        if (reset) begin
            Q <= RESET_VAL;
        end
        else if (en) begin
            Q <= D;
        end
    end

endmodule : Register