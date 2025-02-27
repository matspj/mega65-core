;; /*  -------------------------------------------------------------------
;;     MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
;;     Paul Gardner-Stephen, 2014-2019.

;;     These routines provide support for FAT32 and SDCARD support.
;;     ---------------------------------------------------------------- */

;; /*  -------------------------------------------------------------------
;;     FAT file system routines
;;     ---------------------------------------------------------------- */
toupper:
        ;; convert ASCII character to upper case
        ;;
        ;; INPUT:  .A is the ASCII char to convert up uppercase
        ;; OUTPUT: .A will hold the resulting uppersace
        cmp #$61  ; #$60 = ` char (just before lower-case 'a')
        bcc tu1   ; branch if < #$60
        cmp #$7b  ; #$7a = 'z' char
        bcs tu1   ; branch if > #$7a
        and #$5f  ; 's' = %01110011 & %01011111 = 'S' = %01010011
tu1:    rts

;; /*  -------------------------------------------------------------------
;;     MBP / partition routines

;;     Read master boot record. Does not sanity check anything.
;;     ---------------------------------------------------------------- */
readmbr:
        ;; begin by resetting SD card
        ;;

        +Checkpoint "Resetting SDCARD"

        jsr sd_resetsequence
        bcs l7
        +Checkpoint "FAILED resetting SDCARD"

        rts

l7:     ;; MBR is sector 0
        ;;
        lda #$00
        sta sd_address_byte0 ;; is $D681
        sta sd_address_byte1 ;; is $d682
        sta sd_address_byte2 ;; is $d683
        sta sd_address_byte3 ;; is $d684

        ;; Work out if SD card or SDHC card
        ;; SD cards only read on 512 byte aligned addresses.
        ;; SDHC addresses by sector, so all addresses are valid

        ;; Clear SDHC flag to begin with (flag persists through reset)
        lda #$40
        sta $d680

        ;; Attempt non-aligned read
        lda #$02
        sta sd_address_byte0
        sta $d680

sdhccheckwait:
        jsr sdreadytest
        bcs issdhc
        bne sdhccheckwait

        ;; Normal SD (SDSC) card

        lda #$00
        sta sd_address_byte0

        ;; Reset after SDHC test for normal SD mode
        jsr sd_resetsequence

        ;; XXX - We no longer support standard SD cards, so
        ;; we display an error and infinite loop.

        ldx #<msg_foundsdcard
        ldy #>msg_foundsdcard
        jsr printmessage

@unsupportedcard:
        inc $D020
        jmp @unsupportedcard

issdhc:
        ldx #<msg_foundsdhccard
        ldy #>msg_foundsdhccard
        jsr printmessage

        ;; set SDHC flag
        lda #$41
        sta $d680

        jmp sd_readsector

;; /*  -------------------------------------------------------------------
;;     SD Card access routines
;;     ---------------------------------------------------------------- */

sd_open_write_gate:	
	lda #$57
	sta $d680
	rts

write_non_mbr_sector:
	jsr sd_open_write_gate
	jmp write_sector_trigger
write_mbr_sector:
	lda #$4D
	sta $d680
write_sector_trigger:	
	lda #$03
	sta $d680
	rts
	

sd_wait_for_ready:
        jsr sdtimeoutreset
@loop:  jsr sdreadytest
        bcc @loop
        rts

sd_wait_for_ready_reset_if_required:
        ;; Wait until the SD card is ready. If it doesn't get ready,
        ;; then continuously reset it until it does become ready.
        jsr sd_wait_for_ready
        bcs @isReady
        jsr sd_resetsequence
        jmp sd_wait_for_ready_reset_if_required
@isReady:
        rts

sd_resetsequence:
        ;; write $00 to $D680 to start reset
        ;;

        ;; Assert and release reset
        lda #$00
        sta $D680
        lda #$01
        sta $D680

        ;; Wait for SD card to become ready
re2:    jsr sd_wait_for_ready
        bcs re2done        ;; success, so return
        bne re2                ;; not timed out, so keep trying
        rts                ;; timeout, so return

re2done:
        jsr sd_map_sectorbuffer

redone:
        sec
        rts

