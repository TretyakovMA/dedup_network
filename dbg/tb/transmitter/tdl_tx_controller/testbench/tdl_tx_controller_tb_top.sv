`timescale 1ns/1ns
`define GREEN_STR(str) ($sformatf("\033[32m%s\033[0m", str))
`define RED_STR(str) ($sformatf("\033[31;1m%s\033[0m", str))

module tdl_tx_controller_tb_top;

    localparam int CLK_PERIOD = 20;
    localparam int DICT_SIZE  = 3;
    localparam int KEY_WIDTH  = $clog2(DICT_SIZE);

    localparam logic [1:0] FRAME_RAW  = 2'b00;
    localparam logic [1:0] FRAME_KEY  = 2'b01;
    localparam logic [1:0] FRAME_SYNC = 2'b10;

    logic clk;
    logic rst_n;

    logic tx_en;
    logic bypass_en;
    logic [31:0] policy_cfg;
    logic backend_ready;
    logic busy;
    logic [2:0] state_code;

    logic fifo_empty;
    logic [31:0] fifo_rdata;
    logic fifo_rd_en;

    logic lookup_req_valid;
    logic [31:0] lookup_word;
    logic lookup_req_ready;
    logic lookup_rsp_valid;
    logic lookup_hit;
    logic [KEY_WIDTH-1:0] lookup_key;
    logic lookup_rsp_ready;

    logic policy_req_valid;
    logic [31:0] policy_word;
    logic policy_hit;
    logic [KEY_WIDTH-1:0] policy_hit_key;
    logic [31:0] policy_req_cfg;
    logic policy_req_ready;
    logic policy_rsp_valid;
    logic policy_admit;
    logic [KEY_WIDTH-1:0] policy_key;
    logic policy_bf_filtered;
    logic policy_rsp_ready;
    logic policy_commit;

    logic desc_valid;
    logic [1:0] desc_type;
    logic [7:0] desc_key;
    logic [31:0] desc_data;
    logic desc_ready;

    logic dict_wr_en;
    logic [KEY_WIDTH-1:0] dict_wr_key;
    logic [31:0] dict_wr_data;
    logic word_committed;
    logic bf_filtered_event;

    int error_count = 0;
    int pop_count = 0;
    int commit_count = 0;
    int dict_write_count = 0;
    int policy_commit_count = 0;
    int bf_filtered_count = 0;
    logic active_bypass_q;
    logic expected_bf_filtered_q;
    logic desc_stalled_q;
    logic [1:0] held_desc_type_q;
    logic [7:0] held_desc_key_q;
    logic [31:0] held_desc_data_q;

    tdl_tx_controller #(
        .DATA_WIDTH(32),
        .DICT_SIZE (DICT_SIZE)
    ) dut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .tx_en                (tx_en),
        .bypass_en            (bypass_en),
        .policy_cfg           (policy_cfg),
        .backend_ready        (backend_ready),
        .busy                 (busy),
        .state_code           (state_code),
        .fifo_empty           (fifo_empty),
        .fifo_rdata           (fifo_rdata),
        .fifo_rd_en           (fifo_rd_en),
        .lookup_req_valid     (lookup_req_valid),
        .lookup_word          (lookup_word),
        .lookup_req_ready     (lookup_req_ready),
        .lookup_rsp_valid     (lookup_rsp_valid),
        .lookup_hit           (lookup_hit),
        .lookup_key           (lookup_key),
        .lookup_rsp_ready     (lookup_rsp_ready),
        .policy_req_valid     (policy_req_valid),
        .policy_word          (policy_word),
        .policy_hit           (policy_hit),
        .policy_hit_key       (policy_hit_key),
        .policy_req_cfg       (policy_req_cfg),
        .policy_req_ready     (policy_req_ready),
        .policy_rsp_valid     (policy_rsp_valid),
        .policy_admit         (policy_admit),
        .policy_key           (policy_key),
        .policy_bf_filtered   (policy_bf_filtered),
        .policy_rsp_ready     (policy_rsp_ready),
        .policy_commit        (policy_commit),
        .desc_valid           (desc_valid),
        .desc_type            (desc_type),
        .desc_key             (desc_key),
        .desc_data            (desc_data),
        .desc_ready           (desc_ready),
        .dict_wr_en           (dict_wr_en),
        .dict_wr_key          (dict_wr_key),
        .dict_wr_data         (dict_wr_data),
        .word_committed       (word_committed),
        .bf_filtered_event    (bf_filtered_event)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    task automatic check_condition(input logic condition, input string message);
        if (condition !== 1'b1) begin
            $error("Time %0t: %s", $time, message);
            error_count = error_count + 1;
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            pop_count                 = 0;
            commit_count              = 0;
            dict_write_count          = 0;
            policy_commit_count       = 0;
            bf_filtered_count         = 0;
            active_bypass_q           = 1'b0;
            expected_bf_filtered_q    = 1'b0;
            desc_stalled_q            = 1'b0;
        end
        else begin
            if (desc_stalled_q) begin
                check_condition(desc_valid, "stalled descriptor valid was withdrawn");
                check_condition(desc_type === held_desc_type_q,
                                "descriptor type changed while stalled");
                check_condition(desc_key === held_desc_key_q,
                                "descriptor key changed while stalled");
                check_condition(desc_data === held_desc_data_q,
                                "descriptor data changed while stalled");
            end

            desc_stalled_q = desc_valid && !desc_ready;
            if (desc_stalled_q) begin
                held_desc_type_q = desc_type;
                held_desc_key_q  = desc_key;
                held_desc_data_q = desc_data;
            end

            if (fifo_rd_en) begin
                pop_count = pop_count + 1;
                active_bypass_q = bypass_en;
                expected_bf_filtered_q = 1'b0;
            end
            if (lookup_rsp_valid && lookup_rsp_ready)
                expected_bf_filtered_q = 1'b0;
            if (policy_rsp_valid && policy_rsp_ready)
                expected_bf_filtered_q = policy_bf_filtered;

            if (word_committed) commit_count = commit_count + 1;
            if (dict_wr_en) dict_write_count = dict_write_count + 1;
            if (policy_commit) policy_commit_count = policy_commit_count + 1;
            if (bf_filtered_event) bf_filtered_count = bf_filtered_count + 1;

            check_condition(!(fifo_rd_en && word_committed),
                            "word pop and descriptor commit occurred together");
            check_condition(word_committed === (desc_valid && desc_ready),
                            "word_committed did not match descriptor handshake");
            check_condition(dict_wr_en ===
                            (word_committed && (desc_type == FRAME_SYNC)),
                            "dictionary write did not match SYNC commit");
            check_condition(policy_commit ===
                            (word_committed && !active_bypass_q),
                            "policy commit did not match a non-bypass commit");
            check_condition(bf_filtered_event ===
                            (word_committed && !active_bypass_q &&
                             expected_bf_filtered_q),
                            "BF-filtered event did not match committed policy result");
            check_condition((pop_count >= commit_count) &&
                            ((pop_count - commit_count) <= 1),
                            "pop/commit outstanding-word invariant failed");
            check_condition(dict_write_count <= commit_count,
                            "dictionary write count exceeded commit count");
        end
    end

    task automatic initialize;
        rst_n = 1'b0;
        tx_en = 1'b0;
        bypass_en = 1'b0;
        policy_cfg = '0;
        backend_ready = 1'b0;
        fifo_empty = 1'b1;
        fifo_rdata = '0;
        lookup_req_ready = 1'b0;
        lookup_rsp_valid = 1'b0;
        lookup_hit = 1'b0;
        lookup_key = '0;
        policy_req_ready = 1'b0;
        policy_rsp_valid = 1'b0;
        policy_admit = 1'b0;
        policy_key = '0;
        policy_bf_filtered = 1'b0;
        desc_ready = 1'b0;

        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);
    endtask

    task automatic accept_word(
        input logic [31:0] payload,
        input logic        bypass,
        input logic [31:0] cfg,
        input logic        backend_available
    );
        @(negedge clk);
        fifo_empty    = 1'b0;
        fifo_rdata    = payload;
        tx_en         = 1'b1;
        bypass_en     = bypass;
        policy_cfg    = cfg;
        backend_ready = backend_available;
        #1;
        check_condition(fifo_rd_en, "eligible FIFO word was not popped");
        @(posedge clk);
        #1;
        check_condition(busy, "controller did not retain the accepted word");
        check_condition(!fifo_rd_en, "FIFO pop remained asserted after acceptance");

        // Model FWFT advancement and change live inputs after the captured word.
        fifo_empty    = 1'b1;
        fifo_rdata    = ~payload;
        policy_cfg    = cfg ^ 32'hFFFF_00FF;
        tx_en         = 1'b0;
        bypass_en     = !bypass;
        backend_ready = 1'b0;
    endtask

    task automatic stall_and_check_descriptor(
        input logic [1:0] expected_type,
        input logic [7:0] expected_key,
        input logic [31:0] expected_data
    );
        wait (desc_valid === 1'b1);
        #1;
        check_condition(desc_type === expected_type, "unexpected descriptor type");
        check_condition(desc_key === expected_key, "unexpected descriptor key");
        check_condition(desc_data === expected_data, "unexpected descriptor data");
        check_condition(state_code == 3'd5, "controller was not in OUTPUT");

        repeat (3) begin
            @(posedge clk);
            #1;
            check_condition(desc_valid, "descriptor valid dropped before ready");
            check_condition(desc_type === expected_type,
                            "descriptor type was not held during stall");
            check_condition(desc_key === expected_key,
                            "descriptor key was not held during stall");
            check_condition(desc_data === expected_data,
                            "descriptor data was not held during stall");
            check_condition(!word_committed && !dict_wr_en && !policy_commit,
                            "state update occurred before descriptor acceptance");
            check_condition(!fifo_rd_en, "controller popped another word while busy");
        end
    endtask

    task automatic commit_descriptor(
        input logic        expect_policy_commit,
        input logic        expect_dict_write,
        input logic [7:0]  expect_write_key,
        input logic [31:0] expect_write_data,
        input logic        expect_bf_event
    );
        @(negedge clk);
        desc_ready = 1'b1;
        #1;
        check_condition(desc_valid, "descriptor was not valid at commit");
        check_condition(word_committed, "word_committed missing on descriptor handshake");
        check_condition(policy_commit === expect_policy_commit,
                        "unexpected policy_commit on descriptor handshake");
        check_condition(dict_wr_en === expect_dict_write,
                        "unexpected dictionary write on descriptor handshake");
        check_condition(bf_filtered_event === expect_bf_event,
                        "unexpected BF-filtered event on descriptor handshake");
        if (expect_dict_write) begin
            check_condition(dict_wr_key === expect_write_key[KEY_WIDTH-1:0],
                            "dictionary write key did not match SYNC descriptor");
            check_condition(dict_wr_data === expect_write_data,
                            "dictionary write data did not match SYNC descriptor");
        end

        @(posedge clk);
        #1;
        desc_ready = 1'b0;
        check_condition(!desc_valid && !word_committed,
                        "descriptor handshake was not a single-cycle commit");
        check_condition(!dict_wr_en && !policy_commit && !bf_filtered_event,
                        "commit side effects repeated after the handshake");
        check_condition(!busy, "controller did not return to IDLE after commit");
    endtask

    task automatic complete_lookup_request(input logic [31:0] expected_word);
        wait (lookup_req_valid === 1'b1);
        @(negedge clk);
        check_condition(state_code == 3'd1, "controller was not in LOOKUP_REQ");
        check_condition(lookup_word === expected_word, "lookup used the wrong word");
        lookup_req_ready = 1'b0;

        repeat (2) begin
            @(posedge clk);
            #1;
            check_condition(lookup_req_valid, "lookup request valid dropped while stalled");
            check_condition(lookup_word === expected_word,
                            "lookup payload changed while stalled");
        end

        @(negedge clk);
        lookup_req_ready = 1'b1;
        @(posedge clk);
        #1;
        lookup_req_ready = 1'b0;
    endtask

    task automatic send_lookup_response(
        input logic hit,
        input logic [KEY_WIDTH-1:0] key
    );
        wait (lookup_rsp_ready === 1'b1);
        repeat (2) @(posedge clk);
        @(negedge clk);
        lookup_hit = hit;
        lookup_key = key;
        lookup_rsp_valid = 1'b1;
        @(posedge clk);
        #1;
        lookup_rsp_valid = 1'b0;
    endtask

    task automatic complete_policy_request(
        input logic [31:0] expected_word,
        input logic        expected_hit,
        input logic [KEY_WIDTH-1:0] expected_hit_key,
        input logic [31:0] expected_cfg
    );
        wait (policy_req_valid === 1'b1);
        @(negedge clk);
        check_condition(state_code == 3'd3, "controller was not in POLICY_REQ");
        check_condition(policy_word === expected_word, "policy used the wrong word");
        check_condition(policy_hit === expected_hit, "policy received the wrong hit flag");
        check_condition(policy_hit_key === expected_hit_key,
                        "policy received the wrong hit key");
        check_condition(policy_req_cfg === expected_cfg,
                        "policy configuration was not snapshotted at FIFO pop");
        policy_req_ready = 1'b0;

        repeat (2) begin
            @(posedge clk);
            #1;
            check_condition(policy_req_valid, "policy request valid dropped while stalled");
            check_condition(policy_word === expected_word,
                            "policy request word changed while stalled");
            check_condition(policy_req_cfg === expected_cfg,
                            "policy request configuration changed while stalled");
        end

        @(negedge clk);
        policy_req_ready = 1'b1;
        @(posedge clk);
        #1;
        policy_req_ready = 1'b0;
    endtask

    task automatic send_policy_response(
        input logic admit,
        input logic [KEY_WIDTH-1:0] key,
        input logic bf_filtered
    );
        wait (policy_rsp_ready === 1'b1);
        repeat (2) @(posedge clk);
        @(negedge clk);
        policy_admit = admit;
        policy_key = key;
        policy_bf_filtered = bf_filtered;
        policy_rsp_valid = 1'b1;
        @(posedge clk);
        #1;
        policy_rsp_valid = 1'b0;
    endtask

    initial begin
        initialize();

        check_condition(!fifo_rd_en, "empty FIFO caused a pop");

        @(negedge clk);
        fifo_empty = 1'b0;
        fifo_rdata = 32'hDEAD_BEEF;
        tx_en = 1'b0;
        backend_ready = 1'b1;
        #1;
        check_condition(!fifo_rd_en, "TX_EN=0 did not block FIFO pop");
        repeat (2) begin
            @(posedge clk);
            #1;
            check_condition(!fifo_rd_en, "FIFO popped while TX_EN was disabled");
        end

        @(negedge clk);
        tx_en = 1'b1;
        backend_ready = 1'b0;
        #1;
        check_condition(!fifo_rd_en, "busy backend did not block ordinary FIFO pop");
        repeat (2) begin
            @(posedge clk);
            #1;
            check_condition(!fifo_rd_en, "ordinary FIFO pop ignored backend_ready");
        end

        accept_word(32'h1234_5678, 1'b1, 32'h0102_0304, 1'b0);
        check_condition(!lookup_req_valid && !policy_req_valid,
                        "bypass unexpectedly requested lookup or policy");
        stall_and_check_descriptor(FRAME_RAW, 8'h00, 32'h1234_5678);
        commit_descriptor(1'b0, 1'b0, 8'h00, 32'h1234_5678, 1'b0);

        accept_word(32'hA5C3_0F81, 1'b0, 32'h1122_3344, 1'b1);
        complete_lookup_request(32'hA5C3_0F81);
        send_lookup_response(1'b1, KEY_WIDTH'(2));
        complete_policy_request(
            32'hA5C3_0F81, 1'b1, KEY_WIDTH'(2), 32'h1122_3344
        );
        send_policy_response(1'b0, KEY_WIDTH'(0), 1'b0);
        stall_and_check_descriptor(FRAME_KEY, 8'h02, 32'hA5C3_0F81);
        commit_descriptor(1'b1, 1'b0, 8'h00, 32'hA5C3_0F81, 1'b0);

        accept_word(32'hCAFE_0123, 1'b0, 32'h5566_7788, 1'b1);
        complete_lookup_request(32'hCAFE_0123);
        send_lookup_response(1'b0, KEY_WIDTH'(0));
        complete_policy_request(
            32'hCAFE_0123, 1'b0, KEY_WIDTH'(0), 32'h5566_7788
        );
        send_policy_response(1'b1, KEY_WIDTH'(1), 1'b0);
        stall_and_check_descriptor(FRAME_SYNC, 8'h01, 32'hCAFE_0123);
        commit_descriptor(1'b1, 1'b1, 8'h01, 32'hCAFE_0123, 1'b0);

        accept_word(32'h0BAD_F00D, 1'b0, 32'hAABB_CCDD, 1'b1);
        complete_lookup_request(32'h0BAD_F00D);
        send_lookup_response(1'b0, KEY_WIDTH'(0));
        complete_policy_request(
            32'h0BAD_F00D, 1'b0, KEY_WIDTH'(0), 32'hAABB_CCDD
        );
        send_policy_response(1'b0, KEY_WIDTH'(0), 1'b1);
        stall_and_check_descriptor(FRAME_RAW, 8'h00, 32'h0BAD_F00D);
        commit_descriptor(1'b1, 1'b0, 8'h00, 32'h0BAD_F00D, 1'b1);

        check_condition(pop_count == 4, "expected exactly four FIFO pops");
        check_condition(commit_count == 4, "expected exactly four descriptor commits");
        check_condition(dict_write_count == 1, "expected exactly one SYNC dictionary write");
        check_condition(policy_commit_count == 3,
                        "expected policy commit for each non-bypass word");
        check_condition(bf_filtered_count == 1,
                        "expected exactly one BF-filtered event");
        check_condition(!busy && !fifo_rd_en, "controller was not idle at test end");

        if (error_count == 0) begin
            $display(`GREEN_STR("All controller descriptor tests passed."));
            $finish;
        end
        else begin
            $fatal(1, `RED_STR($sformatf("Controller test completed with %0d errors.", error_count)));
        end
    end

    initial begin
        #100000;
        $fatal(1, "Simulation timeout.");
    end

endmodule
