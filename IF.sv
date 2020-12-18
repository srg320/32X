module S32X_IF (
	input             CLK,
	input             RST_N,
	input             CE_R,
	input             CE_F,

	input             VCLK,
	input      [23:1] VA,
	input      [15:0] VDI,
	output     [15:0] VDO,
	input             AS_N,
	output            DTACK_N,
	input             LWR_N,
	input             UWR_N,
	input             CE0_N,
	input             CAS0_N,
	input             CAS2_N,
	input             ASEL_N,
	input             VRES_N,
	input             MRES_N,
	input             CART_N,

	input      [17:1] SHA,
	input      [15:0] SHDI,
	output     [15:0] SHDO,
	input             SHCS0M_N,
	input             SHCS0S_N,
	input             SHCS1_N,
	input             SHCS2_N,
	input             SHBS_N,
	input             SHRD_WR_N,
	input             SHRD_N,
	input             SHDQMLL_N,
	input             SHDQMLU_N,
	output            SHWAIT_N,
	output            SHRES_N,
	output            SHDREQ0_N,
	output            SHDREQ1_N,
	output      [3:1] SHMIRL_N,
	output      [3:1] SHSIRL_N,
	
	output    [21:19] OVA,
	output            SEL,
	
	input      [15:0] CDI,
	output     [15:0] CDO,
	output            CASEL_N,
	output            CLWR_N,
	output            CUWR_N,
	output            CCE0_N,
	output            CCAS0_N,
	output            CCAS2_N,
	
	output     [17:1] VDP_A,
	input      [15:0] VDP_DI,
	output     [15:0] VDP_DO,
	output            VDP_RD_N,
	output            VDP_LWR_N,
	output            VDP_UWR_N,
	input             VDP_ACK_N,
	output            VDP_DRAM_CS_N,
	output            VDP_REG_CS_N,
	output            VDP_PAL_CS_N,
//	output            VDP_RW,
//	output            VDP_DIR,
//	output            VDP_ACCS,
//	input             VDP_VACK,
	input             VDP_VINT,
	input             VDP_HINT,
//	output            VDP_C23,
	
	output     [15:0] PWM_L,
	output     [15:0] PWM_R,
	
	input             ROM_WAIT
);
	import S32X_PKG::*;

	ADCR_t     ADCR;
	ICR_t      ICR;
	BSR_t      BSR;
	DCR_t      DCR;
	DSAR_t     DSAR;
	DDAR_t     DDAR;
	DLR_t      DLR;
	FFDR_t     FFDR;
	STVR_t     STVR;
	CPxR_t     CP0R;
	CPxR_t     CP1R;
	CPxR_t     CP2R;
	CPxR_t     CP3R;
	CPxR_t     CP4R;
	CPxR_t     CP5R;
	CPxR_t     CP6R;
	CPxR_t     CP7R;
	PWMCR_t    PWMCR;
	CYCR_t     CYCR;
	PWR_t      LPWR;
	PWR_t      RPWR;
	IMR_t      IMMR;
	IMR_t      IMSR;
	STBR_t     STBR;
	HCNTR_t    HCNTR;
	ICLR_t     RESICLR;
	ICLR_t     VICLR;
	ICLR_t     HICLR;
	ICLR_t     CMDICLR;
	ICLR_t     PWMICLR;
	
	bit        VRES_INT;
	bit        V_INTM;
	bit        H_INTM;
	bit        PWM_INTM;
	bit        V_INTS;
	bit        H_INTS;
	bit        PWM_INTS;
	
	bit  [7:0] LINE_CNT;
	
	bit [15:0] FIFO_BUF[8];
	bit  [2:0] FIFO_WR_POS;
	bit  [2:0] FIFO_RD_POS;
	bit  [2:0] FIFO_AMOUNT;
	bit        FIFO_FULL;
	bit        FIFO_EMPTY;
	bit        FIFO_REQ;
	
	bit [15:0] CYC_CNT;
	bit  [3:0] TIME_CNT;
	bit [11:0] LPW_BUF[3];
	bit [11:0] RPW_BUF[3];
	bit  [1:0] LPW_BUF_POS;
	bit  [1:0] RPW_BUF_POS;
	bit        LPW_SET;
	bit        RPW_SET;
	bit        PWM_REQ;
	
	bit [15:0] SHROM_Q;
	SHROM shrom(.clock(CLK), .address({SHCS0M_N,SHA[10:1]}), .q(SHROM_Q));

	wire MDROM_WE = VA[23:2] == 24'h000070>>2 & (~LWR_N | ~UWR_N) & ~AS_N & ADCR.ADEN;
	bit [15:0] MDROM_Q;
	MDROM mdrom(.clock(CLK), .address(VA[7:1]), .data(VDI), .wren(MDROM_WE), .q(MDROM_Q));
	
	bit [15:0] MD_REG_DO;
	bit        MD_REG_DTACK_N;
	bit        MD_ROM_GRANT;
	bit [15:0] SH_REG_DO;
	bit        SH_ROM_WAIT;
	bit        SH_ROM_GRANT;
	
	typedef enum bit [6:0] {
		RS_IDLE    = 7'b0000001,  
		RS_MD_WAIT = 7'b0000010, 
		RS_MD_READ = 7'b0000100, 
		RS_SH_WAIT = 7'b0001000, 
		RS_SH_READ = 7'b0010000,
		RS_MD_END  = 7'b0100000,
		RS_SH_END  = 7'b1000000
	} ROMState_t;
	ROMState_t ROM_ST;
	
	wire MD_SYSREG_SEL = VA[23:7] == 24'hA15100>>7 & ~AS_N;		//A15100-A1517F
	wire MD_32XID_SEL  = VA[23:2] == 24'hA130EC>>2 & ~AS_N;		//A130FC-A130FF
	wire MD_BIOS_SEL   = VA[23:8] == 24'h000000>>8 & ~AS_N & ADCR.ADEN;	//000000-0000FF
	
	wire SH_SLV = ~SHCS0S_N;
	wire SH_BIOS_SEL = (~SHCS0M_N | ~SHCS0S_N) & SHA[17:14] == 4'b0000;	//00000000-00003FFF,20000000-20003FFF
	wire SH_SYSREG_SEL = (~SHCS0M_N | ~SHCS0S_N) & SHA[17:8] == 10'h040;	//00004000-000040FF,20004000-200040FF										
	
	always @(posedge CLK or negedge RST_N) begin
		bit [15:0] DLR_NEXT;
		bit        FIFO_INC_AMOUNT;
		bit        FIFO_DEC_AMOUNT;
		bit        VDP_HINT_OLD;
		bit        VDP_VINT_OLD;
		bit [15:0] CYC_CNT_NEXT;
		bit  [3:0] TIME_CNT_NEXT;
		
		if (!RST_N) begin
			ADCR <= ADCR_INIT;
			ICR  <= ICR_INIT;
			BSR  <= BSR_INIT;
			DCR  <= DCR_INIT;
			DSAR <= DSAR_INIT;
			DDAR <= DDAR_INIT;
			DLR  <= DLR_INIT;
