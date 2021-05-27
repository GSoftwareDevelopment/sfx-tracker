unit SFX_Engine;

interface
const
	SFX_CHANNELS_ADDR	= $6F0;
	SFXNameLength		= 14;
	TABNameLength		= 8;
	SONGNameLength		= 32;

var
(* SFX Mod Modes:
	0 - HFD - High Freq. Div.     - relative modulation of the frequency divider in the range of +/- 127
											- without the possibility of looping the SFX
											- Full backwards compatibility with the original SFX engine
	1 - MFD - Middle Freq. Div.   - relative modulation of the frequency divider in the range of +/- 63
											- SFX looping possible
	2 - LFD/NLM - Low Freq Div.	- note level modulation in relative range of +/- 32 half tones;
											- relative modulation of freq. divider in the range of +/- 32
											- SFX looping possible
	3 - DSD - Direct Set Div.		- direct set of the frequency divider - without looping possible
*)
	SFXModMode:array[0..0] of byte;	// indicates the type of modulation used in the SFX.
	SFXPtr:array[0..0] of word;		// heap pointers to SFX definitions
	TABPtr:array[0..0] of word;		// heap pointera to TAB definitions
	SONGData:array[0..0] of byte;		// table for SONG data

	song_tact,song_beat,song_lpb:byte;

	channels:array[0..15] of byte absolute SFX_CHANNELS_ADDR;

procedure INIT_SFXEngine(_SFXModModes,_SFXList,_TABList,_SONGData:word);

implementation
var
	AUDIO:array[0..0] of byte absolute $d200;

procedure INIT_SFXEngine;
var
	chnOfs:byte;

begin
	SFXModMode:=pointer(_SFXModModes);
	SFXPtr:=pointer(_SFXList);
	TABPtr:=pointer(_TABList);
	SONGData:=pointer(_SONGData);

	chnOfs:=0;
	repeat
		channels[chnOfs]:=$ff; chnOfs:=chnOfs+1;	// SFX address lo
		channels[chnOfs]:=$ff; chnOfs:=chnOfs+1;	// SFX address hi
		channels[chnOfs]:=$ff; chnOfs:=chnOfs+1;	// SFX offset
		channels[chnOfs]:=$00; chnOfs:=chnOfs+1;	// SFX Modulation mode
		channels[chnOfs]:=$00; chnOfs:=chnOfs+1;	// SFX Note
		channels[chnOfs]:=$00; chnOfs:=chnOfs+1;	// SFX frequency
	until chnOfs>15;
end;

procedure SFX_tick(); Assembler; Interrupt;
asm
xitvbl   = $e462;
sysvbv   = $e45c;
audf     = $d200;
audc     = $d201;

// below variables is only for current channel
sfxPtr	= $f5; // SFX Pointer (2 bytes)
chnOfs	= $f7; // SFX Offset in SFX definition
chnMode	= $f8; // SFX Modulation Mode
chnNote	= $f9; // SFX Note
chnFreq	= $fa; // SFX Frequency
chnMod	= $fb; // SFX Modulator
chnCtrl	= $fc; // SFX Control (distortion & volume)

_regA 	= $fd;
_regX 	= $fe;
_regY 	= $ff;

			phr

tick_start
			ldx #0  // channel; channels data offset

// fetching channel & sfx data
// prepare SFX Engine registers

chnset
// get SFX offset
         ldy SFX_CHANNELS_ADDR+2,x
// check SFX offset
         cpy #$ff ; ff=no SFX
         beq noSFX
         sty chnOfs

// get SFX pointer
			lda SFX_CHANNELS_ADDR,x
         sta sfxPtr
         lda SFX_CHANNELS_ADDR+1,x
         sta sfxPtr+1

// get SFX modulation mode
         lda SFX_CHANNELS_ADDR+3,x
         sta chnMode

			cmp #3				// check DFD Modulation mode
			bne get_note_freq
//
// DFD first becouse, must be fast as possible
         lda (sfxPtr),y		// get MOD/VAL
         jmp setPokey

// fetch sound note & frequency
get_note_freq
// get SFX note
         lda SFX_CHANNELS_ADDR+4,x
         sta chnNote
// get SFX frequency
         lda SFX_CHANNELS_ADDR+5,x
         sta chnFreq

// get modulate value
get_modval
         lda (sfxPtr),y
         sta chnMod
// check modulation, if 0, means no modulation
         lda chnMod
         beq setPokey
         jsr modulators
// current frequency in register A

setPokey
			txa
         lsr @
         tax

// store registers direct to POKEY
         sta audf,x
// get distortion & volume
         iny					// shift sfx offset to next byte of definition
         lda (sfxPtr),y
         sta audc,x

         txa
         asl @
         tax

next_channel
			clc

         lda chnOfs
         adc #2
         sta SFX_CHANNELS_ADDR+2,x

			lda chnFreq
         sta SFX_CHANNELS_ADDR+3,x

noSFX
			txa			// shift offset to next channel
			adc #8		// 8 bytes per channel
			tax

         cpx #$20 	// is it last channel?
         bne chnset	// no, go to fetching data
         jmp endtick

sfxend
         lda #$ff
         sta SFX_CHANNELS_ADDR+2,x
         jmp savFreq

endtick  plr
         jmp xitvbl
         rts

;
modulators
			lda chnMode		// get modulation mode

//
// next LFD_NLM, because it is mostly used with melodies
LFD_NLM
			cmp #2			// check LFD/NLM
			bne check_MFD

LFD_NLM_mode				// code for LFD_NLM


			rts				// return frequency in register A

//
// next MFD
check_MFD
			cmp #1			// check MFD
			bne check_HFD

MFD_mode						// code for MFD


			rts				// return frequency in register A

//
// last, compatibility with the original SFX engine
check_HFD
			cmp #0			// check HFD mode
			bne exit_modulator

HFD_MODE						// code for HFD


exit_modulators
         rts				// return frequency in register A
end;

end.
