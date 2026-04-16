module twoscomplement(b, out, clock);
   input [31:0]  b;
   input         clock;
   output [31:0] out;

   reg [31:0]    out;

   integer       i;
   reg           carry;
   always @ (posedge clock) begin
      carry = 1;
      for (i = 0; i < 32; i = i + 1) begin
         out[i] = !b[i] ^ carry;
         
         carry = carry & !b[i];
      end
   end
   
endmodule // twoscomplement

module adder(a, b, sum, clock);
   input [31:0] a;
   input [31:0] b;

   input        clock;

   output [31:0] sum;

   reg [31:0]    sum;

   integer       i;
   reg           carry;

   always @ (posedge clock) begin
      carry = 0;
      
      for (i = 0; i < 32; i = i + 1) begin
         sum[i] = (a[i] ^ b[i]) ^ carry;
         carry = (a[i] & b[i]) | ((a[i] ^ b[i]) & carry);
         // $monitor("carry=%b",
         //          carry);
      end
   end
endmodule // adder

module mux(a,b,s,out,clock);
   input [31:0]  a;
   input [31:0]  b;
   input         s;
   input         clock;
   output [31:0] out;

   reg [31:0]    out;
   integer       i;

   always @ (posedge clock) begin
      out = 0;
      for (i = 0; i < 32; i = i + 1) begin
         out[i] = (a[i] & !s) | (b[i] & s);
      end
   end
endmodule // mux

module smallALU(a, b, op, result, clock);
   input [31:0]  a;
   input [31:0]  b;
   input         op;
   input         clock;

   output [31:0] result;
   wire [31:0]   twos_b;
   wire [31:0]   sum;
   wire [31:0]   rhs;

   twoscomplement twos(.b(b), .out(twos_b), .clock(clock));
   mux choice(.a(b), .b(twos_b), .s(op), .out(rhs), .clock(clock));
   adder add1(.a(a), .b(rhs), .sum(result), .clock(clock));
endmodule // smallALU

module Decoder(code, decoded, clock);
   input [4:0]   code;
   input         clock;
   output [31:0] decoded;
   reg [31:0]    decoded;
   integer       i;

   always @ (posedge clock) begin
      for (i = 0; i < 32; i = i + 1) begin
         decoded[i] <= (
                        (((i % 2) && code[0]) || (!(i % 2) && !code[0]))
                     && ((((i/2) % 2) && code[1]) || (!((i/2) % 2) && !code[1]))
                     && ((((i/4) % 2) && code[2]) || (!((i/4) % 2) && !code[2]))
                     && ((((i/8) % 2) && code[3]) || (!((i/8) % 2) && !code[3]))
                     && ((((i/16) % 2) && code[4]) || (!((i/16) % 2) && !code[4]))
                        );
      end
   end // always @ (posedge clock)
endmodule

module Registerfile(read1, read2, write_register, 
                    write_data, read_data_1,
                    read_data_2, reg_write, clock);
   input [4:0]   read1, read2, write_register;

   input [31:0]  write_data;
   input         reg_write, clock;
   output [31:0] read_data_1, read_data_2;
   reg [31:0]    RF [31:0];
   integer       i;
   
   initial begin
      for (i = 0; i < 32; i = i + 1) begin
         RF[i] = 32'b0;
      end
   end
   assign read_data_1 = RF[read1];
   assign read_data_2 = RF[read2];

   always begin
        @(posedge clock) if (reg_write) RF[write_register] <= write_data;
   end
endmodule // Registerfile

module Datapath(instruction, RegDst, RegWrite, writeData, data1, data2, clock);
   input [31:0]  instruction;
   input [31:0]  writeData;

   input         RegDst;
   input         RegWrite;
   input         clock;
   output [31:0] data1;
   output [31:0] data2;
   
   
   wire [4:0]    readRegister1;
   wire [4:0]    readRegister2;
   wire [4:0]    readRegister3;
   wire [4:0]    writeRegister;

   assign readRegister1 = instruction[25:21]; // rs
   assign readRegister2 = instruction[20:16]; // rt
   assign readRegister3 = instruction[15:11]; // rd
   
   wire [4:0] writeReg = RegDst ? readRegister2: readRegister3;
   
   // Mux mux(
   //         .a(readRegister2), 
   //         .b(instruction[15:11]), 
   //         .s(RegDist),
   //         .out(writeRegister),
   //         .clock(clock)
   //         );

   Registerfile registers(
                    .read1(readRegister1),
                    .read2(readRegister2),
                    .write_register(writeRegister),
                    .write_data(writeData),
                    .read_data_1(data1),
                    .read_data_2(data2),
                    .reg_write(RegWrite),
                    .clock(clock)
                    );
   

endmodule // control

module SRAM(address, dout, din, writeEnable, 
            readEnable, clock);
   input [31:0]      address;
   input [31:0]      din;          // Added from your port list
   input             writeEnable;  // Added from your port list
   input             readEnable;   // Added from your port list
   input             clock;
   output reg [31:0] dout;      // Must be 'reg' because it's assigned in an always block

   // 64 x 32-bit array
   reg [31:0]        memory [0:63];

   // 1. Load the memory from a file at start-up
   initial begin
      $readmemb("test.mem", memory);
   end

   // 2. Synchronous Read/Write Logic
   always @(posedge clock) begin
      if (writeEnable) begin
         memory[address[5:0]] <= din; // Use lower 6 bits for 64 entries
      end
      
      if (readEnable) begin
         dout <= memory[address[5:0]];
      end
   end
endmodule // SRAM

module mem(PC, out, clock);
   input  [31:0] PC;
   input         clock; // Changed from int to input
   output [31:0] out;
   
   wire [5:0]    word_index = PC[7:2];
   // Instantiate the SRAM module
   // We map PC to address and out to dout
   SRAM instruction_storage (
      .address({26'b0, word_index}),
      .dout(out),
      .din(32'b0),          // Instruction memory is usually read-only
      .writeEnable(1'b0),   // Disable writing
      .readEnable(1'b1),    // Always enable reading
      .clock(clock)
   );

endmodule; // mem

module Instruction_Pipeline(instruction, clock);
   // instruction [25:0] -> control circuit
   // instruction [25:21] -> register circuit as read register 1
   // instruction [20:16] -> register circuit as read register 2
   // (instruct[20:16], [15-11]) 0 for first 1 for 2nd
   // instruction [15:0] -> register circuit as read register 2
