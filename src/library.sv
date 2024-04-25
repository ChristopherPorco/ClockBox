/**
 * File: library.sv
 * Authors: Christopher Porco
 *
 * Summary: Library modules for ClockBox
 *
 * Design Guidelines:
 * - Use "TODO" and no other variation for identifying things to do, possible bugs, etc.
 * - Use "_L" for active low signals
 * - Use UpperCamelCase for modules
 * - Use snake_case for variables
 * - Use ALL_CAPS for parameters and enums
 */

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