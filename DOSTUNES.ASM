TITLE dostunes

; dostunes.asm
; Jason Wilkin
; Fall 2012

INCLUDE Irvine16.inc
.386


.data
two WORD 2
ten SWORD 10
sign SWORD 1

freqLine BYTE 1 			; Are we reading a note from the file? (or # of beats)

EOF BYTE 0 					; Program is terminated when EOF == 1
FirstLine BYTE 1 			; Helps to get BPM from top of file
	

currentOctave BYTE 0   		; Hold the current octave
beatDuration BYTE 0  		; Holds number of miliseconds to wait when playing the note
beatsMin BYTE 0 			; BPM
beatsMili WORD 0   			; Calculated from BPM
currentIndex WORD 0 		; Index lookup for table of frequencies

;variables for cmdline PROCs
cmdlinebuffer BYTE 200 DUP(0)		; Buffer for reading cmd line
argc BYTE 0				; For reading call arguments
argv WORD 100 DUP(0)
handle WORD ?				; File name
inArg BYTE ?				; Check for whether or not we are
					; currently in an argument when
					; reading in args




openError BYTE "An open error has occurred. Please check file.",0
fileError BYTE "No file was specified. Please supply a file name in the call to hexdump.",0
readError BYTE "A read error has occurred. Please check file.",0
searchError BYTE "An error occured while searching table.",0


lineBuff BYTE 10 DUP(0) 			; Buffer used when reading file
garbageBuff BYTE 10 DUP(0)			; Garbage buffer for extra unnessary bytes (CR and newline bytes)

; Holds indicies for lookup in frequency table
table BYTE "Cn00C#01Db01Dn02D#03Eb03En04Fn05F#06Gb06Gn07G#08Ab08An09A#10Bb10Bn11rr12Z",0


; http://www.phy.mtu.edu/~suits/notefreqs.html
MYSCALE LABEL DWORD
DWORD 209300 ; C 7
DWORD 221746 ; C#7/Db7
DWORD 234932 ; D 7
DWORD 248902 ; D#7/Eb7
DWORD 263702 ; E 7
DWORD 279383 ; F 7
DWORD 295996 ; F#7/Gb7
DWORD 313596 ; G 7
DWORD 332244 ; G#7/Ab7
DWORD 352000 ; A 7
DWORD 372931 ; A#7/Bb7
DWORD 395107 ; B 7
DWORD 000000 ; Rest

.code
Orig08 DWORD ?
Time WORD 4 DUP(?)
HUNDRED DWORD 100
COUNTER WORD 0
CLOCKSPEED DWORD 1193280
hex BYTE "0123456789ABCDEF"
running BYTE 1
octave WORD 6




parseInt PROC
; IN: bx points to a ASCIZ string
; 	containing the characters of a signed decimal number
;	example bx->'7','8','3',0
; OUT: ax contains the integer, in this example, 783 (030Fh)
;      if this number is too large or too small to fit a word,
;      ax is unspecified, and the overflow flag is set.

	push bx
	push cx
	push dx			; dx saved/restored because imul uses it.
	xor ax,ax		; clear ax and overflow flag
pre:	
	cmp BYTE PTR [bx],'-'	; are we negative?  :-) :-)
	jnz top
	mov sign,-1		; negative!	
	inc bx
top:	mov ch,0		; clear high bits of cx
	mov cl,[bx]		; get the next character
	cmp cl,0		; are we done?
	jz done
	sub cl,'0'		; turn the digit to a number in 0..9
	; negate the digit if needed
	cmp sign,1
	jz pos
	; negate cx!!
	neg cx
pos:	imul ten	
	jo done			; quit if overflow
	add ax,cx		; add the number
	jo done			; quit if overflow (again)
	inc bx			; go to next character in the string
	jmp top
done:
	pop dx			; restore registers
	pop cx
	pop bx
	ret
parseInt ENDP


S_On PROC
; Turns the speaker on
	push	ax
		
	in	al, 97
	or	al, 3
	out	97, al

	pop	ax
	ret
S_On ENDP

S_Off PROC
; Turns the speaker off
	push	ax
	in	al, 97
	and 	al, 0fch
	out	97, al
	pop	ax
	ret
S_Off ENDP