//			FFDR <= FFDR_INIT;
			STVR <= STVR_INIT;
			CP0R <= CPxR_INIT;
			CP1R <= CPxR_INIT;
			CP2R <= CPxR_INIT;
			CP3R <= CPxR_INIT;
			CP4R <= CPxR_INIT;
			CP5R <= CPxR_INIT;
			CP6R <= CPxR_INIT;
			CP7R <= CPxR_INIT;
			PWMCR <= PWMCR_INIT;
			CYCR <= CYCR_INIT;
			LPWR <= PWR_INIT;
			RPWR <= PWR_INIT;
			IMMR <= IMR_INIT;
			IMSR <= IMR_INIT;
			STBR <= STBR_INIT;
			HCNTR <= HCNTR_INIT;
			ADCR.REN <= 1;
			
			MD_REG_DO <= '0;
			MD_REG_DTACK_N <= 1;
			SH_REG_DO <= '0;
			
//			FIFO_WR <= 0;
//			FIFO_RD <= 0;
			FIFO_BUF <= '{8{'0}};
			FIFO_WR_POS <= '0;
			FIFO_RD_POS <= '0;
			FIFO_AMOUNT <= '0;
			FIFO_FULL <= 0;
			FIFO_EMPTY <= 0;
			FIFO_REQ <= 0;
			
			LINE_CNT <= '0;
			V_INTM <= 0; 
			V_INTS <= 0;
			H_INTM <= 0;
			H_INTS <= 0;
			VRES_INT <= 0;
			VDP_HINT_OLD <= 0;
			VDP_VINT_OLD <= 0;
			PWM_INTM <= 0;
			PWM_INTS <= 0;
			LPW_BUF_POS <= '0;
			RPW_BUF_POS <= '0;
			LPW_SET <= 0;
			RPW_SET <= 0;
			CYC_CNT <= '0;
			TIME_CNT <= '0;
			PWM_REQ <= 0;
		end
		else begin
			DLR_NEXT = DLR - 16'd1;
			FIFO_INC_AMOUNT = 0;
			FIFO_DEC_AMOUNT = 0;
			if (MD_SYSREG_SEL & (!LWR_N | !UWR_N | !CAS0_N) && MD_REG_DTACK_N) begin
				if (!LWR_N | !UWR_N) begin
					case ({VA[5:1],1'b0})
						6'h00: begin
							if (!LWR_N) ADCR[ 7:0] <= VDI[ 7:0] & ADCR_MASK[ 7:0];
							if (!UWR_N) ADCR[15:8] <= VDI[15:8] & ADCR_MASK[15:8];
						end
						6'h02: begin
							if (!LWR_N) ICR[ 7:0] <= VDI[ 7:0] & ICR_MASK[ 7:0];
							if (!UWR_N) ICR[15:8] <= VDI[15:8] & ICR_MASK[15:8];
						end
						6'h04: begin
							if (!LWR_N) BSR[ 7:0] <= VDI[ 7:0] & BSR_MASK[ 7:0];
							if (!UWR_N) BSR[15:8] <= VDI[15:8] & BSR_MASK[15:8];
						end
						6'h06: begin
							if (!LWR_N) DCR[ 7:0] <= VDI[ 7:0] & DCR_MASK[ 7:0];
							if (!UWR_N) DCR[15:8] <= VDI[15:8] & DCR_MASK[15:8];
							if (!LWR_N && !VDI[2]) begin
								FIFO_WR_POS <= '0;
								FIFO_RD_POS <= '0;
								FIFO_AMOUNT <= '0;
								FIFO_FULL <= 0;
								FIFO_EMPTY <= 0;
								FIFO_REQ <= 0;
							end
						end
						6'h08: begin
							DSAR[23:16] <= VDI[ 7:0] & DSAR_MASK[23:16];
						end
						6'h0A: begin
							DSAR[15:0]  <= VDI & DSAR_MASK[15:0];
						end
						6'h0C: begin
							DDAR[23:16] <= VDI[ 7:0] & DDAR_MASK[23:16];
						end
						6'h0E: begin
							DDAR[15:0]  <= VDI & DDAR_MASK[15:0];
						end
						6'h10: begin
							DLR         <= VDI & DLR_MASK;
						end
						6'h12: begin
//							FFDR        <= VDI & FFDR_MASK;
							if (DCR.M68S) begin
								DLR <= DLR_NEXT;
								if (!DLR_NEXT) DCR.M68S <= 0;
//								FIFO_WR <= 1;
								FIFO_BUF[FIFO_WR_POS] <= VDI;
								FIFO_WR_POS <= FIFO_WR_POS + 3'd1;
								FIFO_INC_AMOUNT = 1;
							end
						end
						6'h1A: begin
							if (!LWR_N) STVR[ 7:0] <= VDI[ 7:0] & STVR_MASK[ 7:0];
							if (!UWR_N) STVR[15:8] <= VDI[15:8] & STVR_MASK[15:8];
						end
						6'h20: begin
							if (!LWR_N) CP0R[ 7:0] <= VDI[ 7:0] & CPxR_MASK[ 7:0];
							if (!UWR_N) CP0R[15:8] <= VDI[15:8] & CPxR_MASK[15:8];
						end
						6'h22: begin
							if (!LWR_N) CP1R[ 7:0] <= VDI[ 7:0] & CPxR_MASK[ 7:0];
							if (!UWR_N) CP1R[15:8] <= VDI[15:8] & CPxR_MASK[15:8];
						end
						6'h24: begin
							if (!LWR_N) CP2R[ 7:0] <= VDI[ 7:0] & CPxR_MASK[ 7:0];
							if (!UWR_N) CP2R[15:8] <= VDI[15:8] & CPxR_MASK[15:8];
						end
						6'h26: begin
							if (!LWR_N) CP3R[ 7:0] <= VDI[ 7:0] & CPxR_MASK[ 7:0];
							if (!UWR_N) CP3R[15:8] <= VDI[15:8] & CPxR_MASK[15:8];
						end
						6'h28: begin
							if (!LWR_N) CP4R[ 7:0] <= VDI[ 7:0] & CPxR_MASK[ 7:0];
							if (!UWR_N) CP4R[15:8] <= VDI[15:8] & CPxR_MASK[15:8];
						end
						6'h2A: begin
							if (!LWR_N) CP5R[ 7:0] <= VDI[ 7:0] & CPxR_MASK[ 7:0];
							if (!UWR_N) CP5R[15:8] <= VDI[15:8] & CPxR_MASK[15:8];
						end
						6'h2C: begin
							if (!LWR_N) CP6R[ 7:0] <= VDI[ 7:0] & CPxR_MASK[ 7:0];
							if (!UWR_N) CP6R[15:8] <= VDI[15:8] & CPxR_MASK[15:8];
						end
						6'h2E: begin
							if (!LWR_N) CP7R[ 7:0] <= VDI[ 7:0] & CPxR_MASK[ 7:0];
							if (!UWR_N) CP7R[15:8] <= VDI[15:8] & CPxR_MASK[15:8];
						end
						6'h30: begin
							if (!LWR_N) PWMCR[ 7:0] <= VDI[ 7:0] & PWMCR_MASK[ 7:0];
						end
						6'h32: begin
							if (!LWR_N) CYCR[ 7:0] <= VDI[ 7:0] & CYCR_MASK[ 7:0];
							if (!UWR_N) CYCR[11:8] <= VDI[11:8] & CYCR_MASK[11:8];
						end
						6'h34: begin
							if (!LWR_N) LPWR[ 7:0] <= VDI[ 7:0] & PWR_MASK[ 7:0];
							if (!UWR_N) LPWR[13:8] <= VDI[13:8] & PWR_MASK[13:8];
							LPW_SET <= |PWMCR.LMD;
						end
						6'h36: begin
							if (!LWR_N) RPWR[ 7:0] <= VDI[ 7:0] & PWR_MASK[ 7:0];
							if (!UWR_N) RPWR[13:8] <= VDI[13:8] & PWR_MASK[13:8];
							RPW_SET <= |PWMCR.RMD;
						end
						6'h38: begin
							if (!LWR_N) LPWR[ 7:0] <= VDI[ 7:0] & PWR_MASK[ 7:0];
							if (!UWR_N) LPWR[13:8] <= VDI[13:8] & PWR_MASK[13:8];
							if (!LWR_N) RPWR[ 7:0] <= VDI[ 7:0] & PWR_MASK[ 7:0];
							if (!UWR_N) RPWR[13:8] <= VDI[13:8] & PWR_MASK[13:8];
							LPW_SET <= |PWMCR.LMD;
							RPW_SET <= |PWMCR.RMD;
						end
						default:;
					endcase
				end else if (!CAS0_N) begin
					case ({VA[5:1],1'b0})
						6'h00: MD_REG_DO <= ADCR & ADCR_MASK;
						6'h02: MD_REG_DO <= ICR & ICR_MASK;
						6'h04: MD_REG_DO <= BSR & BSR_MASK;
						6'h06: MD_REG_DO <= (DCR & DCR_MASK) | {8'h00,FIFO_FULL,7'h00};
						6'h08: MD_REG_DO <= {8'h00,DSAR[23:16] & DSAR_MASK[23:16]};
						6'h0A: MD_REG_DO <= DSAR[15:0] & DSAR_MASK[15:0];
						6'h0C: MD_REG_DO <= {8'h00,DDAR[23:16] & DDAR_MASK[23:16]};
						6'h0E: MD_REG_DO <= DDAR[15:0] & DDAR_MASK[15:0];
						6'h10: MD_REG_DO <= DLR & DLR_MASK;
						6'h12: MD_REG_DO <= '0; //write only
						6'h1A: MD_REG_DO <= STVR & STVR_MASK;
						6'h20: MD_REG_DO <= CP0R;
						6'h22: MD_REG_DO <= CP1R;
						6'h24: MD_REG_DO <= CP2R;
						6'h26: MD_REG_DO <= CP3R;
						6'h28: MD_REG_DO <= CP4R;
						6'h2A: MD_REG_DO <= CP5R;
						6'h2C: MD_REG_DO <= CP6R;
						6'h2E: MD_REG_DO <= CP7R;
						6'h30: MD_REG_DO <= PWMCR;
						6'h32: MD_REG_DO <= {4'h0,CYCR[11:0]};
						6'h34: MD_REG_DO <= {LPW_BUF_POS==2'd2,LPW_BUF_POS==2'd0,14'h0000};
						6'h36: MD_REG_DO <= {RPW_BUF_POS==2'd2,RPW_BUF_POS==2'd0,14'h0000};
						6'h38: MD_REG_DO <= {LPW_BUF_POS==2'd2,LPW_BUF_POS==2'd0,14'h0000};
						default: MD_REG_DO <= '0;
					endcase
				end
				MD_REG_DTACK_N <= 0;
				
			end else if (MD_32XID_SEL & (!LWR_N | !UWR_N | !CAS0_N) && MD_REG_DTACK_N) begin
				if (!CAS0_N) begin
					MD_REG_DO <= !VA[1] ? S32X_ID[31:16] : S32X_ID[15:0];
				end
				MD_REG_DTACK_N <= 0;
				
			end else if (MD_BIOS_SEL & (!LWR_N | !UWR_N | !CAS0_N) && MD_REG_DTACK_N) begin
				if (!CAS0_N) begin
					MD_REG_DO <= MDROM_Q;
				end
				MD_REG_DTACK_N <= 0;

			end else if (AS_N && !MD_REG_DTACK_N) begin
				MD_REG_DTACK_N <= 1;
			end
			
			if (SH_SYSREG_SEL	&& SHBS_N) begin
				if (!SHRD_WR_N && (!SHDQMLL_N || !SHDQMLU_N) && CE_F) begin
					case ({SHA[5:1],1'b0})
						6'h00: begin
							if (!SHDQMLL_N && !SH_SLV) IMMR[ 3:0] <= SHDI[ 3:0] & IMR_MASK[ 3:0];
							if (!SHDQMLL_N &&  SH_SLV) IMSR[ 3:0] <= SHDI[ 3:0] & IMR_MASK[ 3:0];
							if (!SHDQMLL_N)            IMMR[ 7:4] <= SHDI[ 7:4] & IMR_MASK[ 7:4];
							if (!SHDQMLU_N) ADCR.FM <= SHDI[15];
						end
						6'h02: begin
							if (!SHDQMLL_N) STBR[ 7:0] <= SHDI[ 7:0] & STBR_MASK[ 7:0];
							if (!SHDQMLU_N) STBR[15:8] <= SHDI[15:8] & STBR_MASK[15:8];
						end
						6'h04: begin
							if (!SHDQMLL_N) HCNTR[ 7:0] <= SHDI[ 7:0] & HCNTR_MASK[ 7:0];
						end
						6'h06:;	//Read only
						6'h08:;	//Read only
						6'h0A:;	//Read only
						6'h0C:;	//Read only
						6'h0E:;	//Read only
						6'h10:;	//Read only
						6'h12:;	//Read only
						6'h14: VRES_INT <= 0;
						6'h16: if (!SH_SLV) V_INTM <= 0; 
						       else         V_INTS <= 0;
						6'h18: if (!SH_SLV) H_INTM <= 0;
						       else         H_INTS <= 0;
						6'h1A: if (!SH_SLV) ICR.INTM <= 0;
						       else         ICR.INTS <= 0;
						6'h1C: if (!SH_SLV) PWM_INTM <= 0;
						       else         PWM_INTS <= 0;
						6'h20: begin
							if (!SHDQMLL_N) CP0R[ 7:0] <= SHDI[ 7:0] & CPxR_MASK[ 7:0];
							if (!SHDQMLU_N) CP0R[15:8] <= SHDI[15:8] & CPxR_MASK[15:8];
						end
						6'h22: begin
							if (!SHDQMLL_N) CP1R[ 7:0] <= SHDI[ 7:0] & CPxR_MASK[ 7:0];
							if (!SHDQMLU_N) CP1R[15:8] <= SHDI[15:8] & CPxR_MASK[15:8];
						end
						6'h24: begin
							if (!SHDQMLL_N) CP2R[ 7:0] <= SHDI[ 7:0] & CPxR_MASK[ 7:0];
							if (!SHDQMLU_N) CP2R[15:8] <= SHDI[15:8] & CPxR_MASK[15:8];
						end
						6'h26: begin
							if (!SHDQMLL_N) CP3R[ 7:0] <= SHDI[ 7:0] & CPxR_MASK[ 7:0];
							if (!SHDQMLU_N) CP3R[15:8] <= SHDI[15:8] & CPxR_MASK[15:8];
						end
						6'h28: begin
							if (!SHDQMLL_N) CP4R[ 7:0] <= SHDI[ 7:0] & CPxR_MASK[ 7:0];
							if (!SHDQMLU_N) CP4R[15:8] <= SHDI[15:8] & CPxR_MASK[15:8];
						end
						6'h2A: begin
							if (!SHDQMLL_N) CP5R[ 7:0] <= SHDI[ 7:0] & CPxR_MASK[ 7:0];
							if (!SHDQMLU_N) CP5R[15:8] <= SHDI[15:8] & CPxR_MASK[15:8];
						end
						6'h2C: begin
							if (!SHDQMLL_N) CP6R[ 7:0] <= SHDI[ 7:0] & CPxR_MASK[ 7:0];
							if (!SHDQMLU_N) CP6R[15:8] <= SHDI[15:8] & CPxR_MASK[15:8];
						end
						6'h2E: begin
							if (!SHDQMLL_N) CP7R[ 7:0] <= SHDI[ 7:0] & CPxR_MASK[ 7:0];
							if (!SHDQMLU_N) CP7R[15:8] <= SHDI[15:8] & CPxR_MASK[15:8];
						end
						6'h30: begin
							if (!SHDQMLL_N) PWMCR[ 7:0] <= SHDI[ 7:0] & PWMCR_MASK[ 7:0];
							if (!SHDQMLU_N) PWMCR[15:8] <= SHDI[15:8] & PWMCR_MASK[15:8];
						end
						6'h32: begin
							if (!SHDQMLL_N) CYCR[ 7:0] <= SHDI[ 7:0] & CYCR_MASK[ 7:0];
							if (!SHDQMLU_N) CYCR[11:8] <= SHDI[11:8] & CYCR_MASK[11:8];
						end
						6'h34: begin
							if (!SHDQMLL_N) LPWR[ 7:0] <= SHDI[ 7:0] & PWR_MASK[ 7:0];
							if (!SHDQMLU_N) LPWR[13:8] <= SHDI[13:8] & PWR_MASK[13:8];
							LPW_SET <= 1;
						end
						6'h36: begin
							if (!SHDQMLL_N) RPWR[ 7:0] <= SHDI[ 7:0] & PWR_MASK[ 7:0];
							if (!SHDQMLU_N) RPWR[13:8] <= SHDI[13:8] & PWR_MASK[13:8];
							RPW_SET <= 1;
						end
						6'h38: begin
							if (!SHDQMLL_N) LPWR[ 7:0] <= SHDI[ 7:0] & PWR_MASK[ 7:0];
							if (!SHDQMLU_N) LPWR[13:8] <= SHDI[13:8] & PWR_MASK[13:8];
							if (!SHDQMLL_N) RPWR[ 7:0] <= SHDI[ 7:0] & PWR_MASK[ 7:0];
							if (!SHDQMLU_N) RPWR[13:8] <= SHDI[13:8] & PWR_MASK[13:8];
							LPW_SET <= 1;
							RPW_SET <= 1;
						end
						default:;
					endcase
				end else if (SHRD_WR_N && !SHRD_N && CE_R) begin
					case ({SHA[5:1],1'b0})
						6'h00: SH_REG_DO <= { {ADCR.FM,5'b00000,ADCR.ADEN,CART_N}, {IMMR[7:4],(!SH_SLV ? IMMR[3:0] : IMSR[3:0])} & IMR_MASK[7:0] };
						6'h02: SH_REG_DO <= '0;	//Write only
						6'h04: SH_REG_DO <= {8'h00,HCNTR};
						6'h06: SH_REG_DO <= {FIFO_FULL,FIFO_EMPTY,11'h000,DCR.M68S,1'b0,DCR.RV};
						6'h08: SH_REG_DO <= {8'h00,DSAR[23:16] & DSAR_MASK[23:16]};
						6'h0A: SH_REG_DO <= DSAR[15:0] & DSAR_MASK[15:0];
						6'h0C: SH_REG_DO <= {8'h00,DDAR[23:16] & DDAR_MASK[23:16]};
						6'h0E: SH_REG_DO <= DDAR[15:0] & DDAR_MASK[15:0];
						6'h10: SH_REG_DO <= DLR & DLR_MASK[15:0];
						6'h12: begin
							SH_REG_DO <= FIFO_BUF[FIFO_RD_POS]; 
