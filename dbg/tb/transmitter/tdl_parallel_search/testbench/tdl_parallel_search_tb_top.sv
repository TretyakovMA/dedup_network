// ============================================================================
// Testbench for tdl_parallel_search module
// ============================================================================

`timescale 1ns/1ps

module tdl_parallel_search_tb_top;

    // ========================================================================
    // Parameter definitions
    // ========================================================================
    localparam int DATA_WIDTH = 32;
    localparam int DICT_SIZE  = 8;
    localparam int KEY_WIDTH  = $clog2(DICT_SIZE);

    // ========================================================================
    // DUT signals
    // ========================================================================
    logic [DATA_WIDTH-1:0]                search_word;
    logic [DICT_SIZE-1:0][DATA_WIDTH-1:0] dict_words;
    logic [DICT_SIZE-1:0]                 valid_bits;
    logic                                 hit;
    logic [KEY_WIDTH-1:0]                 hit_index;

    // ========================================================================
    // Test signals
    // ========================================================================
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;

    // ========================================================================
    // DUT instantiation
    // ========================================================================
    tdl_parallel_search #(
        .DATA_WIDTH(DATA_WIDTH),
        .DICT_SIZE(DICT_SIZE)
    ) dut (
        .search_word(search_word),
        .dict_words(dict_words),
        .valid_bits(valid_bits),
        .hit(hit),
        .hit_index(hit_index)
    );

    // ========================================================================
    // Helper tasks
    // ========================================================================

    task automatic check_result(
        input string test_name,
        input logic exp_hit,
        input logic [KEY_WIDTH-1:0] exp_index
    );
        test_count++;
        if (hit == exp_hit && (exp_hit == 0 || hit_index == exp_index)) begin
            $display("[PASS] Test %0d: %s | hit=%0b, index=%0d", 
                     test_count, test_name, hit, hit_index);
            pass_count++;
        end else begin
            $display("[FAIL] Test %0d: %s | Expected: hit=%0b, index=%0d | Got: hit=%0b, index=%0d",
                     test_count, test_name, exp_hit, exp_index, hit, hit_index);
            fail_count++;
        end
    endtask

    task automatic setup_dict(
        input logic [DICT_SIZE-1:0][DATA_WIDTH-1:0] words,
        input logic [DICT_SIZE-1:0] valid
    );
        dict_words = words;
        valid_bits = valid;
        #1; // Allow combinational logic to settle
    endtask

    task automatic search(
        input logic [DATA_WIDTH-1:0] word
    );
        search_word = word;
        #1; // Allow combinational logic to settle
    endtask

    // ========================================================================
    // Test procedures
    // ========================================================================

    initial begin
        $display("\n");
        $display("========================================");
        $display("  TDL_PARALLEL_SEARCH TESTBENCH");
        $display("  DATA_WIDTH=%0d, DICT_SIZE=%0d", DATA_WIDTH, DICT_SIZE);
        $display("========================================\n");

        // Initialize signals
        search_word = 0;
        dict_words = '{default: 0};
        valid_bits = 0;

        // ====================================================================
        // Test 1: Empty dictionary (all valid_bits=0)
        // ====================================================================
        $display("\n--- Test Group 1: Empty Dictionary ---");
        setup_dict('{default: 32'hDEADBEEF}, 8'h00);
        search(32'h12345678);
        check_result("Empty dict - no hit expected", 1'b0, '0);

        // ====================================================================
        // Test 2: Single entry, valid, match found
        // ====================================================================
        $display("\n--- Test Group 2: Single Entry ---");
        begin
            logic [DICT_SIZE-1:0][DATA_WIDTH-1:0] dict;
            dict = '{default: 0};
            dict[0] = 32'hAAAAAAAA;
            setup_dict(dict, 8'h01); // Only dict[0] is valid
            search(32'hAAAAAAAA);
            check_result("Single entry - hit at index 0", 1'b1, 3'd0);
        end

        // Single entry, valid, no match
        begin
            logic [DICT_SIZE-1:0][DATA_WIDTH-1:0] dict;
            dict = '{default: 0};
            dict[0] = 32'hAAAAAAAA;
            setup_dict(dict, 8'h01);
            search(32'hBBBBBBBB);
            check_result("Single entry - no hit", 1'b0, '0);
        end

        // ====================================================================
        // Test 3: Multiple entries, single match
        // ====================================================================
        $display("\n--- Test Group 3: Multiple Entries, Single Match ---");
        begin
            logic [DICT_SIZE-1:0][DATA_WIDTH-1:0] dict;
            dict[0] = 32'h11111111;
            dict[1] = 32'h22222222;
            dict[2] = 32'h33333333;
            dict[3] = 32'h44444444;
            dict[4] = 32'h55555555;
            dict[5] = 32'h66666666;
            dict[6] = 32'h77777777;
            dict[7] = 32'h88888888;
            setup_dict(dict, 8'hFF); // All entries valid
            
            search(32'h22222222);
            check_result("Match at index 1", 1'b1, 3'd1);
            
            search(32'h77777777);
            check_result("Match at index 6", 1'b1, 3'd6);
            
            search(32'h88888888);
            check_result("Match at index 7", 1'b1, 3'd7);
        end

        // ====================================================================
        // Test 4: Multiple entries, no match
        // ====================================================================
        $display("\n--- Test Group 4: Multiple Entries, No Match ---");
        begin
            logic [DICT_SIZE-1:0][DATA_WIDTH-1:0] dict;
            dict[0] = 32'h11111111;
            dict[1] = 32'h22222222;
            dict[2] = 32'h33333333;
            dict[3] = 32'h44444444;
            dict[4] = 32'h55555555;
            dict[5] = 32'h66666666;
            dict[6] = 32'h77777777;
            dict[7] = 32'h88888888;
            setup_dict(dict, 8'hFF);
            
            search(32'hDEADBEEF);
            check_result("No match in dict", 1'b0, '0);
        end

        // ====================================================================
        // Test 5: Valid bits mask - selective validity
        // ====================================================================
        $display("\n--- Test Group 5: Valid Bits Mask ---");
        begin
            logic [DICT_SIZE-1:0][DATA_WIDTH-1:0] dict;
            dict[0] = 32'h11111111;
            dict[1] = 32'h22222222;
            dict[2] = 32'h33333333;
            dict[3] = 32'h44444444;
            dict[4] = 32'h55555555;
            dict[5] = 32'h66666666;
            dict[6] = 32'h77777777;
            dict[7] = 32'h88888888;
            
            // Only odd indices are valid
            setup_dict(dict, 8'hAA); // Indices 1,3,5,7
            search(32'h22222222);
            check_result("Match on valid entry (index 1)", 1'b1, 3'd1);
            
            search(32'h11111111);
            check_result("No hit - entry invalid (index 0)", 1'b0, '0);
            
            search(32'h33333333);
            check_result("No hit - entry invalid (index 2)", 1'b0, '0);
        end

        // ====================================================================
        // Test 6: Duplicate entries - lowest index priority
        // ====================================================================
        $display("\n--- Test Group 6: Duplicate Entries (Priority Encoding) ---");
        begin
            logic [DICT_SIZE-1:0][DATA_WIDTH-1:0] dict;
            dict[0] = 32'h12345678;
            dict[1] = 32'hAAAAAAAA;
            dict[2] = 32'h12345678; // Duplicate of dict[0]
            dict[3] = 32'hBBBBBBBB;
            dict[4] = 32'h12345678; // Another duplicate
            dict[5] = 32'hCCCCCCCC;
            dict[6] = 32'h12345678; // Yet another duplicate
            dict[7] = 32'hDDDDDDDD;
            setup_dict(dict, 8'hFF);
            
            search(32'h12345678);
            check_result("Duplicates - returns lowest index (0)", 1'b1, 3'd0);
        end

        // ====================================================================
        // Test 7: Edge case - first and last entries
        // ====================================================================
        $display("\n--- Test Group 7: Edge Cases (First/Last Entries) ---");
        begin
            logic [DICT_SIZE-1:0][DATA_WIDTH-1:0] dict;
            dict = '{default: 32'h00000000};
            dict[0] = 32'hFEDCBA98;
            dict[7] = 32'h76543210;
            setup_dict(dict, 8'h81); // Only indices 0 and 7 valid
            
            search(32'hFEDCBA98);
            check_result("First entry match", 1'b1, 3'd0);
            
            search(32'h76543210);
            check_result("Last entry match", 1'b1, 3'd7);
            
            search(32'h00000000);
            check_result("Zeros in middle - no match", 1'b0, '0);
        end

        // ====================================================================
        // Test 8: Boundary patterns - 0x00000000 and 0xFFFFFFFF
        // ====================================================================
        $display("\n--- Test Group 8: Special Patterns ---");
        begin
            logic [DICT_SIZE-1:0][DATA_WIDTH-1:0] dict;
            dict[0] = 32'h00000000;
            dict[1] = 32'hFFFFFFFF;
            dict[2] = 32'hAAAAAAAA;
            dict[3] = 32'h55555555;
            dict[4] = 32'hDEADBEEF;
            dict[5] = 32'hCAFEBABE;
            dict[6] = 32'hB00DB00D;
            dict[7] = 32'hDEADC0DE;
            setup_dict(dict, 8'hFF);
            
            search(32'h00000000);
            check_result("All-zeros pattern", 1'b1, 3'd0);
            
            search(32'hFFFFFFFF);
            check_result("All-ones pattern", 1'b1, 3'd1);
            
            search(32'hAAAAAAAA);
            check_result("Alternating pattern 1", 1'b1, 3'd2);
            
            search(32'h55555555);
            check_result("Alternating pattern 2", 1'b1, 3'd3);
        end

        // ====================================================================
        // Test 9: Sparse dictionary
        // ====================================================================
        $display("\n--- Test Group 9: Sparse Dictionary ---");
        begin
            logic [DICT_SIZE-1:0][DATA_WIDTH-1:0] dict;
            dict = '{default: 0};
            dict[2] = 32'h12345678;
            dict[5] = 32'hABCDEF00;
            setup_dict(dict, 8'h24); // Only indices 2 and 5 valid
            
            search(32'h12345678);
            check_result("Sparse - match at index 2", 1'b1, 3'd2);
            
            search(32'hABCDEF00);
            check_result("Sparse - match at index 5", 1'b1, 3'd5);
            
            search(32'h00000000);
            check_result("Sparse - no match", 1'b0, '0);
        end

        // ====================================================================
        // Test 10: Rapid sequence of searches
        // ====================================================================
        $display("\n--- Test Group 10: Rapid Sequence ---");
        begin
            logic [DICT_SIZE-1:0][DATA_WIDTH-1:0] dict;
            dict[0] = 32'h11111111;
            dict[1] = 32'h22222222;
            dict[2] = 32'h33333333;
            dict[3] = 32'h44444444;
            dict[4] = 32'h55555555;
            dict[5] = 32'h66666666;
            dict[6] = 32'h77777777;
            dict[7] = 32'h88888888;
            setup_dict(dict, 8'hFF);
            
            for (int i = 0; i < 8; i++) begin
                search(32'h11111111 + (i * 32'h11111111));
                check_result($sformatf("Sequential search %0d", i), 1'b1, i);
            end
        end

        // ====================================================================
        // Test Summary
        // ====================================================================
        $display("\n========================================");
        $display("  TEST SUMMARY");
        $display("========================================");
        $display("Total tests:  %0d", test_count);
        $display("Passed:       %0d", pass_count);
        $display("Failed:       %0d", fail_count);
        
        if (fail_count == 0) begin
            $display("\n✓ ALL TESTS PASSED!");
        end else begin
            $display("\n✗ SOME TESTS FAILED!");
        end
        $display("========================================\n");

        $finish;
    end

endmodule
