`ifndef TDL_SDR_TIMING
`define TDL_SDR_TIMING
// Делитель SDR с разрешениями подъёма и спада и завершением начатой высокой фазы.
module tdl_sdr_timing (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        timing_active,
    input  logic [15:0] timing_div,
    input  logic        allow_rise,
    output logic        sdr_clk,
    output logic        rise_ce,
    output logic        fall_ce
);

    logic        sdr_clk_q;
    // Отсчёт от 0 до timing_div включительно задаёт полупериод D+1 тактов.
    logic [15:0] phase_count;

    assign sdr_clk = sdr_clk_q;

    // These are enables for transitions on the current clk edge.
    assign rise_ce = rst_n && !sdr_clk_q && timing_active && allow_rise &&
                     (phase_count == timing_div);
    // Начатая высокая фаза завершается даже при снятии allow_rise.
    assign fall_ce = rst_n && sdr_clk_q &&
                     (phase_count == timing_div);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sdr_clk_q  <= 1'b0;
            phase_count <= 16'd0;
        end
        else if (sdr_clk_q) begin
            if (fall_ce) begin
                sdr_clk_q  <= 1'b0;
                phase_count <= 16'd0;
            end
            else begin
                phase_count <= phase_count + 16'd1;
            end
        end
        // После паузы низкая фаза отсчитывается заново, без укороченного полупериода.
        else if (!timing_active || !allow_rise) begin
            phase_count <= 16'd0;
        end
        else if (rise_ce) begin
            sdr_clk_q  <= 1'b1;
            phase_count <= 16'd0;
        end
        else begin
            phase_count <= phase_count + 16'd1;
        end
    end

endmodule
`endif