//							FIFO_RD <= 1;
							FIFO_RD_POS <= FIFO_RD_POS + 3'd1;
							FIFO_DEC_AMOUNT = 1;
						end
						6'h20: SH_REG_DO <= CP0R;
						6'h22: SH_REG_DO <= CP1R;
						6'h24: SH_REG_DO <= CP2R;
						6'h26: SH_REG_DO <= CP3R;
						6'h28: SH_REG_DO <= CP4R;
						6'h2A: SH_REG_DO <= CP5R;
						6'h2C: SH_REG_DO <= CP6R;
						6'h2E: SH_REG_DO <= CP7R;
						6'h30: SH_REG_DO <= PWMCR & PWMCR_MASK;
						6'h32: SH_REG_DO <= {4'h0,CYCR[11:0]};
						6'h34: SH_REG_DO <= LPWR & PWR_MASK;
						6'h36: SH_REG_DO <= RPWR & PWR_MASK;
						6'h38: SH_REG_DO <= LPWR & PWR_MASK;
						default: SH_REG_DO <= '0;
					endcase
				end
			end else if (SH_BIOS_SEL && SHBS_N) begin
				if (SHRD_WR_N && !SHRD_N && CE_F) begin
					SH_REG_DO <= SHROM_Q;
				end
			end
			
			VDP_HINT_OLD <= VDP_HINT;
			if (VDP_HINT && !VDP_HINT_OLD) begin
				LINE_CNT <= LINE_CNT + 3'd1;
				if (LINE_CNT == HCNTR) begin
					LINE_CNT <= '0;
					if (IMMR.H) H_INTM <= 1;
					if (IMSR.H) H_INTS <= 1;
				end
			end
			
			VDP_VINT_OLD <= VDP_VINT;
			if (VDP_VINT && !VDP_VINT_OLD) begin
				if (IMMR.V) V_INTM <= 1;
				if (IMSR.V) V_INTS <= 1;
			end
			
			if (FIFO_INC_AMOUNT && !FIFO_DEC_AMOUNT) begin
				if (FIFO_AMOUNT == 3'd7) FIFO_FULL <= 1;
				else FIFO_AMOUNT <= FIFO_AMOUNT + 3'd1;
				FIFO_EMPTY <= 0;
				if (FIFO_AMOUNT[1:0] == 2'd3) FIFO_REQ <= 1;
			end else if (!FIFO_INC_AMOUNT && FIFO_DEC_AMOUNT) begin
				if (FIFO_AMOUNT == 3'd0) FIFO_EMPTY <= 1;
				else FIFO_AMOUNT <= FIFO_AMOUNT - 3'd1;
				FIFO_FULL <= 0;
				if (FIFO_REQ) FIFO_REQ <= 0;
			end
			
			if (PWMCR.LMD || PWMCR.RMD) begin 
				CYC_CNT_NEXT = CYC_CNT - 12'd1;
			end else begin 
				CYC_CNT_NEXT = CYC_CNT;
			end
			TIME_CNT_NEXT = TIME_CNT - 4'd1;
			if (CE_R) begin
				CYC_CNT <= CYC_CNT_NEXT;
				if (!CYC_CNT_NEXT && (PWMCR.LMD || PWMCR.RMD)) begin
					CYC_CNT <= CYCR;
					PWM_REQ <= 0;
					TIME_CNT <= TIME_CNT_NEXT;
					if (!TIME_CNT_NEXT) begin
						TIME_CNT <= PWMCR.TM;
						PWM_INTM <= IMMR.PWM;
						PWM_INTS <= IMSR.PWM;
						PWM_REQ <= PWMCR.RTP;
					end
					if (LPW_BUF_POS > 2'd0) LPW_BUF_POS <= LPW_BUF_POS - 2'd1;
					else LPWR.EMPTY <= 1;
					LPWR.FULL <= 0;
					if (RPW_BUF_POS > 2'd0) RPW_BUF_POS <= RPW_BUF_POS - 2'd1;
					else RPWR.EMPTY <= 1;
					RPWR.FULL <= 0;
				end else if (LPW_SET || RPW_SET) begin
					if (LPW_SET) begin
						LPW_SET <= 0;
						LPW_BUF[LPW_BUF_POS] <= LPWR.PW;
						if (LPW_BUF_POS < 2'd2) LPW_BUF_POS <= LPW_BUF_POS + 2'd1;
						else LPWR.FULL <= 1;
						LPWR.EMPTY <= 0;
					end
					if (RPW_SET) begin
						RPW_SET <= 0;
						RPW_BUF[RPW_BUF_POS] <= RPWR.PW;
						if (RPW_BUF_POS < 2'd2) RPW_BUF_POS <= RPW_BUF_POS + 2'd1;
						else RPWR.FULL <= 1;
						RPWR.EMPTY <= 0;
					end
				end
			end
		end
	end
	assign PWM_L = {LPW_BUF[LPW_BUF_POS] - 12'h800,4'h0};
	assign PWM_R = {RPW_BUF[RPW_BUF_POS] - 12'h800,4'h0};
	
	wire MD_32XROM_SEL = VA[23:16] >= 8'h88 & VA[23:16] <= 8'h9F & ~AS_N & ADCR.ADEN;		//880000-9FFFFF
	wire SH_ROM_SEL = ~SHCS1_N;		//02000000-03FFFFFF,22000000-23FFFFFF
	
	bit [15:0] MD_ROM_DO;
	bit        MD_ROM_DTACK_N;
	bit [15:0] SH_ROM_DO;
	bit S32X_CE0;
	always @(posedge CLK or negedge RST_N) begin
		bit        ROM_WAIT_SYNC;
		bit        MD_ROM_READ;
		bit        SH_ROM_READ;
		
		if (!RST_N) begin
			ROM_ST <= RS_IDLE;
			MD_ROM_DTACK_N <= 1;
			SH_ROM_WAIT <= 0;
			SH_ROM_GRANT <= 0;
			S32X_CE0 <= 0;
		end
		else begin
			ROM_WAIT_SYNC <= ROM_WAIT;
			if (SH_ROM_SEL && !SHBS_N && CE_F) begin
				SH_ROM_WAIT <= 1;
			end
			
			case (ROM_ST)
				RS_IDLE: begin
					if (SH_ROM_WAIT && !DCR.RV) begin
						S32X_CE0 <= 1;
						SH_ROM_GRANT <= 1;
						ROM_ST <= RS_SH_WAIT;
					end else if (MD_32XROM_SEL & (!LWR_N | !UWR_N | !CAS0_N)) begin
						S32X_CE0 <= 1;
						ROM_ST <= RS_MD_WAIT;
					end
				end
				
				RS_SH_WAIT: begin
					if (ROM_WAIT_SYNC) begin
						ROM_ST <= RS_SH_READ;
					end
				end
				
				RS_SH_READ: begin
					if (!ROM_WAIT_SYNC) begin
						SH_ROM_DO <= CDI;
						SH_ROM_WAIT <= 0;
						S32X_CE0 <= 0;
						ROM_ST <= RS_SH_END;
					end
				end
				
				RS_SH_END: begin
					if (SHRD_N && SHDQMLL_N && SHDQMLU_N) begin
						SH_ROM_GRANT <= 0;
						ROM_ST <= RS_IDLE;
					end
				end
				
				RS_MD_WAIT: begin
					if (ROM_WAIT_SYNC) begin
						ROM_ST <= RS_MD_READ;
					end
				end
				
				RS_MD_READ: begin
					if (!ROM_WAIT_SYNC) begin
						MD_ROM_DO <= CDI;
						MD_ROM_DTACK_N <= 0;
						S32X_CE0 <= 0;
						ROM_ST <= RS_MD_END;
					end
				end
				
				RS_MD_END: begin
					if (AS_N && !MD_ROM_DTACK_N) begin
						MD_ROM_DTACK_N <= 1;
						ROM_ST <= RS_IDLE;
					end
				end
			endcase
		end
	end
	
	bit        VDP_DTACK_N;
	wire MD_VDPREG_SEL = VA[23:7] == 24'hA15180>>7 & ~AS_N & ~ADCR.FM;		//A15180-A151FF
	wire MD_VDPPAL_SEL = VA[23:9] == 24'hA15200>>9 & ~AS_N & ~ADCR.FM;		//A15200-A153FF
	wire MD_VDPDRAM_SEL = VA[23:18] == 24'h840000>>18 & ~AS_N & ~ADCR.FM;		//840000-87FFFF
	always @(posedge CLK or negedge RST_N) begin
		bit        MD_VDP_ACCESS;
		bit        SH_VDP_ACCESS;
		
		if (!RST_N) begin
			VDP_RD_N <= 1;
			VDP_LWR_N <= 1;
			VDP_UWR_N <= 1;
			VDP_REG_CS_N <= 1;
			VDP_PAL_CS_N <= 1;
			VDP_DRAM_CS_N <= 1;
			VDP_DO <= '0;
			VDP_DTACK_N <= 1;
			MD_VDP_ACCESS <= 0;
		end
		else begin
			if ((MD_VDPREG_SEL || MD_VDPPAL_SEL) & (!LWR_N || !UWR_N || !CAS0_N) && VDP_DTACK_N && !MD_VDP_ACCESS) begin
				VDP_A <= VA[17:1];
				VDP_DO <= VDI;
				VDP_REG_CS_N <= ~MD_VDPREG_SEL;
				VDP_PAL_CS_N <= ~MD_VDPPAL_SEL;
				VDP_DRAM_CS_N <= ~MD_VDPDRAM_SEL;
				VDP_RD_N <= CAS0_N;
				VDP_LWR_N <= LWR_N;
				VDP_UWR_N <= UWR_N;

				MD_VDP_ACCESS <= 1;
			
			end else if ((MD_VDPREG_SEL || MD_VDPPAL_SEL) && MD_VDP_ACCESS) begin
				if (!VDP_ACK_N) begin
					VDP_RD_N <= 1;
					VDP_LWR_N <= 1;
					VDP_UWR_N <= 1;
					VDP_REG_CS_N <= 1;
					VDP_PAL_CS_N <= 1;
					VDP_DRAM_CS_N <= 1;
					VDP_DTACK_N <= 0;
					MD_VDP_ACCESS <= 0;
				end
				
			end else if (AS_N && !VDP_DTACK_N) begin
				VDP_DTACK_N <= 1;
			end
			
//			if (SH_ROM_SEL && !SH_ROM_READ && !MD_ROM_GRANT) begin
//				if (CE_F) begin
//					if (!SHBS_N) begin
//						SH_ROM_GRANT <= ~DCR.RV;
//						SH_ROM_WAIT <= 1;
//					end else if (SHRD_WR_N && !SHRD_N && !DCR.RV && ROM_WAIT_SYNC) begin
//						SH_ROM_WAIT <= 1;
//						SH_ROM_READ <= 1;
//					end
//				end
//			end else if (SH_ROM_SEL && SH_ROM_READ) begin
//				if (!ROM_WAIT_SYNC) begin
//					SH_DO <= CDI;
//					SH_ROM_GRANT <= 0;
//					SH_ROM_READ <= 0;
//					SH_ROM_WAIT <= 0;
//				end
//			end
		end
	end
	
	
	always_comb begin
		if (!ADCR.ADEN || DCR.RV) 
			OVA = VA[21:19];
		else if (VA[21:19] == 3'b001) 	//880000-8FFFFF->000000-07FFFF
			OVA = 3'b000;
		else if (VA[21:19] ==? 3'b01?) 	//900000-9FFFFF->x00000-xFFFFF (x=0..3)
			OVA = {BSR.BK,VA[19]};
		else
			OVA = VA[21:19];
		
		if (MD_SYSREG_SEL || MD_32XID_SEL)
			VDO = MD_REG_DO;
		else if (MD_BIOS_SEL)
			VDO = MDROM_Q;
		else if (MD_32XROM_SEL)
			VDO = MD_ROM_DO;
		else if (MD_VDPREG_SEL || MD_VDPPAL_SEL)
			VDO = VDP_DI;
		else
			VDO = CDI;
	end
	
	assign DTACK_N = MD_REG_DTACK_N & MD_ROM_DTACK_N & VDP_DTACK_N;
	
	assign SHDO = SH_ROM_SEL ? SH_ROM_DO : SH_REG_DO;
	assign SHWAIT_N = ~SH_ROM_WAIT;
	
	assign SHRES_N = ADCR.RES /*| ~ADCR.REN*/;
	assign SHDREQ0_N = ~FIFO_REQ;
	assign SHDREQ1_N = ~PWM_REQ;
	
	wire CMD_INTM = ICR.INTM & IMMR.CMD;
	wire CMD_INTS = ICR.INTS & IMSR.CMD;
	always_comb begin
		if (VRES_INT)      SHMIRL_N = 3'b000;	//14
		else if (V_INTM)   SHMIRL_N = 3'b001;	//12
		else if (H_INTM)   SHMIRL_N = 3'b010;	//10
		else if (CMD_INTM) SHMIRL_N = 3'b011;	//8
		else if (PWM_INTM) SHMIRL_N = 3'b100;	//6
		else               SHMIRL_N = 3'b111;	//0
		
		if (VRES_INT)      SHSIRL_N = 3'b000;	//14
		else if (V_INTS)   SHSIRL_N = 3'b001;	//12
		else if (H_INTS)   SHSIRL_N = 3'b010;	//10
		else if (CMD_INTS) SHSIRL_N = 3'b011;	//8
		else if (PWM_INTS) SHSIRL_N = 3'b100;	//6
		else               SHSIRL_N = 3'b111;	//0
	end
	
	assign CDO = VDI;
	assign CASEL_N = ASEL_N;
	assign CLWR_N = LWR_N;
	assign CUWR_N = UWR_N;
	assign CCE0_N = ~(ADCR.ADEN & S32X_CE0) & CE0_N;
	assign CCAS0_N = ~(ADCR.ADEN & S32X_CE0) & CAS0_N;
	assign CCAS2_N = CAS2_N;
	
	assign SEL = SH_ROM_GRANT;
	
//	assign VDP_DO = '0;
//	assign VDP_RW = 0;
//	assign VDP_DIR = 0;
//	assign VDP_ACCS = 0;
//	assign VDP_C23 = 0;
	
endmodule