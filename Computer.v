module ALU(a, b, op, result, zero, clock);
   input [31:0]  a;
   input [31:0]  b;
   input [3:0]   op;
   input         clock;
   output [31:0] result;

   always @(*) begin
      case (op)
        4'b0010: begin
           result <= a + b;
        end
        4'b0110: begin
           result <= a - b;
        end
        4'b0000: begin
           result <= a & b;
        end
        4'b0001: begin
           result <= a | b;
        end
        4'b0111: begin
           result <= a < b;
        end
      endcase // case (op)
   end // always @ (*)

   assign zero = (result == 32'b0);
   
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

module Registerfile(read1, read2, write_register, write_data,
                    read_data_1, read_data_2, reg_write, clock);
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

// module Datapath(instruction, RegDst, RegWrite, writeData, data1, data2, clock);
//    input [31:0]  instruction;
//    input [31:0]  writeData;

//    input         RegDst;
//    input         RegWrite;
//    input         clock;
//    output [31:0] data1;
//    output [31:0] data2;
   
   
//    wire [4:0]    readRegister1;
//    wire [4:0]    readRegister2;
//    wire [4:0]    readRegister3;
//    wire [4:0]    writeRegister;

//    assign readRegister1 = instruction[25:21]; // rs
//    assign readRegister2 = instruction[20:16]; // rt
//    assign readRegister3 = instruction[15:11]; // rd
   
//    wire [4:0] writeReg = RegDst ? readRegister2: readRegister3;
   
//    // Mux mux(
//    //         .a(readRegister2), 
//    //         .b(instruction[15:11]), 
//    //         .s(RegDist),
//    //         .out(writeRegister),
//    //         .clock(clock)
//    //         );

//    Registerfile registers(
//                     .read1(readRegister1),
//                     .read2(readRegister2),
//                     .write_register(writeRegister),
//                     .write_data(writeData),
//                     .read_data_1(data1),
//                     .read_data_2(data2),
//                     .reg_write(RegWrite),
//                     .clock(clock)
//                     );

// endmodule // control

module SRAM(address, dout, din, MemWrite, 
            MemRead, clock);
   input [31:0]      address;
   input [31:0]      din;          // Added from your port list
   input             MemWrite;  // Added from your port list
   input             MemRead;   // Added from your port list
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
      if (MemWrite) begin
         memory[address[5:0]] <= din; // Use lower 6 bits for 64 entries
      end
      
      if (MemRead) begin
         dout <= memory[address[5:0]];
      end
   end
endmodule // SRAM

module instruction_memory(PC, out, clock);
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
      .MemWrite(1'b0),   // Disable writing
      .MemRead(1'b1),    // Always enable reading
      .clock(clock)
   );

endmodule; // mem

module Control(Opcode, PCWriteCond, PCWrite, IorD, MemRead, 
               MemWrite, MemtoReg, IRWrite, PCSource, 
               ALUOp, ALUSrcA, ALUSrcB, RegWrite, RegDst);
   input [5:0]  Opcode;
   output       ALUSrcA, MemRead, MemWrite, MemtoReg, IorD;
   output       PCWrite, PCWriteCond, IRWrite, PCWrite, RegDst, RegWrite;
   output [1:0] ALUOp, ALUSrcB, PCSource;
   localparam   FETCH  = 4'd0, DECODE = 4'd1, MEM_ADR= 4'd2,  MEM_RD = 4'd3,
                MEM_WB = 4'd4, EXEC   = 4'd6, R_TYPE = 4'd7, BEQ_STATE = 4'd8,
                J_STATE = 4'd9;
   
   reg [3:0]    state, next_state;

   // Sequential block to update the current state
   always @(posedge clock or posedge reset) begin
       if (reset) state <= FETCH;
       else       state <= next_state;
   end
   
   always @(*) begin
        // Initialize all outputs to 0 to avoid unintended latches
        {ALUSrcA, MemRead, MemWrite, MemtoReg, IorD} = 5'b0;
        {PCWrite, PCWriteCond, IRWrite, RegDst, RegWrite} = 5'b0;
        {ALUOp, ALUSrcB, PCSource} = 6'b0;
        next_state = FETCH;
      
      case (state)
        FETCH: begin
           MemRead = 1;
           IorD = 0;
           IRWrite = 1;
           ALUSrcB = 2'b01; // Constant 4
           ALUSrcA = 0;     // Use PC
           ALUOp = 2'b00;   // Add
           PCWrite = 1;
           PCSource = 2'b00;
           next_state = DECODE;
        end

        DECODE: begin
           ALUSrcA = 0;
           ALUSrcB = 2'd3;
           ALUOp = 2'b00;
           RegWrite = 0;
           
           if (Opcode == 6'h23 || Opcode == 6'h2b)
             next_state = MEM_ADR;
           else if (Opcode == 6'h0)
             next_state = EXEC;
           else if (Opcode == 6'h4)
             next_state = 4'd8;
           else if (Opcode == 6'h2)
             next_state = 4'd9;
        end // case: DECODE

        MEM_ADR: begin
           ALUSrcB = 2'b10;
           ALUSrcA = 1;
           ALUOp = 2'b00;
           
           if (Opcode == 6'h23)
             next_state = MEM_RD;
           else
             next_state = 4'd5;
        end

        MEM_RD: begin
           IorD = 1;
           MemRead = 1;
           next_state = MEM_WB;
        end

        MEM_WB: begin
           RegWrite = 1;
           MemtoReg = 1;
           RegDst = 0;
           next_state = FETCH;
        end

        4'd5: begin
           IorD = 1;
           MemWrite = 1;
           next_state = FETCH;
        end

        EXEC: begin
           ALUSrcA = 1;
           ALUSrcB = 2'b00;
           ALUOp = 2'b10;
           next_state = R_TYPE;
        end

        R_TYPE: begin
           MemtoReg = 0;
           RegWrite = 1;
           RegDst = 1;
           next_state = FETCH;
        end

        BEQ_STATE: begin
           ALUOp = 2'b01;
           ALUSrcA = 1;
           ALUSrcB = 2'b00;
           PCSource = 2'b01;
           PCWriteCond = 1;
           next_state = FETCH;
        end

        J_STATE: begin
           PCSource = 2;
           PCWrite = 1;
           next_state = FETCH;
        end
      endcase
endmodule // Control

module ALUControl(ALUOp, Funct, ALUControlOut, clock);
   input [1:0]  ALUOp;
   input [5:0]  Funct;
   output [3:0] ALUControlOut;
   always @(*) begin
      case (ALUOp)
        2'b00: ALUControlOut = 4'b0010; // Force Add (LW, SW, ADDI)
        2'b01: ALUControlOut = 4'b0110; // Force Subtract (BEQ)
        
        2'b10: begin // R-type: Look at Funct field
           case (Funct)
             6'h20: ALUControlOut = 4'b0010; // ADD
             6'h22: ALUControlOut = 4'b0110; // SUB
             6'h24: ALUControlOut = 4'b0000; // AND
             6'h25: ALUControlOut = 4'b0001; // OR
             6'h2a: ALUControlOut = 4'b0111; // SLT
             default: ALUControlOut = 4'b0000;
           endcase
        end
        
        default: ALUControlOut = 4'b0010; // Default to Add
      endcase
   end
endmodule // ALUControl

module Multicycle_Pipeline;
   reg [31:0]  PC;
   reg [31:0]  Instruction;
   reg [31:0]  MemoryData;

   reg         IorD;
   reg [31:0]  Address;
   reg [31:0]  ALUOut;
   reg [1:0]   ALUSrcB;
   reg         MemWrite;
   reg         MemRead;
   reg         IRWrite;
   reg         RegDst;
   reg         RegWrite;
   reg         MemtoReg;

   wire [31:0] Address;
   wire [31:0] Write_data;
   wire [31:0] A;
   wire [31:0] signextend;
   
   // PC to memory address or aluoutput
   if ( (PCWriteCond & zero) | PCWrite)
     PC = jumpaddress;
   
   assign Address = IorD ? ALUOut : PC;

   // address used in memory data
   SRAM memory(
               .address(Address),
               .dout(MemoryData),
               .din(WriteData),
               .MemWrite(MemWrite),
               .MemRead(MemRead),
               .clock(clock)
               );

   // instruction write
   assign Instruction = IRWrite ? MemoryData : Instruction;
   Control control(
                   .Opcode(Instruction[31:26]), .PCWriteCond(PCWriteCond), .PCWrite(PCWrite),
                   .IorD(IorD), .MemRead(MemRead), .MemWrite(MemWrite), .MemtoReg(MemtoReg),
                   .IRWrite(IRWrite), .PCSource(PCSource), .ALUOp(ALUop),
                   .ALUSrcA(ALUSrcA), .ALUSrcB(ALUSrcB), .RegWrite(RegWrite),
                   .RegDst(RegDst)
                   );
   assign WriteData = MemtoReg ? MemoryData : ALUOut;
   assign signextended = {{16{Instruction[15]}}, Instruction[15:0]};
   assign WriteRegister = RegDst ? instruction[15:11] : instruction[20:16];
   RegisterFile register(
                         .read1(instruction[25:21]), .read2(instruction[20:16]),
                         .write_register(WriteRegister), .write_data(WriteData),
                         .read_data_1(ReadData1), .read_data_2(ReadData2),
                         .reg_write(WriteData), .clock(clock)
                         );
   
   assign A = ALUSrcA ? ReadData1 : PC;
   always @(*) begin
      case (ALUSrcB)
        2'b00: B = ReadData2;          // R-type instructions
        2'b01: B = 32'd4;             // PC + 4 increment
        2'b10: B = signextended;      // I-type instructions (e.g., addi, lw)
        2'b11: B = signextended << 2; // Branch offsets (PC-relative)
        default: B = 32'b0;           // Safety catch-all
      endcase // case (ALUSrcB)
   end
         
   ALUControl alucontrol(
                         .ALUOp(ALUOp), .Funct(Instruction[5:0]),
                         .ALUControlOut(ALUControlOut), .clock(clock)
                         );
   ALU alu(
           .a(A), .b(B), 
           .op(ALUControlOut), 
           .result(ALUresult), 
           .zero(zero), .clock(clock)
           );
   
   always @(*) begin
      case (PCSource)
        2'b00: jumpaddress = ALUresult;
        2'b01: jumpaddress = ALUOut;
        2'b10: jumpaddress = (Instruction[25:0] << 2) | (PC[31:28] << 28);
      endcase
   end
endmodule // Multicycle_Pipeline