SetClockCount PROC
; IN: AX a count to set on the clock
	push	ax
	push	cx

	mov	cx, ax
	mov	al, 182
	out	67, al	; tell timer to accept a new count
	mov	ax, cx

	out	66, al
	mov	al, ah
	out	66, al

	pop	cx
	pop	ax
	ret
SetClockCount ENDP

SetFreq	PROC
	push	bp
	mov	bp,sp

	push 	ax
	push 	bx
	push	dx

	;;  set ax to clockspeed divided by frequency
	mov	eax,cs:CLOCKSPEED
	mov	edx, 0
	mov	ebx, 0
	mov	bx, [bp+4]	; sets bx to the desired frequency
	div	ebx		; divide to get count in ax

	;; and call SetClockCount
	call SetClockCount
	
	pop dx
	pop bx
	pop ax

	mov sp,bp
	pop bp
	ret 2
SetFreq ENDP


adjustOctave PROC
	; IN: eax in centihertz
	; divide by two (7-cs:octave) times

	push cx	
	push bx
	mov cx, 7
	mov bx,OFFSET currentOctave
	sub cx, [bx]
	shr eax, cl
	pop bx
	pop cx
	ret	

adjustOctave ENDP


readCMDLine PROC
; IN:	Nothing
; OUT:	cmdlinebuffer contains the arguments (unparsed)

	pushf			; Save regs
	push cx
	push dx
	push si
	push di

	mov si,82h		; start of actual command line
	mov di,OFFSET cmdlinebuffer	; destination setup
	mov cx,0
	mov cl,es:[80h]		; cx: number of chars in command line
	cmp cx,0		; if no command line args at all...
	jz done			; don't do anything at all
	dec cx			; otherwise skip first space and proceed
again:  cmp cx,0
	jz done
	mov dl,es:[si]		; copy one char from PSP
	mov [di],dl		; to my buffer
	inc di			; increment the pointers
	inc si
	dec cx
	jmp again
done:	mov BYTE PTR [di],0	; null-terminate the whole thing!
	pop di			; Restore regs
	pop si
	pop dx
	pop cx
	popf 
	ret
readCMDLine ENDP


parseCMDLine PROC
; IN:	cmdlinebuffer contains the unparsed arguments
; OUT:	Args in cmdlinebuffer are parsed and null-terminated
	pushf
	push dx
	push si
	push di

	mov inArg,0
	mov si, OFFSET cmdlinebuffer	; pointer into buffer
	mov di, OFFSET argv	; pointer into argv
	mov argc, 0
again:
	mov dl,[si]	 ; load next char from buffer
	cmp dl,0	 ; is this the end?
	jz finished	
			; no
	cmp dl,' '
	jz space

	;-- handle non-space
	cmp inArg,1		; are we already in an argument
	jz continue
	inc argc		; no.. new arg!  yay!!
	mov [di],si		; store starting location
	add di,2
	mov inArg,1
	jmp continue

space:	;-- handle space
	mov inArg,0		; no longer in an argument 
	mov BYTE PTR [si],0	; null terminate 
continue:
	inc si			; go to next character
	jmp again		; and repeat
finished:
	pop di
	pop si
	pop dx
	popf
	ret
parseCMDLine ENDP


Getline PROC
; Reads a line of a Note/Octave or number of beats to be played
	pushf

	push bx
	mov bx,OFFSET freqLine
	mov cx,[bx]
;	call DumpRegs
	pop bx


	cmp freqLine,1
	jz onFreqLine		; Looking at a note line (reading 5 chars)
	mov cx,3 			; Looking at a beat line (reading 3 chars)
	jmp read

onFreqLine:
	mov cx,5 	

read:
	mov ah,3Fh 			; Read in the appropriate number of chars
	int 21h
	jc badr 			; Handle a read error

	cmp freqLine,1
	jz endCheck
	jmp continue
endCheck:
	cmp ax,5 			; Have we read the correct number of chars?...
	jz done


continue:
	cmp ax,3
	jz done
						; ...if not, need to close file, cleanup
	push bx
	mov bx,OFFSET EOF		; End of file, prepare to stop reading
	mov BYTE PTR [bx],1
	pop bx
	jmp done


badr:
	push edx
	mov edx, OFFSET readError 		; Output error message
	call WriteString
	pop edx

