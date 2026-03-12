module pfe_chip (
  input  wire clk_i,
  input  wire rst_ni,

    // Input stream (producer -> FIFO)
  input  wire in_valid_i,
  output wire in_ready_o,
  input  wire in_data_0_i,
  input  wire in_data_1_i,
  input  wire in_data_2_i,
  input  wire in_data_3_i,
  input  wire in_data_4_i,
  input  wire in_data_5_i,
  input  wire in_data_6_i,
  input  wire in_data_7_i,

  // Output stream (FIFO -> consumer)
  output wire out_valid_o,
  input  wire out_ready_i,
  output wire out_data_0_o,
  output wire out_data_1_o,
  output wire out_data_2_o,
  output wire out_data_3_o,
  output wire out_data_4_o,
  output wire out_data_5_o,
  output wire out_data_6_o,
  output wire out_data_7_o,

  output wire unused0_o,
  output wire unused1_o,

  inout wire VDD,
  inout wire VSS,
  inout wire VDDIO,
  inout wire VSSIO
); 
    logic soc_clk_i;
    logic soc_rst_ni;
    logic soc_ref_clk_i;
    logic soc_testmode_i;

    logic soc_jtag_tck_i;
    logic soc_jtag_trst_ni;
    logic soc_jtag_tms_i;
    logic soc_jtag_tdi_i;
    logic soc_jtag_tdo_o;

    logic soc_status_o;

    localparam int unsigned DataCount = 16;

    logic                 soc_in_valid_i;
    logic                 soc_in_ready_o;
    logic [DataCount-1:0] soc_in_data_i; 
    logic                 soc_out_valid_o;
    logic                 soc_out_ready_i;            
    logic [DataCount-1:0] soc_out_data_o;

    sg13g2_IOPadIn        pad_clk_i        (.pad(clk_i),        .p2c(soc_clk_i));
    sg13g2_IOPadIn        pad_rst_ni       (.pad(rst_ni),       .p2c(soc_rst_ni));

    // in_data
    sg13g2_IOPadIn        pad_in_valid_i    (.pad(in_valid_i),    .p2c(soc_in_valid_i));
    sg13g2_IOPadOut16mA   pad_in_ready_o    (.pad(in_ready_o),    .c2p(soc_in_ready_o));
    sg13g2_IOPadIn        pad_in_data_0_i   (.pad(in_data_0_i),   .p2c(soc_in_data_i[0]));
    sg13g2_IOPadIn        pad_in_data_1_i   (.pad(in_data_1_i),   .p2c(soc_in_data_i[1]));
    sg13g2_IOPadIn        pad_in_data_2_i   (.pad(in_data_2_i),   .p2c(soc_in_data_i[2]));
    sg13g2_IOPadIn        pad_in_data_3_i   (.pad(in_data_3_i),   .p2c(soc_in_data_i[3]));
    sg13g2_IOPadIn        pad_in_data_4_i   (.pad(in_data_4_i),   .p2c(soc_in_data_i[4]));
    sg13g2_IOPadIn        pad_in_data_5_i   (.pad(in_data_5_i),   .p2c(soc_in_data_i[5]));
    sg13g2_IOPadIn        pad_in_data_6_i   (.pad(in_data_6_i),   .p2c(soc_in_data_i[6]));
    sg13g2_IOPadIn        pad_in_data_7_i   (.pad(in_data_7_i),   .p2c(soc_in_data_i[7]));

    // out_data
    sg13g2_IOPadOut16mA   pad_out_valid_o   (.pad(out_valid_o),   .c2p(soc_out_valid_o));
    sg13g2_IOPadIn        pad_out_ready_i   (.pad(out_ready_i),   .p2c(soc_out_ready_i));
    sg13g2_IOPadOut16mA   pad_out_data_0_o  (.pad(out_data_0_o),  .c2p(soc_out_data_o[0]));
    sg13g2_IOPadOut16mA   pad_out_data_1_o  (.pad(out_data_1_o),  .c2p(soc_out_data_o[1]));
    sg13g2_IOPadOut16mA   pad_out_data_2_o  (.pad(out_data_2_o),  .c2p(soc_out_data_o[2]));
    sg13g2_IOPadOut16mA   pad_out_data_3_o  (.pad(out_data_3_o),  .c2p(soc_out_data_o[3]));
    sg13g2_IOPadOut16mA   pad_out_data_4_o  (.pad(out_data_4_o),  .c2p(soc_out_data_o[4]));
    sg13g2_IOPadOut16mA   pad_out_data_5_o  (.pad(out_data_5_o),  .c2p(soc_out_data_o[5]));
    sg13g2_IOPadOut16mA   pad_out_data_6_o  (.pad(out_data_6_o),  .c2p(soc_out_data_o[6]));
    sg13g2_IOPadOut16mA   pad_out_data_7_o  (.pad(out_data_7_o),  .c2p(soc_out_data_o[7]));

    sg13g2_IOPadOut16mA pad_unused0_o      (.pad(unused0_o),    .c2p(soc_status_o));
    sg13g2_IOPadOut16mA pad_unused1_o      (.pad(unused1_o),    .c2p(soc_status_o));


    (* dont_touch = "true" *)sg13g2_IOPadVdd pad_vdd0();
    (* dont_touch = "true" *)sg13g2_IOPadVdd pad_vdd1();
    (* dont_touch = "true" *)sg13g2_IOPadVdd pad_vdd2();
    (* dont_touch = "true" *)sg13g2_IOPadVdd pad_vdd3();

    (* dont_touch = "true" *)sg13g2_IOPadVss pad_vss0();
    (* dont_touch = "true" *)sg13g2_IOPadVss pad_vss1();
    (* dont_touch = "true" *)sg13g2_IOPadVss pad_vss2();
    (* dont_touch = "true" *)sg13g2_IOPadVss pad_vss3();

    (* dont_touch = "true" *)sg13g2_IOPadIOVdd pad_vddio0();
    (* dont_touch = "true" *)sg13g2_IOPadIOVdd pad_vddio1();
    (* dont_touch = "true" *)sg13g2_IOPadIOVdd pad_vddio2();
    (* dont_touch = "true" *)sg13g2_IOPadIOVdd pad_vddio3();

    (* dont_touch = "true" *)sg13g2_IOPadIOVss pad_vssio0();
    (* dont_touch = "true" *)sg13g2_IOPadIOVss pad_vssio1();
    (* dont_touch = "true" *)sg13g2_IOPadIOVss pad_vssio2();
    (* dont_touch = "true" *)sg13g2_IOPadIOVss pad_vssio3();

  pfe_soc #(
    .DSIZE    (   8 ),
    .ASIZE    (   8 ),
    .USE_SRAM ( 1'b1 )
  )
  i_fifo_soc (
    .clk_i          ( soc_clk_i       ),
    .rst_ni         ( soc_rst_ni      ),
    .in_valid_i     ( soc_in_valid_i  ),
    .in_ready_o     ( soc_in_ready_o  ),
    .in_data_i      ( soc_in_data_i   ),
    .out_valid_o    ( soc_out_valid_o ),
    .out_ready_i    ( soc_out_ready_i ),
    .out_data_o     ( soc_out_data_o  )
  );

  assign soc_status_o = 1'b1;

endmodule
