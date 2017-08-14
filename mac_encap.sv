// MAC Frame-encapsulation
module mac_encap #(
  parameter MIN_PAYLOAD_LENGTH = 46,
  parameter MAX_PAYLOAD_LENGTH = 1500
  ) (
  input  logic        clk,
  input  logic        reset,
  input  logic [7:0]  tdata,
  input  logic        tvalid,
  output logic        tready,
  input  logic        tuser,
  input  logic        tlast,
  
  input  logic [1:0]  speed_mode,
  input  logic [47:0] mac_address,
  
  output logic        gtx_clk,    // Clock signal for gigabit TX signals (125 MHz)
  output logic        clk_enable, // Clock signal for 10/100 Mbit/s signals
  output logic [7:0]  gmii_txd,   // Data to be transmitted
  output logic        gmii_txen,  // Transmitter enable
  output logic        gmii_txer   // Transmitter error (used to corrupt a packet)
  );
  
  localparam MIN_FRAME_LENGTH = MIN_PAYLOAD_LENGTH+6+6+2;
  localparam MAX_FRAME_LENGTH = MAX_PAYLOAD_LENGTH+6+6+2;
  localparam PREAMBLE_LENGTH = 7;
  localparam FCS_LENGTH = 4;
  localparam IFG_LENGTH = 12;
  localparam PREAMBLE_DATA = 8'h55;
  localparam SFD_DATA = 8'hD5;
  localparam IFG_DATA = 8'h00;
  
  typedef enum {
    IDLE,
    PREAMBLE,
    SFD,
    DATA,
    FCS,
    PAD,
    IFG
  } state_type;
  state_type state = IDLE;
  
  localparam COUNT_WDTH = $clog2(MAX_FRAME_LENGTH);
  logic [COUNT_WDTH-1:0] count = {COUNT_WDTH{1'b0}};
  
  logic [31:0] crc_cal;
  logic [7:0] crc_data;
  
  always_comb begin
    case (count[1:0])
      2'b00 : crc_data = crc_cal[31:24];
      2'b01 : crc_data = crc_cal[23:16];
      2'b10 : crc_data = crc_cal[15:08];
      2'b11 : crc_data = crc_cal[07:00];
    endcase
  end
  
  logic frame_valid;
  frame_valid = state == PREAMBLE 
              | state == SFD 
              | state == DATA 
              | state == FCS 
              | state == PAD 
              | state == IDLE && ~tready && tvalid;
  
  assign gtx_clk = clk;
  assign clk_enable = 1;
  
  always_ff @(posedge clk) begin
    case (state)
      IDLE     : gmii_txd <= ~tready && tvalid ? PREAMBLE_DATA : IFG_DATA;
      PREAMBLE : gmii_txd <= PREAMBLE_DATA;
      SFD      : gmii_txd <= SFD_DATA;
      DATA     : gmii_txd <= tready && tvalid ? tdata : IFG_DATA;
      FCS      : gmii_txd <= crc_data;
      default  : gmii_txd <= IFG_DATA;
    endcase
  end
  
  always_ff @(posedge clk) begin
    gmii_txen <= frame_valid;
  end
  
  always_ff @(posedge clk) begin
    gmii_txer <= tuser;
  end
  
  always_ff @(posedge clk) begin
    if (reset) begin
      state <= IDLE;
      count <= {COUNT_WDTH{1'b0}};
    end else begin
      case (state)
        IDLE : begin
          if (~tready && tvalid) begin
            state <= PREAMBLE;
          end
        end
        PREAMBLE : begin
          if (count >= PREAMBLE_LENGTH-2) begin
            count <= {COUNT_WDTH{1'b0}};
            state <= SFD;
          end else begin
            count <= count + 1;
          end
        end
        SFD : begin
          state <= DATA;
        end
        DATA : begin
          if (count >= MAX_FRAME_LENGTH-1) begin
            count <= {COUNT_WDTH{1'b0}};
            state <= FCS;
          end else if (tready && tvalid && tlast && count >= MIN_FRAME_LENGTH-1) begin
            count <= {COUNT_WDTH{1'b0}};
            state <= FCS;
          end else if (tready && tvalid && tlast) begin
            count <= count + 1;
            state <= PAD;
          end else begin
            count <= count + 1;
          end
        end
        PAD : begin
          if (count >= MIN_FRAME_LENGTH-1) begin
            count <= {COUNT_WDTH{1'b0}};
            state <= FCS;
          end else begin
            count <= count + 1;
          end
        end
        FCS : begin
          if (count >= FCS_LENGTH-1) begin
            count <= {COUNT_WDTH{1'b0}};
            state <= IFG;
          end else begin
            count <= count + 1;
          end
        end
        IFG : begin
          if (count >= IFG_LENGTH-1) begin
            count <= {COUNT_WDTH{1'b0}};
            state <= IDLE;
          end else begin
            count <= count + 1;
          end
        end
        default : begin
          state <= IDLE;
          count <= {COUNT_WDTH{1'b0}};
        end
      endcase
    end
  end

endmodule
