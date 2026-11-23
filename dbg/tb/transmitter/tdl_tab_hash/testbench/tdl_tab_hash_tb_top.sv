`timescale 1ns/1ps

module tdl_tab_hash_tb_top;
    logic clk;
    logic rst_n;
    logic in_valid;
    logic in_ready;
    logic [31:0] data_in;
    logic out_valid;
    logic out_ready;
    logic [11:0] h_bf1;
    logic [11:0] h_bf2;
    logic [7:0] h_cms1;
    logic [7:0] h_cms2;

    tdl_tab_hash dut (.*);

    // Fixed sample sizes keep every full-address histogram well populated.
    localparam int RANDOM_SAMPLES = 262144;
    localparam int SWEEP_SAMPLES = 65536;
    localparam int MAX_BINS = 4096;
    localparam int PAIR_COUNT = 6;
    localparam real SIGMA_LIMIT = 8.0;

    int unsigned histogram[4][MAX_BINS];
    int unsigned pair_histogram[PAIR_COUNT][MAX_BINS];
    int unsigned bit_ones[4][12];
    int unsigned observed_samples;
    int quality_failures = 0;
    bit test_passed = 1'b0;
    logic [31:0] quality_seed = 32'h1357_9BDF;

    typedef enum int { RANDOM_WORDS, LOW_COUNTER, MID_COUNTER, HIGH_COUNTER,
                       FIXED_PREFIX, FIXED_SUFFIX, MIRRORED_HALVES } dataset_t;

    function automatic logic [31:0] next_random(input logic [31:0] state);
        logic [31:0] value;
        value = state ^ (state << 13);
        value = value ^ (value >> 17);
        return value ^ (value << 5);
    endfunction

    function automatic string hash_name(input int index);
        case (index)
            0: return "BF1";
            1: return "BF2";
            2: return "CMS1";
            3: return "CMS2";
            default: $fatal(1, "Invalid hash index");
        endcase
    endfunction

    task automatic clear_statistics;
        foreach (histogram[h, b]) histogram[h][b] = 0;
        foreach (pair_histogram[p, b]) pair_histogram[p][b] = 0;
        foreach (bit_ones[h, b]) bit_ones[h][b] = 0;
        observed_samples = 0;
    endtask

    // Called on the accepting edge, before the DUT registers its next result.
    task automatic record_output;
        int unsigned values[4];
        int pair_index;
        int bin_index;
        if ($isunknown({h_bf1, h_bf2, h_cms1, h_cms2}))
            $fatal(1, "Unknown hash at output handshake");
        values[0] = int'(h_bf1);
        values[1] = int'(h_bf2);
        values[2] = int'(h_cms1);
        values[3] = int'(h_cms2);
        foreach (values[h]) begin
            histogram[h][values[h]]++;
            for (int bit_index = 0; bit_index < (h < 2 ? 12 : 8); bit_index++)
                bit_ones[h][bit_index] += (values[h] >> bit_index) & 1;
        end
        pair_index = 0;
        for (int first = 0; first < 4; first++) begin
            for (int second = first + 1; second < 4; second++) begin
                // 64 x 64 joint bins, at least 16 observations expected per bin.
                bin_index = ((values[first] & 63) << 6) | (values[second] & 63);
                pair_histogram[pair_index][bin_index]++;
                pair_index++;
            end
        end
        observed_samples++;
    endtask

    task automatic check_histogram(
        input string label,
        input int unsigned counts[MAX_BINS],
        input int bin_count,
        input int sample_count
    );
        real expected_count;
        real chi_square;
        real chi_limit;
        real delta;
        real max_deviation;
        real bin_limit;
        int unsigned total;
        int unsigned min_count;
        int unsigned max_count;
        int empty_bins;
        expected_count = real'(sample_count) / real'(bin_count);
        chi_limit = real'(bin_count - 1) + SIGMA_LIMIT * $sqrt(2.0 * (bin_count - 1));
        bin_limit = SIGMA_LIMIT * $sqrt(expected_count * (1.0 - 1.0 / bin_count));
        chi_square = 0.0;
        max_deviation = 0.0;
        total = 0;
        min_count = sample_count;
        max_count = 0;
        empty_bins = 0;
        for (int bin_index = 0; bin_index < bin_count; bin_index++) begin
            total += counts[bin_index];
            if (counts[bin_index] < min_count) min_count = counts[bin_index];
            if (counts[bin_index] > max_count) max_count = counts[bin_index];
            if (counts[bin_index] == 0) empty_bins++;
            delta = real'(counts[bin_index]) - expected_count;
            chi_square += delta * delta / expected_count;
            if (delta < 0.0) delta = -delta;
            if (delta > max_deviation) max_deviation = delta;
        end
        if (total != sample_count)
            $fatal(1, "%s histogram total=%0d expected=%0d", label, total, sample_count);
        $display("QUALITY %s N=%0d bins=%0d mean=%0.2f min=%0d max=%0d empty=%0d chi2=%0.2f limit=%0.2f max_delta=%0.2f limit=%0.2f",
                 label, sample_count, bin_count, expected_count, min_count, max_count,
                 empty_bins, chi_square, chi_limit, max_deviation, bin_limit);
        if (chi_square > chi_limit || max_deviation > bin_limit) begin
            quality_failures++;
            $display("QUALITY_FAIL %s nonuniform histogram", label);
        end
    endtask

    task automatic check_statistics(input string dataset_name, input int sample_count);
        real bit_limit;
        real delta;
        real max_bit_deviation;
        int pair_index;
        if (observed_samples != sample_count)
            $fatal(1, "%s received=%0d expected=%0d", dataset_name, observed_samples, sample_count);
        bit_limit = SIGMA_LIMIT * $sqrt(real'(sample_count) * 0.25);
        for (int h = 0; h < 4; h++) begin
            check_histogram({dataset_name, "/", hash_name(h)}, histogram[h],
                            h < 2 ? 4096 : 256, sample_count);
            max_bit_deviation = 0.0;
            for (int b = 0; b < (h < 2 ? 12 : 8); b++) begin
                delta = real'(bit_ones[h][b]) - real'(sample_count) / 2.0;
                if (delta < 0.0) delta = -delta;
                if (delta > max_bit_deviation) max_bit_deviation = delta;
                if (delta > bit_limit) begin
                    quality_failures++;
                    $display("QUALITY_FAIL %s/%s bit=%0d ones=%0d limit=%0.2f",
                             dataset_name, hash_name(h), b, bit_ones[h][b], bit_limit);
                end
            end
            $display("QUALITY_BITS %s/%s max_delta=%0.2f limit=%0.2f",
                     dataset_name, hash_name(h), max_bit_deviation, bit_limit);
        end
        pair_index = 0;
        for (int first = 0; first < 4; first++) begin
            for (int second = first + 1; second < 4; second++) begin
                check_histogram({dataset_name, "/", hash_name(first), "_", hash_name(second), "_low6"},
                                pair_histogram[pair_index], 4096, sample_count);
                pair_index++;
            end
        end
    endtask

    task automatic run_dataset(input dataset_t kind, input string label, input int sample_count);
        logic [31:0] random_state;
        clear_statistics();
        random_state = quality_seed;
        $display("DATASET %s N=%0d seed=%08h", label, sample_count, quality_seed);
        // One final bubble drains the output register. Count only handshakes.
        for (int sample_index = 0; sample_index <= sample_count; sample_index++) begin
            @(negedge clk);
            out_ready = 1'b1;
            in_valid = (sample_index < sample_count);
            case (kind)
                RANDOM_WORDS: begin
                    random_state = next_random(random_state);
                    data_in = random_state;
                end
                LOW_COUNTER: data_in = 32'(sample_index);
                MID_COUNTER: data_in = 32'(sample_index) << 7;
                HIGH_COUNTER: data_in = 32'(sample_index) << 14;
                FIXED_PREFIX: data_in = {16'hA55A, 16'(sample_index)};
                FIXED_SUFFIX: data_in = {16'(sample_index), 16'h5AA5};
                MIRRORED_HALVES: data_in = {16'(sample_index), 16'(sample_index)};
                default: $fatal(1, "Unknown dataset");
            endcase
            @(posedge clk);
            if (in_ready !== 1'b1) $fatal(1, "Unexpected input stall in throughput test");
            if (out_valid === 1'b1 && out_ready) record_output();
            else if (sample_index != 0) $fatal(1, "Missing result in continuous stream");
            #1;
        end
        if (out_valid !== 1'b0) $fatal(1, "Output did not drain at dataset boundary");
        check_statistics(label, sample_count);
    endtask

    initial begin
        #20000000;
        $fatal(1, "tdl_tab_hash test timed out");
    end

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check_hashes(
        input logic [11:0] expected_bf1,
        input logic [11:0] expected_bf2,
        input logic [7:0] expected_cms1,
        input logic [7:0] expected_cms2
    );
        if ({h_bf1, h_bf2, h_cms1, h_cms2} !==
            {expected_bf1, expected_bf2, expected_cms1, expected_cms2}) begin
            $fatal(1, "Unexpected hashes: %h %h %h %h",
                   h_bf1, h_bf2, h_cms1, h_cms2);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        in_valid = 1'b0;
        data_in = '0;
        out_ready = 1'b0;

        repeat (2) @(posedge clk);
        #1;
        if (out_valid !== 1'b0 || in_ready !== 1'b0)
            $fatal(1, "Reset did not clear valid or gate ready");

        @(negedge clk);
        rst_n = 1'b1;
        #1;
        if (in_ready !== 1'b1)
            $fatal(1, "Idle hash module was not ready");

        in_valid = 1'b1;
        data_in = 32'h1234_5678;
        @(posedge clk);
        #1;
        if (out_valid !== 1'b1)
            $fatal(1, "Hash result was not registered");
        check_hashes(12'h164, 12'h693, 8'h8B, 8'h71);

        @(negedge clk);
        in_valid = 1'b0;
        data_in = 32'hFFFF_FFFF;
        #1;
        if (in_ready !== 1'b0)
            $fatal(1, "Ready was not deasserted while output was stalled");
        @(posedge clk);
        #1;
        if (out_valid !== 1'b1)
            $fatal(1, "Output valid was lost during stall");
        check_hashes(12'h164, 12'h693, 8'h8B, 8'h71);

        @(negedge clk);
        out_ready = 1'b1;
        in_valid = 1'b1;
        data_in = 32'h0000_0000;
        #1;
        if (in_ready !== 1'b1)
            $fatal(1, "Ready was not asserted for simultaneous transfer");
        @(posedge clk);
        #1;
        if (out_valid !== 1'b1)
            $fatal(1, "Back-to-back transfer introduced a bubble");
        check_hashes(12'hDE8, 12'h36E, 8'hA0, 8'hAF);

        @(negedge clk);
        in_valid = 1'b0;
        @(posedge clk);
        #1;
        if (out_valid !== 1'b0)
            $fatal(1, "Output valid was not cleared after transfer");

        if ($value$plusargs("HASH_SEED=%h", quality_seed)) begin
            if (quality_seed == 0) $fatal(1, "HASH_SEED must be nonzero for xorshift32");
        end
        $display("HASH_TABLES version=%0d seed=%08h", tdl_tab_hash_pkg::TABLE_VERSION,
                 tdl_tab_hash_pkg::TABLE_SEED);
        run_dataset(RANDOM_WORDS, "random32", RANDOM_SAMPLES);
        run_dataset(LOW_COUNTER, "counter_low18", RANDOM_SAMPLES);
        run_dataset(MID_COUNTER, "counter_shift7", RANDOM_SAMPLES);
        run_dataset(HIGH_COUNTER, "counter_high18", RANDOM_SAMPLES);
        run_dataset(FIXED_PREFIX, "fixed_upper16", SWEEP_SAMPLES);
        run_dataset(FIXED_SUFFIX, "fixed_lower16", SWEEP_SAMPLES);
        run_dataset(MIRRORED_HALVES, "mirrored_halves", SWEEP_SAMPLES);
        if (quality_failures != 0)
            $fatal(1, "HASH QUALITY FAILED: %0d checks", quality_failures);
        test_passed = 1'b1;
        $display("PASS: tdl_tab_hash handshake, golden vectors and hash quality (1245184 words)");
        $finish;
    end
endmodule
