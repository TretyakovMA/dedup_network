`timescale 1ns/1ps

module tdl_dict_unit_tb_top;

    localparam int DATA_WIDTH = 8;
    localparam int DICT_SIZE  = 5;
    localparam int KEY_WIDTH  = $clog2(DICT_SIZE);

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic flush_dict = 1'b0;
    logic [DATA_WIDTH-1:0] search_data = '0;
    logic add_en = 1'b0;
    logic use_custom_index = 1'b0;
    logic [KEY_WIDTH-1:0] wr_key = '0;
    logic [DATA_WIDTH-1:0] wr_data = '0;

    logic hit;
    logic [KEY_WIDTH-1:0] hit_key;
    logic dict_full;
    logic [KEY_WIDTH-1:0] next_free_key;
    logic [KEY_WIDTH:0] occupied_count;
    logic [DICT_SIZE-1:0] valid_bits;
    logic lookup_req_valid = 1'b0;
    logic lookup_rsp_ready = 1'b0;
    logic lookup_req_ready, lookup_rsp_valid, lookup_hit;
    logic [KEY_WIDTH-1:0] lookup_key;

    tdl_dict_unit #(
        .DATA_WIDTH(DATA_WIDTH),
        .DICT_SIZE (DICT_SIZE)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .flush_dict      (flush_dict),
        .search_data     (search_data),
        .hit             (hit),
        .hit_key         (hit_key),
        .add_en          (add_en),
        .use_custom_index(use_custom_index),
        .wr_key          (wr_key),
        .wr_data         (wr_data),
        .dict_full       (dict_full),
        .next_free_key   (next_free_key),
        .occupied_count  (occupied_count),
        .valid_bits      (valid_bits),
        .lookup_req_valid(lookup_req_valid),
        .lookup_req_ready(lookup_req_ready),
        .lookup_rsp_valid(lookup_rsp_valid),
        .lookup_rsp_ready(lookup_rsp_ready),
        .lookup_hit      (lookup_hit),
        .lookup_key      (lookup_key)
    );

    always #10 clk = ~clk;
    bit test_passed = 1'b0;

    task automatic tick();
        @(posedge clk);
        #1;
    endtask

    task automatic check_status(
        input string phase,
        input logic [DICT_SIZE-1:0] expected_valid,
        input int expected_next_free
    );
        int expected_count;
        expected_count = $countones(expected_valid);
        #1;
        if (valid_bits !== expected_valid)
            $fatal(1, "%s: valid_bits=%b, expected %b", phase, valid_bits, expected_valid);
        if (occupied_count !== (KEY_WIDTH+1)'(expected_count))
            $fatal(1, "%s: occupied_count=%0d, expected %0d",
                   phase, occupied_count, expected_count);
        if (dict_full !== (&expected_valid))
            $fatal(1, "%s: dict_full=%b, expected %b",
                   phase, dict_full, &expected_valid);
        if (next_free_key !== KEY_WIDTH'(expected_next_free))
            $fatal(1, "%s: next_free_key=%0d, expected %0d",
                   phase, next_free_key, expected_next_free);
    endtask

    task automatic check_search(
        input logic [DATA_WIDTH-1:0] data,
        input logic expected_hit,
        input logic [KEY_WIDTH-1:0] expected_key,
        input string phase
    );
        search_data = data;
        #1;
        if (hit !== expected_hit)
            $fatal(1, "%s: search %h hit=%b, expected %b",
                   phase, data, hit, expected_hit);
        if (expected_hit && hit_key !== expected_key)
            $fatal(1, "%s: search %h hit_key=%0d, expected %0d",
                   phase, data, hit_key, expected_key);
    endtask

    task automatic write_entry(
        input logic custom_index,
        input logic [KEY_WIDTH-1:0] index,
        input logic [DATA_WIDTH-1:0] data
    );
        @(negedge clk);
        use_custom_index = custom_index;
        wr_key = index;
        wr_data = data;
        add_en = 1'b1;
        tick();
        add_en = 1'b0;
    endtask

    task automatic check_lookup(
        input string phase,
        input logic expected_ready,
        input logic expected_valid,
        input logic expected_hit = 1'b0,
        input logic [KEY_WIDTH-1:0] expected_key = '0
    );
        if ({lookup_req_ready, lookup_rsp_valid} !== {expected_ready, expected_valid})
            $fatal(1, "%s: lookup ready/valid=%b/%b, expected %b/%b", phase,
                   lookup_req_ready, lookup_rsp_valid, expected_ready, expected_valid);
        if (expected_valid && {lookup_hit, lookup_key} !== {expected_hit, expected_key})
            $fatal(1, "%s: lookup hit/key=%b/%0d, expected %b/%0d", phase,
                   lookup_hit, lookup_key, expected_hit, expected_key);
    endtask

    task automatic test_lookup();
        @(negedge clk);
        search_data = 8'h22;
        lookup_req_valid = 1'b1;
        use_custom_index = 1'b1;
        wr_key = '0;
        wr_data = 8'h7a;
        add_en = 1'b1;
        #1;
        check_lookup("empty response slot", 1, 0);
        tick();
        add_en = 1'b0;
        check_lookup("lookup captured pre-write hit at key zero", 0, 1, 1, '0);
        if ({hit, hit_key} !== {1'b1, KEY_WIDTH'(1)})
            $fatal(1, "lookup replacement did not update the live search");

        @(negedge clk);
        // Keep the next request pending while the registered response is stalled.
        search_data = 8'h33;
        repeat (3) begin
            tick();
            check_lookup("response held despite different live lookup", 0, 1, 1, '0);
        end

        @(negedge clk);
        lookup_rsp_ready = 1'b1;
        #1;
        check_lookup("simultaneous response and request", 1, 1, 1, '0);
        tick();
        lookup_req_valid = 1'b0;
        check_lookup("new hit replaced the consumed response", 1, 1, 1, KEY_WIDTH'(3));
        tick();
        check_lookup("response consumed once", 1, 0);

        @(negedge clk);
        lookup_rsp_ready = 1'b0;
        search_data = 8'h7a;
        lookup_req_valid = 1'b1;
        tick();
        lookup_req_valid = 1'b0;
        check_lookup("lookup sees the replacement committed earlier", 0, 1, 1, '0);
    endtask

    initial begin
        #1;
        check_status("during reset", '0, 0);
        @(negedge clk);
        rst_n = 1'b1;
        check_status("after reset release", '0, 0);
        check_search(8'h11, 1'b0, '0, "empty dictionary");

        write_entry(1'b0, '0, 8'h11);
        check_status("first automatic write", 5'b00001, 1);
        check_search(8'h11, 1'b1, 2'd0, "automatic index zero");

        write_entry(1'b0, '0, 8'h22);
        check_status("second automatic write", 5'b00011, 2);
        check_search(8'h22, 1'b1, 2'd1, "automatic index one");
        check_search(8'h33, 1'b0, '0, "search miss");

        write_entry(1'b1, KEY_WIDTH'(3), 8'h33);
        check_status("custom-index write", 5'b01011, 2);
        check_search(8'h33, 1'b1, KEY_WIDTH'(3), "custom index three");

        write_entry(1'b1, '0, 8'h22);
        check_status("custom overwrite", 5'b01011, 2);
        check_search(8'h22, 1'b1, '0, "duplicate returns lowest index");

        write_entry(1'b0, '0, 8'h44);
        check_status("automatic write fills the hole", 5'b01111, 4);
        write_entry(1'b0, '0, 8'h45);
        check_status("dictionary full", '1, 0);
        check_search(8'h45, 1'b1, KEY_WIDTH'(4), "last automatic slot");

        write_entry(1'b0, '0, 8'h99);
        check_search(8'h22, 1'b1, '0, "automatic write cannot overwrite key zero when full");
        check_search(8'h99, 1'b0, '0, "blocked automatic write");
        write_entry(1'b1, KEY_WIDTH'(DICT_SIZE), 8'h98);
        check_status("invalid key leaves dictionary full", '1, 0);
        check_search(8'h98, 1'b0, '0, "invalid custom key");

        test_lookup();
        check_status("custom replacement preserves occupancy", '1, 0);

        @(negedge clk);
        flush_dict = 1'b1;
        lookup_req_valid = 1'b1;
        lookup_rsp_ready = 1'b1;
        add_en = 1'b1;
        use_custom_index = 1'b1;
        wr_key = KEY_WIDTH'(1);
        wr_data = 8'h55;
        #1;
        check_lookup("flush suppresses both handshakes", 0, 0);
        tick();
        add_en = 1'b0;
        lookup_req_valid = 1'b0;
        flush_dict = 1'b0;
        check_status("flush takes priority over write", '0, 0);
        check_lookup("flush dropped the pending response", 1, 0);
        check_search(8'h55, 1'b0, '0, "flushed write is invalid");
        check_search(8'h7a, 1'b0, '0, "old entry is invalid after flush");

        @(negedge clk);
        lookup_req_valid = 1'b1;
        tick();
        lookup_req_valid = 1'b0;
        check_lookup("registered miss after flush", 1, 1);
        tick();
        check_lookup("miss consumed", 1, 0);

        write_entry(1'b0, '0, 8'h66);
        check_status("automatic write after flush", 5'b00001, 1);
        check_search(8'h66, 1'b1, '0, "write after flush");

        @(negedge clk);
        lookup_rsp_ready = 1'b0;
        lookup_req_valid = 1'b1;
        tick();
        lookup_req_valid = 1'b0;
        check_lookup("hit queued before reset", 0, 1, 1, '0);

        @(negedge clk);
        rst_n = 1'b0;
        #1;
        check_status("asynchronous reset", '0, 0);
        check_lookup("reset drops pending response", 0, 0);
        check_search(8'h66, 1'b0, '0, "reset invalidates stored entry");
        @(negedge clk);
        rst_n = 1'b1;
        #1;
        check_lookup("empty lookup after reset release", 1, 0);

        test_passed = 1'b1;
        $display("All dictionary unit tests passed.");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "Dictionary unit test timed out.");
    end

endmodule
