module S32X_VDP (
	input             CLK,
	input             RST_N,
	input             CE_R,
	input             CE_F,
	
	input             MRES_N,
	input             VSYNC_N,
	input             HSYNC_N,
	input             EDCLK_CE,
	input             YS_N,
	
	input             PAL,
	
	input      [17:1] A,
	input      [15:0] DI,
	output     [15:0] DO,
	input             RD_N,
	input             LWR_N,
	input             UWR_N,
	output            ACK_N,
	input             DRAM_CS_N,
	input             REG_CS_N,
	input             PAL_CS_N,
	
	output            VINT,
	output            HINT,
	
	output     [15:0] FB0_A,
	input      [15:0] FB0_DI,
	output     [15:0] FB0_DO,
	output      [1:0] FB0_WE,
	
	output     [15:0] FB1_A,
	input      [15:0] FB1_DI,
	output     [15:0] FB1_DO,
	output      [1:0] FB1_WE,
	
	output      [4:0] R,
	output      [4:0] G,
	output      [4:0] B,
	output            YSO_N	//0 - 32X pixel, 1 - MD pixel
);
	import S32X_PKG::*;
	
	BMMR_t     BMMR;
	PPCR_t     PPCR;
	AFLR_t     AFLR;
	AFAR_t     AFAR;
	AFDR_t     AFDR;
	FBCR_t     FBCR;
	
	bit        VBLK;
	bit        HBLK;
	bit        PEN;
	bit        FEN;

	
	bit        FB_SEL;
	bit [15:0] FB_DRAW_A;
	bit [15:0] FB_DRAW_D;
	bit  [1:0] FB_DRAW_WE;
	bit [15:0] FB_DRAW_Q;
	
	bit [15:0] FB_DISP_A;
	bit [15:0] FB_DISP_Q;

	bit        FILL_EXEC;
	bit        FILL_WR;

	always @(posedge CLK or negedge RST_N) begin
		bit  [7:0] FILL_CNT;
		
		if (!RST_N) begin
			BMMR <= BMMR_INIT;
			PPCR <= PPCR_INIT;
			AFLR <= AFLR_INIT;
			AFAR <= AFAR_INIT;
			AFDR <= AFDR_INIT;
			FBCR <= FBCR_INIT;
			
			ACK_N <= 1;
			FILL_EXEC <= 0;
			FILL_WR <= 0;
			FILL_CNT <= '0;
		end
		else begin
			if (!REG_CS_N && (!LWR_N || !UWR_N || !RD_N) && ACK_N) begin
				if (!LWR_N || !UWR_N) begin
					case ({A[3:1],1'b0})
						4'h0: begin
							if (!LWR_N) BMMR[ 7:0] <= DI[ 7:0] & BMMR_MASK[ 7:0];
							if (!UWR_N) BMMR[15:8] <= DI[15:8] & BMMR_MASK[15:8];
						end
						4'h2: begin
							if (!LWR_N) PPCR[ 7:0] <= DI[ 7:0] & PPCR_MASK[ 7:0];
							if (!UWR_N) PPCR[15:8] <= DI[15:8] & PPCR_MASK[15:8];
						end
						4'h4: begin
							if (!LWR_N) AFLR[ 7:0] <= DI[ 7:0] & AFLR_MASK;
						end
						4'h6: begin
							if (!LWR_N) AFAR[ 7:0] <= DI[ 7:0] & AFAR_MASK[ 7:0];
							if (!UWR_N) AFAR[15:8] <= DI[15:8] & AFAR_MASK[15:8];
						end
						4'h8: begin
							if (!LWR_N) AFDR[ 7:0] <= DI[ 7:0] & AFDR_MASK[ 7:0];
							if (!UWR_N) AFDR[15:8] <= DI[15:8] & AFDR_MASK[15:8];
							FILL_EXEC <= 1;
							FILL_CNT <= AFLR;
						end
						4'hA: begin
							if (!LWR_N) FBCR[ 7:0] <= DI[ 7:0] & FBCR_MASK[ 7:0];
							if (!UWR_N) FBCR[15:8] <= DI[15:8] & FBCR_MASK[15:8];
						end
					endcase
				end else if (!RD_N) begin
					case ({A[3:1],1'b0})
						4'h0: DO <= (BMMR & BMMR_MASK) | {~PAL,15'h0000};
						4'h2: DO <= PPCR & PPCR_MASK;
						4'h4: DO <= {8'h00,AFLR & AFLR_MASK};
						4'h6: DO <= AFAR & AFAR_MASK;
						4'h8: DO <= AFDR & AFDR_MASK;
						4'hA: DO <= {VBLK,HBLK,PEN,11'h000,FEN,FB_SEL};
						default: DO <= '0;
					endcase
				end
				ACK_N <= 0;
			end else if (!DRAM_CS_N && (!LWR_N || !UWR_N || !RD_N) && ACK_N && !FEN) begin
				if (!LWR_N | !UWR_N) begin
					
				end else if (!RD_N) begin
					DO <= FB_DRAW_Q;
				end
				ACK_N <= 0;
			end else if (!PAL_CS_N && (!LWR_N || !UWR_N || !RD_N) && ACK_N && PEN) begin
				if (!LWR_N | !UWR_N) begin
					
				end else if (!RD_N) begin
					DO <= PAL_IO_Q;
				end
				ACK_N <= 0;
			end else if (LWR_N && UWR_N && RD_N && !ACK_N) begin
				ACK_N <= 1;
			end
			
			FILL_WR <= 0;
			if (FILL_EXEC) begin
				if (DOT_CLK && EDCLK_CE) begin
					AFAR[ 7:0] <= AFAR[ 7:0] + 8'd1;
					FILL_CNT <= FILL_CNT - 8'd1;
					if (!FILL_CNT) FILL_EXEC <= 0;
					FILL_WR <= 1;
				end
			end
		end
	end
	
	assign FEN = FILL_EXEC;
	
	bit        DOT_CLK;
	bit  [8:0] H_CNT;
	bit  [8:0] V_CNT;
	always @(posedge CLK or negedge RST_N) begin
		bit        HSYNC_N_OLD;
		bit        VSYNC_N_OLD;
		
		if (!RST_N) begin
			DOT_CLK <= 0;
			H_CNT <= '0;
			V_CNT <= '0;
			HSYNC_N_OLD <= 1;
			VSYNC_N_OLD <= 1;
		end
		else begin
			if (EDCLK_CE) begin
				DOT_CLK <= ~DOT_CLK;
				HSYNC_N_OLD <= HSYNC_N;
				if (!HSYNC_N && HSYNC_N_OLD && !DOT_CLK) begin
					H_CNT <= 9'h1CD;
				end else if (H_CNT == 9'h16C && DOT_CLK) begin
					H_CNT <= 9'h1C9;
				end else if (DOT_CLK) begin
					H_CNT <= H_CNT + 9'd1;
				end
				
				VSYNC_N_OLD <= VSYNC_N;
				if (H_CNT == 9'h149 && DOT_CLK) begin
					if (!VSYNC_N && VSYNC_N_OLD) begin
						V_CNT <= 9'd234;
					end else if (V_CNT == 9'd260) begin
						V_CNT <= 9'd0;
					end else begin
						V_CNT <= V_CNT + 9'd1;
					end
				end
			end
		end
	end
	
	assign HBLK = ~(H_CNT >= 9'h00D & H_CNT <= 9'h168);
	assign VBLK = ~(V_CNT <= 9'd223);
	assign PEN = HBLK || VBLK || !BMMR.M[0];
	
	always @(posedge CLK or negedge RST_N) begin		
		if (!RST_N) begin
			FB_SEL <= 0;
		end
		else begin
			if (DOT_CLK && EDCLK_CE) begin
				if (VBLK) begin
					FB_SEL <= FBCR.FS;
				end
			end
		end
	end
	
	
	bit [16:0] LINE_LEAD;
	bit [15:0] PIX_DATA;
	bit        PP_BYTE;
	always @(posedge CLK or negedge RST_N) begin		
		if (!RST_N) begin
			LINE_LEAD <= '0;
			PIX_DATA <= '0;
		end
		else begin
			if (DOT_CLK && EDCLK_CE) begin
				if (H_CNT == 9'h000) begin
					LINE_LEAD <= {FB_DISP_Q,PPCR.SFT | &BMMR.M};
					PP_BYTE <= PPCR.SFT | &BMMR.M;
				end
				else if (H_CNT >= 9'h018 && H_CNT <= 9'h157)  begin
					case (BMMR.M)
						2'b00:;
						2'b01: begin
							LINE_LEAD <= LINE_LEAD + 17'd1;
							if (LINE_LEAD[0]) begin
								PIX_DATA <= FB_DISP_Q;
							end
						end
						2'b10:  begin
							PIX_DATA <= FB_DISP_Q;
							LINE_LEAD <= LINE_LEAD + 17'd2;
						end
						2'b11: begin
							PIX_DATA[15:8] <= PIX_DATA[15:8] - 8'd1;
							if (PIX_DATA[15:8] == 8'd0) begin
								PIX_DATA <= FB_DISP_Q;
								LINE_LEAD <= LINE_LEAD + 17'd2;
							end
						end
					endcase
				end
			end
		end
	end
	
	always_comb begin
		if (H_CNT == 9'h000) 
			FB_DISP_A = {8'h00,V_CNT[7:0]};
		else
			FB_DISP_A = LINE_LEAD[16:1];
	end
		
	wire  [7:0] PAL_DISP_A = LINE_LEAD[0] ? PIX_DATA[7:0] : PIX_DATA[15:8];
	bit  [15:0] PAL_DISP_Q;
	
	wire  [7:0] PAL_IO_A = A[8:1];
	wire [15:0] PAL_IO_D = DI;
	wire        PAL_IO_WE = ~LWR_N & ~UWR_N & ~PAL_CS_N & PEN;
	bit  [15:0] PAL_IO_Q;
	
	VDPPAL pal(
		.clock(CLK), 
		.address_a(PAL_DISP_A), 
		.data_a('0), 
		.wren_a(0), 
		.q_a(PAL_DISP_Q),
		
		.address_b(PAL_IO_A), 
		.data_b(PAL_IO_D), 
		.wren_b(PAL_IO_WE), 
		.q_b(PAL_IO_Q)
	);
	
	bit [15:0] PIX_COLOR;
	always @(posedge CLK or negedge RST_N) begin		
		if (!RST_N) begin
			PIX_COLOR <= '0;
		end
		else begin
			if (EDCLK_CE && DOT_CLK) begin
				if (H_CNT >= 9'h019 && H_CNT <= 9'h158)  begin
					case (BMMR.M)
						2'b00: PIX_COLOR <= '0;
						2'b01: PIX_COLOR <= PAL_DISP_Q;
						2'b10: PIX_COLOR <= PIX_DATA;
						2'b11: PIX_COLOR <= PAL_DISP_Q;
					endcase
				end
			end
		end
	end
	
	assign R = PIX_COLOR[4:0];
	assign G = PIX_COLOR[9:5];
	assign B = PIX_COLOR[14:10];
	assign YSO_N = ~(((~BMMR.PRI && (PIX_COLOR[15] || ~YS_N)) | (BMMR.PRI && ~PIX_COLOR[15])) && |BMMR.M);
	
	assign FB_DRAW_A = FILL_EXEC ? AFAR : A[16:1];
	assign FB_DRAW_D = FILL_EXEC ? AFDR : DI;
	assign FB_DRAW_WE = FILL_EXEC ? FILL_WR : {~UWR_N & ~DRAM_CS_N, ~LWR_N & ~DRAM_CS_N};
	assign FB_DRAW_Q = FB_SEL ? FB0_DI : FB1_DI;
	assign FB_DISP_Q = FB_SEL ? FB1_DI : FB0_DI;
	
	assign FB0_A  = FB_SEL ? FB_DRAW_A : FB_DISP_A;
	assign FB0_DO = FB_DRAW_D;
	assign FB0_WE = FB_SEL ? FB_DRAW_WE : 2'b00;
	
	assign FB1_A  = FB_SEL ? FB_DISP_A : FB_DRAW_A;
	assign FB1_DO = FB_DRAW_D;
	assign FB1_WE = FB_SEL ? 2'b00 : FB_DRAW_WE;
	
	assign HINT = HBLK;
	assign VINT = VBLK;
	
endmodule
