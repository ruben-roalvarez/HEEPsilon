// Copyright 2022 EPFL
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

module datapath
  import cgra_pkg::*;
(
  input  logic                         clk_i,
  input  logic                         rst_i,
  input  logic                         ce_i,
  input  logic [      INSTR_WIDTH-1:0] conf_rdata_i,
  input  logic [         DP_WIDTH-1:0] data_rdata_i,
  input  logic                         data_rvalid_i,
  input  logic [         DP_WIDTH-1:0] left_regs_i   [0:RC_NUM_REG-1],
  input  logic [         DP_WIDTH-1:0] right_regs_i  [0:RC_NUM_REG-1],
  input  logic [         DP_WIDTH-1:0] top_regs_i    [0:RC_NUM_REG-1],
  input  logic [         DP_WIDTH-1:0] bottom_regs_i [0:RC_NUM_REG-1],
  input  logic [       ALU_N_FLAG-1:0] own_flag_i,
  input  logic [       ALU_N_FLAG-1:0] left_flag_i,
  input  logic [       ALU_N_FLAG-1:0] right_flag_i,
  input  logic [       ALU_N_FLAG-1:0] top_flag_i,
  input  logic [       ALU_N_FLAG-1:0] bottom_flag_i,
  input  logic                         conf_re_i,
  output logic [         DP_WIDTH-1:0] self_regs_o   [0:RC_NUM_REG-1],
  output logic [       ALU_N_FLAG-1:0] flag_o,
  output logic                         br_req_o,
  output logic [RCS_NUM_CREG_LOG2-1:0] br_add_o,
  output logic                         data_req_o,
  output logic                         data_wen_o,
  output logic                         data_ind_o,
  output logic [         DP_WIDTH-1:0] data_add_o,
  output logic [         DP_WIDTH-1:0] data_wdata_o,
  output logic                         dp_stall_o,
  output logic                         rc_nop_o,
  output logic                         exec_end_o
);

  logic [         DP_WIDTH-1:0] mux_a_out;
  logic [         DP_WIDTH-1:0] mux_b_out;

  logic [         DP_WIDTH-1:0] self_a_res;
  logic [         DP_WIDTH-1:0] left_a_res;
  logic [         DP_WIDTH-1:0] right_a_res;
  logic [         DP_WIDTH-1:0] top_a_res;
  logic [         DP_WIDTH-1:0] bottom_a_res;
  logic [         DP_WIDTH-1:0] self_b_res;
  logic [         DP_WIDTH-1:0] left_b_res;
  logic [         DP_WIDTH-1:0] right_b_res;
  logic [         DP_WIDTH-1:0] top_b_res;
  logic [         DP_WIDTH-1:0] bottom_b_res;

  logic [       ALU_N_FLAG-1:0] mux_flag_out;
  logic [    RC_MUX_A_NSEL-1:0] mux_a_sel;
  logic [         DP_WIDTH-1:0] mux_a_inputs [0:RC_MUX_A_NUM_INPUTS-1];
  logic [   RC_NUM_REG_LOG-1:0] mux_a_rf_sel;
  logic [    RC_MUX_B_NSEL-1:0] mux_b_sel;
  logic [         DP_WIDTH-1:0] mux_b_inputs [0:RC_MUX_B_NUM_INPUTS-1];
  logic [   RC_NUM_REG_LOG-1:0] mux_b_rf_sel;
  logic [ RC_MUX_FLAG_NSEL-1:0] mux_flag_sel;
  logic [       ALU_N_FLAG-1:0] mux_flag_inputs [0:RC_MUX_FLAG_NUM_INPUTS-1];
  logic [         DP_WIDTH-1:0] alu_res;
  logic [CGRA_ALU_OP_WIDTH-1:0] alu_op;
  logic [                2-1:0] reg_sel;
  logic                         reg_we;
  logic [         DP_WIDTH-1:0] regs_rdata [0:RC_NUM_REG-1];
  logic [   RC_CONST_WIDTH-1:0] imm_val;
  logic [         DP_WIDTH-1:0] imm_sign_ext;
  logic [       ALU_N_FLAG-1:0] alu_flag;
  logic                         br_req_s;
  logic [RCS_NUM_CREG_LOG2-1:0] br_add_s;
  logic                         data_req_s;
  logic                         data_we_s;
  logic                         data_ind_s;
  logic [         DP_WIDTH-1:0] data_alu_mux;
  logic                         rf_en;


  // Visible RF output
  always_comb begin
    for (int i = 0; i < RC_NUM_REG; i++) begin
      self_regs_o[i] = regs_rdata[i];
    end
  end

  assign flag_o      = alu_flag;

  // Here the configuration word is decoded and fed to the different components
  assign mux_a_sel    = conf_rdata_i[31:29];
  assign mux_a_rf_sel = conf_rdata_i[28:27];
  assign mux_b_sel    = conf_rdata_i[26:24];
  assign mux_b_rf_sel = conf_rdata_i[23:22];
  assign alu_op       = conf_rdata_i[21:17];
  assign reg_sel      = conf_rdata_i[16:15]; // selected register to write to
  assign mux_flag_sel = conf_rdata_i[14:12];
  assign imm_val      = conf_rdata_i[RC_CONST_WIDTH-1:0];
  assign imm_sign_ext = {{(DP_WIDTH-RC_CONST_WIDTH){imm_val[RC_CONST_WIDTH-1]}}, imm_val[RC_CONST_WIDTH-1:0]};

  // detect nop to retain value in output register
  assign rc_nop_o = (alu_op == CGRA_ALU_NOP) ? 1'b1 : 1'b0;

  // If RC request a data, write to register when data is available
  // otherwise wait end of instruction and update the register but not if 
  // it has already been updated from a data request
  assign rf_en = (data_req_s & data_rvalid_i) | (ce_i & ~data_req_s);

  // Detect when to write in the register file
  assign reg_we = (
    alu_op == CGRA_ALU_SADD   |
    alu_op == CGRA_ALU_SSUB   |
    alu_op == CGRA_ALU_SMUL   |
    alu_op == CGRA_ALU_FXPMUL |
    alu_op == CGRA_ALU_SLL    |
    alu_op == CGRA_ALU_SRL    |
    alu_op == CGRA_ALU_SRA    |
    alu_op == CGRA_ALU_LAND   |
    alu_op == CGRA_ALU_LOR    |
    alu_op == CGRA_ALU_LXOR   |
    alu_op == CGRA_ALU_LNAND  |
    alu_op == CGRA_ALU_LNOR   |
    alu_op == CGRA_ALU_LNXOR  |
    alu_op == CGRA_ALU_BSFA   |
    alu_op == CGRA_ALU_BZFA   |
    alu_op == CGRA_ALU_LWD    |
    alu_op == CGRA_ALU_SWD    |
    alu_op == CGRA_ALU_LWI    |
    alu_op == CGRA_ALU_SWI
    ) ? 1'b1 : 1'b0;


  //////////////////////////////////
  //  _     ____    ______ _____  //
  // | |   |  _ \  / / ___|_   _| //
  // | |   | | | |/ /\___ \ | |   //
  // | |___| |_| / /  ___) || |   //
  // |_____|____/_/  |____/ |_|   //
  //                              //
  //////////////////////////////////

  assign data_req_o = data_req_s & conf_re_i;
  assign data_wen_o = ~data_we_s & conf_re_i;
  assign data_ind_o = data_ind_s & conf_re_i;

  always_comb
  begin

    data_req_s = 1'b0;
    data_we_s  = 1'b0;
    data_ind_s = 1'b0;

    unique case (alu_op)
      CGRA_ALU_LWD:
      begin
        data_req_s = 1'b1;
        data_we_s  = 1'b0;
        data_ind_s = 1'b0;
      end
      CGRA_ALU_LWI:
      begin
        data_req_s = 1'b1;
        data_we_s  = 1'b0;
        data_ind_s = 1'b1;
      end
      CGRA_ALU_SWD:
      begin
        data_req_s = 1'b1;
        data_we_s  = 1'b1;
        data_ind_s = 1'b0;
      end
      CGRA_ALU_SWI:
      begin
        data_req_s = 1'b1;
        data_we_s  = 1'b1;
        data_ind_s = 1'b1;
      end
      default: ;
    endcase
  end

  // data_rdata_i goes directly to register file (not through the ALU)
  always_comb
  begin
    if (data_req_s == 1'b1 && data_we_s == 1'b0) begin
      data_alu_mux = data_rdata_i;
    end else begin
      data_alu_mux = alu_res;
    end
  end

  // For read/write memory access operand b holds the address for indirect memory accesses
  always_comb
  begin
    if (data_req_s == 1'b1) begin
      data_wdata_o = mux_a_out;
      data_add_o = mux_b_out;
    end else begin
      data_wdata_o = mux_a_out;
      data_add_o = '0;
    end
  end

  //////////////////////////////////////////////
  //   ____ ____     _    _   _  ____ _   _   //
  //  |  _ \  _ \   / \  | \ | |/ ___/ |_| |  //
  //  |  _ < |_) | / _ \ |  \| | |   |  _  |  //
  //  | |_)|  _ < / ___ \| |\  | |__ | | | |  //
  //  |____/_| \_\_/   \_\_| \_|\____\_| |_|  //
  //                                          //
  //////////////////////////////////////////////

  // Constant field is used for branch ops (as long as constant field is big enough)
  always_comb
  begin
    br_req_o = br_req_s;
    br_add_o = '0;

    if (br_req_s == 1'b1) begin
      if (alu_op == CGRA_ALU_JUMP) begin
        br_add_o = br_add_s;//alu_res[RCS_NUM_CREG_LOG2-1:0];
      end else if (br_req_s == 1'b1) begin
        br_add_o = imm_val[RCS_NUM_CREG_LOG2-1:0];
      end
    end
  end

  //////////////////////////////
  //   _______  _____ _____   //
  //  | ____\ \/ /_ _|_   _|  //
  //  |  _|  \  / | |  | |    //
  //  | |___ /  \ | |  | |    //
  //  |_____/_/\_\___| |_|    //
  //                          //
  //////////////////////////////

  always_comb
  begin
    exec_end_o = 1'b0;

    if (conf_re_i == 1'b1 && alu_op == CGRA_ALU_EXIT) begin
      exec_end_o = 1'b1;
    end
  end

  //--------------------------------------------------------
  //
  // Components mapping
  //
  //--------------------------------------------------------

  assign mux_a_inputs[ 0] = '0; // Hardcoded zero entry
  assign mux_a_inputs[ 1] = self_a_res;
  assign mux_a_inputs[ 2] = left_a_res;
  assign mux_a_inputs[ 3] = right_a_res;
  assign mux_a_inputs[ 4] = top_a_res;
  assign mux_a_inputs[ 5] = bottom_a_res;
  assign mux_a_inputs[ 6] = imm_sign_ext;
  assign mux_a_inputs[ 7] = '0; // free

  assign mux_b_inputs[ 0] = '0; // Hardcoded zero entry
  assign mux_b_inputs[ 1] = self_b_res;
  assign mux_b_inputs[ 2] = left_b_res;
  assign mux_b_inputs[ 3] = right_b_res;
  assign mux_b_inputs[ 4] = top_b_res;
  assign mux_b_inputs[ 5] = bottom_b_res;
  assign mux_b_inputs[ 6] = imm_sign_ext;
  assign mux_b_inputs[ 7] = '0; // free

  assign mux_flag_inputs[0] = own_flag_i;
  assign mux_flag_inputs[1] = left_flag_i;
  assign mux_flag_inputs[2] = right_flag_i;
  assign mux_flag_inputs[3] = top_flag_i;
  assign mux_flag_inputs[4] = bottom_flag_i;
  assign mux_flag_inputs[5] = '0; // free
  assign mux_flag_inputs[6] = '0; // free
  assign mux_flag_inputs[7] = '0; // free

  // Self
  mux #(
    .MUX_NUM_INPUTS   ( RC_NUM_REG ),
    .MUX_INPUTS_WIDTH ( DP_WIDTH   )
  ) mux_a_self_rf_i
  (
    .mux_inputs ( regs_rdata   ),
    .mux_sel    ( mux_a_rf_sel ),
    .mux_o      ( self_a_res   )
  );
  
  mux #(
    .MUX_NUM_INPUTS   ( RC_NUM_REG ),
    .MUX_INPUTS_WIDTH ( DP_WIDTH   )
  ) mux_b_self_rf_i
  (
    .mux_inputs ( regs_rdata   ),
    .mux_sel    ( mux_b_rf_sel ),
    .mux_o      ( self_b_res   )
  );

  // Left
  mux #(
    .MUX_NUM_INPUTS   ( RC_NUM_REG ),
    .MUX_INPUTS_WIDTH ( DP_WIDTH   )
  ) mux_a_left_rf_i
  (
    .mux_inputs ( left_regs_i  ),
    .mux_sel    ( mux_a_rf_sel ),
    .mux_o      ( left_a_res   )
  );

  mux #(
    .MUX_NUM_INPUTS   ( RC_NUM_REG ),
    .MUX_INPUTS_WIDTH ( DP_WIDTH   )
  ) mux_b_left_rf_i
  (
    .mux_inputs ( left_regs_i  ),
    .mux_sel    ( mux_b_rf_sel ),
    .mux_o      ( left_b_res   )
  );

  // Right
  mux #(
    .MUX_NUM_INPUTS   ( RC_NUM_REG ),
    .MUX_INPUTS_WIDTH ( DP_WIDTH   )
  ) mux_a_right_rf_i
  (
    .mux_inputs ( right_regs_i ),
    .mux_sel    ( mux_a_rf_sel ),
    .mux_o      ( right_a_res  )
  );

  mux #(
    .MUX_NUM_INPUTS   ( RC_NUM_REG ),
    .MUX_INPUTS_WIDTH ( DP_WIDTH   )
  ) mux_b_right_rf_i
  (
    .mux_inputs ( right_regs_i ),
    .mux_sel    ( mux_b_rf_sel ),
    .mux_o      ( right_b_res  )
  );

  // Top
  mux #(
    .MUX_NUM_INPUTS   ( RC_NUM_REG ),
    .MUX_INPUTS_WIDTH ( DP_WIDTH   )
  ) mux_a_top_rf_i
  (
    .mux_inputs ( top_regs_i   ),
    .mux_sel    ( mux_a_rf_sel ),
    .mux_o      ( top_a_res    )
  );

  mux #(
    .MUX_NUM_INPUTS   ( RC_NUM_REG ),
    .MUX_INPUTS_WIDTH ( DP_WIDTH   )
  ) mux_b_top_rf_i
  (
    .mux_inputs ( top_regs_i   ),
    .mux_sel    ( mux_b_rf_sel ),
    .mux_o      ( top_b_res    )
  );

  // Bottom
  mux #(
    .MUX_NUM_INPUTS   ( RC_NUM_REG ),
    .MUX_INPUTS_WIDTH ( DP_WIDTH   )
  ) mux_a_bottom_rf_i
  (
    .mux_inputs ( bottom_regs_i),
    .mux_sel    ( mux_a_rf_sel ),
    .mux_o      ( bottom_a_res )
  );

  mux #(
    .MUX_NUM_INPUTS   ( RC_NUM_REG ),
    .MUX_INPUTS_WIDTH ( DP_WIDTH   )
  ) mux_b_bottom_rf_i
  (
    .mux_inputs ( bottom_regs_i),
    .mux_sel    ( mux_b_rf_sel ),
    .mux_o      ( bottom_b_res )
  );

  mux #(
    .MUX_NUM_INPUTS   ( RC_MUX_A_NUM_INPUTS ),
    .MUX_INPUTS_WIDTH ( DP_WIDTH            )
  ) mux_a_i
  (
    .mux_inputs ( mux_a_inputs ),
    .mux_sel    ( mux_a_sel    ),
    .mux_o      ( mux_a_out    )
  );

  mux #(
    .MUX_NUM_INPUTS   ( RC_MUX_B_NUM_INPUTS ),
    .MUX_INPUTS_WIDTH ( DP_WIDTH            )
  ) mux_b_i
  (
    .mux_inputs ( mux_b_inputs ),
    .mux_sel    ( mux_b_sel    ),
    .mux_o      ( mux_b_out    )
  );

  mux #(
    .MUX_NUM_INPUTS   ( RC_MUX_FLAG_NUM_INPUTS   ),
    .MUX_INPUTS_WIDTH ( RC_MUX_FLAG_INPUTS_WIDTH )
  ) mux_flag_i
  (
    .mux_inputs ( mux_flag_inputs ),
    .mux_sel    ( mux_flag_sel    ),
    .mux_o      ( mux_flag_out    )
  );

  alu rc_alu
  (
    .operand_a_i ( mux_a_out    ),
    .operand_b_i ( mux_b_out    ),
    .flag_i      ( mux_flag_out ),
    .alu_op_i    ( alu_op       ),
    .alu_res_o   ( alu_res      ),
    .flag_o      ( alu_flag     ),
    .br_req_o    ( br_req_s     ),
    .br_add_o    ( br_add_s     ),
    .alu_stall_o ( dp_stall_o   )
  );

  reg_file #(
    .REGFILE_DEPTH ( RC_NUM_REG ),
    .REGFILE_WIDTH ( DP_WIDTH   )
  ) reg_file_i
  (
    .clk_i  ( clk_i        ),
    .rst_i  ( rst_i        ),
    .ce_i   ( rf_en        ),
    .we_i   ( reg_we       ),
    .wsel_i ( reg_sel      ),
    .reg_i  ( data_alu_mux ),
    .regs_o ( regs_rdata   )
  );

endmodule