done:
	popf
	ret
Getline ENDP

SearchStr PROC
; Searches the table of indicies for the appropriate index into the table of frequencies
	pushf
	push ax
	push bx
	push cx
	push si


	mov bx,OFFSET table 		; bx points to the table of indicies
	mov si,OFFSET lineBuff		; si points to a buffer containing the note (as a string)

top:

	cmp BYTE PTR [bx],'Z' 		; Reached end of table, note not found
	jz error


	mov eax,0 					; Clear eax
	mov al, BYTE PTR [bx] 		; mov first char of note and table into
	mov cl,BYTE PTR [si] 		; registers to compare
	cmp cl,al
	jz continue 				; If they match, check for natural/sharp/flat (n/#/b)
	add bx,4 					; Otherwise, move bx to next note in table
	jmp top

continue:
	mov al,BYTE PTR [bx+1] 		; Compare for natural/sharp/flat (n/#/b)
	mov cl,BYTE PTR [si+1]
	cmp al,cl
	jz match 					; Found it!
	add bx,4 					; Otherwise, move on to next note in table
	jmp top

match:
	mov ch,BYTE PTR [bx+2] 		; Move index to cx
	mov cl,BYTE PTR [bx+3]

	mov ax,0
	sub cl,'0' 					; Convert string to int
	mov al,cl 					; and move it into al

	cmp ch,'0' 					; If index < 10, we're done
	jz done

	add al,10 					; Otherwise, add 10 to al
	jmp done


error:
	push edx
	mov edx,OFFSET searchError 	; Output error message if note is not in table
	call WriteString
	pop edx

done:	
	mov bx,OFFSET currentIndex 	; Move the index into currentIndex
	mov [bx],al
done2:

	pop si
	pop bx
	pop cx
	pop ax
	popf
	ret
SearchStr ENDP



GetBPM PROC
; Reads in BPM from the top of the file and converts it to a integer
	pushf
	push eax
	push ebx
	push ecx
	push edx


	mov dx,OFFSET lineBuff
	mov cx,6 						; Reads in BPM
	mov ah,3Fh
	int 21h

	mov cx,0
	mov bx,OFFSET FirstLine
	mov BYTE PTR [bx],0 			; We are no longer reading the first line
	mov bx,OFFSET lineBuff
BPM:
	cmp BYTE PTR [bx],'0' 			; Have we reached the end of the BPM yet?
	jae moveOn 						; If not, increment to find next chars
	mov BYTE PTR [bx],0 			; If yes, null terminate

	mov bx,OFFSET lineBuff			; Prepare to convert str to int
	mov eax,0
	call parseInt
	mov bx,OFFSET beatsMin	
	mov [bx],ax 					; Store BPM in beatsMin

	cmp cx,2 						; Do we need to read in an extra CR char?
	ja extraRead
	jmp done

extraRead:
	mov bx,handle
	mov dx, OFFSET lineBuff
	mov cx,1 			; accounts for extra CR character
	mov ah,3Fh
	int 21h
	jmp done

moveOn:						; Not done processing BPM
	inc bx 					; Advance pointer to lineBuff
	inc cx 					; Count how many chars are in BPM
	jmp BPM 				


done:

	pop edx
	pop ecx
	pop ebx
	pop eax
	popf
	ret
GetBPM ENDP

GarbageRead PROC
	pushf
	push ax
	push bx
	push cx
	push dx


	mov dx, OFFSET garbageBuff 		; Setup read with appropriate parameters
	mov bx, handle
	mov cx, 1

	mov ah,3Fh 			; Read in one byte
	int 21h

	pop dx
	pop cx
	pop bx
	pop ax
	popf
	ret
GarbageRead ENDP


CalcBeatTime PROC
; Calculates the Beats per millisecond
	pushf
	push eax
	push ebx
	push ecx
	push edx

	mov edx,0 					; Clear edx, eax
	mov eax,0

	mov bx, OFFSET beatsMin
	mov ax,[bx] 				; Move BPM into ax




;   --------- Comment these lines when virtualizing with a faster CPU -----------
;	mov cx,4 					
;	mul cx 						; Multiply by 4 (adjust to run on slower machines)
;   ------------------------------------------------------------------------------


	mov cx,ax
	mov ax,60000
	div cx 						; (BPM * 4) / 60000 = Beats per millisecond

	mov bx, OFFSET beatsMili
	mov [bx],ax 				; Store in beatsMili

	pop edx
	pop ecx
	pop ebx
	pop eax
	popf
	ret
CalcBeatTime ENDP

;------------------------------------------------------------------------
; Main Program
;------------------------------------------------------------------------

main PROC
	mov	ax,@data
	mov	ds,ax

	;-- get command line stuff
	call readCMDLine
	call parseCMDLine	
	
	;-- do we have a file?
	cmp argc,0
	jz nofile

	;-- open the file for reading
	mov al,0			; file mode is read
	mov ah,3Dh			; open file code
	mov dx, argv[0]			; the file name  (is the first arg)
	int 21h
	jc bado				; handle error on open
	mov handle,ax			; store the file handle in memory
	

	mov bx,handle
	call GetBPM 				; Read and process BPM
	call CalcBeatTime 			; Convert to miliseconds
mytop:
	mov dx,OFFSET lineBuff
	call Getline 				; Reads a line from the file
	call WriteString 			; Writes the line to the screen

checkEOF:
	cmp EOF,1 					; Have we reached end of file?
	jz cleanup


	mov si,OFFSET lineBuff
	cmp freqLine,1
	jz freqNull


	;-- BEAT LINE
	push bx
	mov bx,si
	inc bx
readBeat:
	cmp BYTE PTR [bx],'0'
	jae extraBeat
	mov BYTE PTR [bx],0
	jmp procBeat


extraBeat:
	inc bx
	call GarbageRead
	jmp readBeat


procBeat:
	mov bx,OFFSET freqLine 		; Switch freqLine back to 1 for next read
	mov BYTE PTR [bx],1
	
	mov bx,OFFSET lineBuff
	call parseInt 				; Convert number of beats from str to int
	mov bx,OFFSET beatDuration
	mov [bx],ax 				; Store beats in beatDuration


	mov bx,OFFSET currentIndex
	mov di,[bx] 				; Get the index into the freq table
	shl di,2 					; index ^ 4 (to navigate through DWORDs)
	
	mov eax,0
	mov eax,[MYSCALE+di] 		; Move frequency into eax
	pop bx

	cmp eax,0 					; If frequency is 0, need to rest
	jz resting

	call adjustOctave 			; Adjust to the correct octave

	mov edx,0 					; Clear edx
	div cs:HUNDRED 				; Divide frequency by 100 for SetFreq

	push ax
	call SetFreq 				; Set the appropriate frequency
	call S_On 					; Turn the speaker on

	push bx
	mov eax,0
	mov bx,OFFSET beatsMili
	mov ax,[bx]
	mov bx,OFFSET beatDuration
	mov cx,[bx]
	mul cx 			 	; Prepare to delay for:
						; beatsMili (BPMillisecond) * beatDuration (BPM)
	call Delay 			
	call S_Off 			; Turn speaker off after waiting the appropriate amount of time
	pop bx
	jmp mytop 			; Read the next line

resting:
	push bx
	mov bx,OFFSET beatsMili
	mov ax,[bx]
	mov bx,OFFSET beatDuration
	mov cx,[bx]
	mul cx 				; Prepare to delay/rest for:
						; beatsMili (BPMillisecond) * beatDuration (BPM)
	call Delay
	pop bx
	jmp mytop 			; Read the next line


	;-- NOTE LINE
freqNull:
	add si,2 					; si now points to the octave
	mov BYTE PTR [si+1],0 		; Null terminate to prepare for conversion
	mov bx,si
	call parseInt 				; Convert octave str to int

	mov bx,OFFSET currentOctave
	mov [bx],ax 				; Move octave into currentOctave


	call SearchStr 				; Find the index into the freq table for this note
	mov freqLine,0 				; Prepare to read in beats
	jmp mytop


bado:
	mov edx,OFFSET openError 	; Output open error message
	call WriteString
	jmp done


nofile:
	mov edx,OFFSET fileError 	; Output file error message
	call WriteString
	jmp done

cleanup:
	mov bx,handle
	mov ah,3Eh		; Close the file
	int 21h

done:
	mov ax,4C00h
	int 21h
main ENDP
END main