;;         ========================

        ;; Watch for ethernet packets while waiting for the SD card.
        ;; this allows loading of code into the hypervisor for testing and
        ;; bare-metal operation.
        ;;
sdwaitawhile:
        jsr sdtimeoutreset

sw1:    inc sdcounter+0
        bne sw1
        inc sdcounter+1
        bne sw1
        inc sdcounter+2
        bne sw1
        rts

;;         ========================

sdtimeoutreset:
        ;; count to timeout value when trying to read from SD card
        ;; (if it is too short, the SD card won't reset)
        ;;
        lda #$00
        sta sdcounter+0
        sta sdcounter+1
        lda #$f3
        sta sdcounter+2
        rts

;;         ========================

sdreadytest:
        ;; check if SD card is ready, or if timeout has occurred
        ;; C is set if ready.
        ;; Z is set if timeout has occurred.
        ;;
        lda $d680
        and #$03
        beq sdisready
        inc sdcounter+0
        bne sr1
        inc sdcounter+1
        bne sr1
        inc sdcounter+2
        bne sr1

        ;; timeout
        ;;
        lda #$00 ;; set Z

sr1:    clc
        rts

sdisready:
        sec
        rts

;;         ========================

sd_map_sectorbuffer:

        ;; BG this clobbers .A, maybe we should protect .A as the UNMAP-function does? (see below)

        ;; Clear colour RAM at $DC00 flag, as this prevents mapping of sector buffer at $DE00
        lda #$01
        trb $D030

        ;; Actually map the sector buffer
        lda #$81
        sta $D680
        sec
        rts

;;         ========================

sd_unmap_sectorbuffer:

        pha
        lda #$82
        sta $D680
        pla
        sec
        rts


;;         ========================

;; /*  -------------------------------------------------------------------
;;     Below function is self-contained
;;     ---------------------------------------------------------------- */

sd_readsector:
        ;; Assumes fixed sector number (or byte address in case of SD cards)
        ;; is loaded into $D681 - $D684

!if DEBUG_HYPPO {
        ;; print out debug info
        ;;
;;         jsr printsectoraddress        ; to screen
        jsr dumpsectoraddress        ;; checkpoint message
}

        ;; check if sd card is busy
        ;;
        lda $d680
        and #$01
        bne rsbusyfail

        ;;
        jmp rs4                ;; skipping the redoread-delay below

;;         ========================

redoread:
        ;; redo-read delay
        ;;
        ;; when retrying, introduce a delay.  This seems to be needed often
        ;; when reading the first sector after SD card reset.
        ;;
        ;; print out a debug message to indicate RE-reading (ie previous read failed)
        ;;
        ldx #<msg_sdredoread
        ldy #>msg_sdredoread
        jsr printmessage

        +Checkpoint "ERROR redoread:"

        ldx #$f0
        ldy #$00
        ldz #$00
r1:     inz
        bne r1
        iny
        bne r1
        inx
        bne r1

rs4:
        ;; ask for sector to be read
        ;;
        lda #$02
        sta $d680

        ;; wait for sector to be read
        ;;
        jsr sdtimeoutreset
rs3:
        jsr sdreadytest
        bcs rsread        ;; yes, sdcard is ready
        bne rs3                ;; not ready, so check if ready now?
        beq rereadsector        ;; Z was set, ie timeout
rsread:
        sec
        rts

;;         ========================

rereadsector:
        ;; reset sd card and try again
        ;;

        +Checkpoint "ERROR rereadsector:"

        jsr sd_resetsequence
        jmp rs4

rsbusyfail:     ;; fail
        ;;
        lda #dos_errorcode_read_timeout
        sta dos_error_code
        +Checkpoint "ERROR rsbusyfail:"

        clc
        rts

;; /*  -------------------------------------------------------------------
;;     Above function is self-contained
;;     ---------------------------------------------------------------- */

sd_inc_sectornumber:

        ;; PGS 20190225 - SD SC card support deprecated. Only SD HC supported.

        ;; SDHC card mode: add 1
        ;;

        inc sd_address_byte0
        bne s1
        inc sd_address_byte1
        bne s1
        inc sd_address_byte2
        bne s1
        inc sd_address_byte3
s1:     rts

;;         ========================
