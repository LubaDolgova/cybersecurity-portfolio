.model small
.386
.stack 100h
.data
    b       db  2500 dup(?)
    a       db  'com.com',0
    c       db  'result.asm',0
    _aad    db  9,'aad',13,10,'$'
    _rcl    db  9,'rcl',9,'$' 
    _bt    db  9,'bt',9,'$'    
    _reg    db  'e',2 dup(?),'$'
    _imm8   db  2 dup(?),'h$'
    _imm16  db  4 dup(?),'h$'
    _imm32  db  8 dup(?),'h$'
    _segm   db  2 dup(?),':$'
    _b      db  'byte ptr $'
    _v      db  'dword ptr $'
    _ob     db  '[$'
    _cb     db  ']$'
    _plus   db  '+$'
    _index  db  ' *$'
    _comma  db  ', $'
    _new_l  db  13,10,'$'
    
.code
start:
    mov     ax,@data
    mov     ds,ax
    mov     es,ax

    lea     dx,a            
    mov     ax,3D00h
    int     21h
    
    mov     bx,ax           
    mov     ax,3F00h
    mov     cx,2500
    lea     dx,b
    int     21h

    mov     ax,3E00h        
    int     21h
    
    lea     dx,c            
    mov     ax,3C00h
    mov     cx,2
    int     21h
    
    lea     si,b
    mov     ebp,0

;------------------------------------------------ begin   
begin:
    mov     eax,0
    lodsb
    
    cmp     al,9eh
    jz      c_aad   
    cmp     al,66h
    jz      op_size
    cmp     al,67h
    jz      addr_size
    cmp     bp,0
    jnz     get_command     
    cmp     al,26h
    jz      segm_reg_es
    cmp     al,2Eh
    jz      segm_reg_cs 
    cmp     al,36h
    jz      segm_reg_ss
    cmp     al,3Eh
    jz      segm_reg_ds
    cmp     al,64h
    jz      segm_reg_fs
    cmp     al,65h
    jz      segm_reg_gs

get_command:
    mov     ah,al
    cmp     ah,0D0h
    jz      rcl_b_1
    cmp     ah,0D2h
    jz      rcl_b_cl
    cmp     ah,0C0h
    jz      rcl_b_imm8
    cmp     ah,0D1h
    jz      rcl_v_1
    cmp     ah,0D3h
    jz      rcl_v_cl
    cmp     ah,0C1h
    jz      rcl_v_imm8
	
	cmp		ah,0fh
	jz      _bt_1or2
    jmp     exit

;------------------------------------------------ aad     
c_aad:
    call    display_aad
    jmp     command_end   
    
;------------------------------------------------ bt    
_bt_1or2:
	lodsb
	cmp 	al,0A3h
	jz		bt_v_mem_reg
	cmp 	al,0BAh
	jz		bt_v_imm8
	jmp     exit
	
bt_v_imm8:
    mov     cx,1
    call    bt_begin
    call    display_comma
    call    set_imm8
    jmp     command_end    

bt_v_mem_reg:
    mov     cx,101h
    call    bt_begin
    jmp     command_end
	
bt_begin:
    push    cx
    call    display_bt
    pop     cx
    jmp     op1

disp_imm8:
    call    set_imm8
    jmp     command_end
    
;------------------------------------------------ rcl
rcl_v_1:
    mov     cx,1
    call    rcl_begin
    jmp     rcl_1

rcl_v_cl:
    mov     cx,1
    call    rcl_begin
    jmp     rcl_cl  
    
rcl_v_imm8:
    mov     cx,1
    call    rcl_begin
    jmp     disp_imm8  

rcl_b_1:
    mov     cx,0
    call    rcl_begin
    jmp     rcl_1

rcl_b_cl:
    mov     cx,0
    call    rcl_begin
    jmp     rcl_cl  
    
rcl_b_imm8:
    mov     cx,0
    call    rcl_begin
    jmp     disp_imm8  
    
rcl_1:
    lea     di,_imm8
    mov     ax,'10'
    stosw
    call    display_imm8
    jmp     command_end

rcl_cl:
    mov     ax,'lc'
    call    set_regbw
    call    display_reg
    jmp     command_end
    
rcl_begin:
    push    cx
    call    display_rcl
    pop     cx
    call    op1
    jmp     display_comma
    
;------------------------------------------------ get opreand
op1:
    lodsb
    mov     bl,al
    mov     ah,al
    shr     bl,6    
    and     al,7    
    
    cmp     ch,0
    jz      get_op
    
    shr     ah,3
    and     ah,7    
    push    ax
    cmp     ch,1
    jz      mem_reg
    push    bx
    jmp     reg_rm
    
mem_reg:
    push    cx
    call    get_op
    call    display_comma
    pop     cx
    pop     ax
    mov     al,ah
    jmp     get_reg
    
reg_rm:
    mov     al,ah
    push    cx
    call    get_reg
    call    display_comma
    pop     cx
    pop     bx
    pop     ax
    
get_op:
    cmp     bl,3  
    jz      get_reg
    push    cx
    push    bx
    push    ax
    call    get_ptr
    call    display_segm
    call    display_ob
    pop     ax
    pop     bx
    pop     cx
    cmp     bl,0
    jz      mod_00
    cmp     bl,1
    jz      mod_01   
    jmp     mod_10

get_reg:
    cmp     cl,1
    jz      mod_11_v
    jmp     mod_11_b
    
get_ptr:
    cmp     cl,1
    jz      display_v
    jmp     display_b    

mod_00:
    call    display_mem
    jmp     display_cb
    
mod_01:
    call    display_mem
    call    display_plus
    call    set_imm8    
    jmp     display_cb
    
mod_10:
    call    display_mem
    call    display_plus
    mov     cx,-1
    call    set_imm1632
    jmp     display_cb
    
mod_11_b:
    call    set_regb_ax
    call    set_regbw
    jmp     display_reg

mod_11_v:
    call    set_regv_ax
    jmp     display_regv
    
;------------------------------------------------ set reg
set_regb_ax:    
    cmp     al,0
    jz      reg_al
    cmp     al,1
    jz      reg_cl
    cmp     al,2
    jz      reg_dl
    cmp     al,3
    jz      reg_bl
    cmp     al,4
    jz      reg_ah
    cmp     al,5
    jz      reg_ch
    cmp     al,6
    jz      reg_dh
    jmp     reg_bh

set_regv_ax:
    cmp     al,0
    jz      reg_ax
    cmp     al,1
    jz      reg_cx
    cmp     al,2
    jz      reg_dx
    cmp     al,3
    jz      reg_bx
    cmp     al,4
    jz      reg_sp
    cmp     al,5
    jz      reg_bp
    cmp     al,6
    jz      reg_si
    jmp     reg_di
    
;------------------------------------------------ r/m 
display_mem:
    rol     ebp,15
    jnc     display_mem_w
    
    cmp     al,4
    jz      sib_byte
    ror     ebp,15
    call    set_regv_ax
    jmp     display_regv_mem
     
display_mem_w:
    ror     ebp,15
    cmp     al,0
    jz      mem_bx_si
    cmp     al,1
    jz      mem_bx_di
    cmp     al,2
    jz      mem_bp_si
    cmp     al,3
    jz      mem_bp_di
    cmp     al,4
    jz      mem_si
    cmp     al,5
    jz      mem_di
    cmp     al,6
    jz      mem_bp
    jmp     mem_bx

;---------------------------------------------------- SIB
sib_byte:
    ror     ebp,15
    lodsb
    mov     bl,al
    mov     bh,al
    shr     bl,6    
    shr     bh,3
    and     bh,7    
    and     al,7    
    push    bx
    call    set_regv_ax
    call    display_regv_mem
    call    display_plus
    pop     bx
    push    bx
    cmp     bl,0
    jz      cont_sib
    cmp     bl,1
    jz      index2
    cmp     bl,2
    jz      index4
    jmp     index8    
    
cont_sib:
    pop     bx
    mov     al,bh
    call    set_regv_ax
    jmp     display_regv_mem
    
;---------------------------------------------------- convert and set 
set_regbw:
    lea     di,_reg
    inc     di
    stosw
    ret
    
display_regv_mem:
    mov     cl,15
    jmp     disp_reg_

display_regv:
    mov     cl,16
disp_reg_:
    call    set_regbw
    rol     ebp,cl
    jc      display_reg_e_
    ror     ebp,cl
    jmp     display_reg
    
display_reg_e_:
    ror     ebp,cl
    jmp     display_reg_e    

set_imm1632:
    add     cl,16
    rol     ebp,cl
    jc      set_imm32_
    ror     ebp,cl
    lea     di,_imm16
    call    convert_word
    stosd
    jmp     display_imm16
    
set_imm32_:
    ror     ebp,cl
    lea     di,_imm32
    call    convert_word
    mov     ecx,eax
    call    convert_word
    stosd
    mov     eax,ecx
    stosd
    jmp     display_imm32

set_imm8:
    lodsb
    call    convert_byte
    lea     di,_imm8
    stosw
    jmp     display_imm8

convert_word:
    lodsb
    call    convert_byte
    shl     eax,16
    lodsb
convert_byte:
    ror     ax,4
    shr     ah,4
    and     al,0Fh
    add     ah,30h
    cmp     ah,3Ah
    jb      conv_h
    add     ah,7
conv_h:    
    add     al,30h
    cmp     al,39h
    ja      conv_c
    ret
conv_c:
    add     al,7
    ret  

;---------------------------------------------------- prefix
op_size:
    ror     ebp,16
    or      bp,1
    rol     ebp,16
    jmp     begin  
    
addr_size:
    ror     ebp,16
    or      bp,2
    rol     ebp,16
    jmp     begin   

segm_reg_es:
    mov     bp,'se'
    jmp     begin

segm_reg_cs:
    mov     bp,'sc'
    jmp     begin
    
segm_reg_ss:
    mov     bp,'ss'
    jmp     begin
    
segm_reg_ds:
    mov     bp,'sd'
    jmp     begin
    
segm_reg_fs:
    mov     bp,'sf'
    jmp     begin
    
segm_reg_gs:
    mov     bp,'sg'
    jmp     begin  
    
;---------------------------------------------------- display
command_end:
    lea     dx,_new_l
    mov     cx,2
    call    _display
    mov     ebp,0
    mov     eax,0
    jmp     begin
    
display_comma:
    lea     dx,_comma
    mov     cx,2
    jmp     _display

display_plus:
    lea     dx,_plus
    mov     cx,1
    jmp     _display

display_ob:
    lea     dx,_ob
    mov     cx,1
    jmp     _display

display_cb:
    lea     dx,_cb
    mov     cx,1
    jmp     _display
    
display_b:
    lea     dx,_b
    mov     cx,9
    jmp     _display
    
display_v:
    lea     dx,_v
    mov     cx,10
    rol     ebp,16
    jc      display_d
    ror     ebp,16
    inc     dx
    dec     cx
    jmp     _display

display_d:
    ror     ebp,16
    jmp     _display

display_index:
    lea     dx,_index
    mov     cx,2
    jmp     _display

display_aad:
    lea     dx,_aad
    mov     cx,6
    jmp     _display
    
display_rcl:
    lea     dx,_rcl
    mov     cx,5
    jmp     _display
    
display_bt:
    lea     dx,_bt
    mov     cx,5
    jmp     _display
    
display_reg:
    lea     dx,_reg
    inc     dx
    mov     cx,2
    jmp    _display
    
display_reg_e:
    lea     dx,_reg
    mov     cx,3
    jmp    _display    
    
display_imm8:
    lea     dx,_imm8
    mov     cx,3
    jmp    _display
    
display_imm16:
    lea     dx,_imm16
    mov     cx,5
    jmp    _display
    
display_imm32:
    lea     dx,_imm32
    mov     cx,9
    jmp    _display
    
display_segm:
    cmp     bp,0
    jnz     display__segm
    ret
    
display__segm:
    mov     ax,bp
    lea     di,_segm
    stosw
    lea     dx,_segm
    mov     cx,3
    jmp    _display
    
_display:
    mov     ah,09h          
    int     21h                
    mov     ah,40h
    mov     bx,5h            
    int     21h    
    ret

;---------------------------------------------------- reg-8    
reg_al:    
    mov     ax,'la'
    ret
reg_bl:    
    mov     ax,'lb'
    ret
reg_cl:    
    mov     ax,'lc'
    ret
reg_dl:    
    mov     ax,'ld'
    ret    
reg_ah:    
    mov     ax,'ha'
    ret
reg_bh:    
    mov     ax,'hb'
    ret
reg_ch:    
    mov     ax,'hc'
    ret
reg_dh:    
    mov     ax,'hd'
    ret      

;---------------------------------------------------- reg-16 
reg_ax:    
    mov     ax,'xa'
    ret
reg_bx:    
    mov     ax,'xb'
    ret
reg_cx:    
    mov     ax,'xc'
    ret
reg_dx:    
    mov     ax,'xd'
    ret    
reg_sp:    
    mov     ax,'ps'
    ret
reg_bp:    
    mov     ax,'pb'
    ret
reg_di:    
    mov     ax,'id'
    ret
reg_si:    
    mov     ax,'is'
    ret
    
;---------------------------------------------------- r/m-16
mem_bx_si:
    mov     ax,'xb'
    call    display_regv_mem
    call    display_plus
    mov     ax,'is'
    jmp     display_regv_mem
       
mem_bx_di:    
    mov     ax,'xb'
    call    display_regv_mem
    call    display_plus
    mov     ax,'id'
    jmp     display_regv_mem

mem_bp_si:    
    mov     ax,'pb'
    call    display_regv_mem
    call    display_plus
    mov     ax,'is'
    jmp     display_regv_mem
    
mem_bp_di:    
    mov     ax,'pb'
    call    display_regv_mem
    call    display_plus
    mov     ax,'id'
    jmp     display_regv_mem 

mem_si:
    mov     ax,'is'
    jmp     display_regv_mem
    
mem_di:    
    mov     ax,'id'
    jmp     display_regv_mem

mem_bp:    
    mov     ax,'pb'
    jmp     display_regv_mem
    
mem_bx:    
    mov     ax,'xb'
    jmp     display_regv_mem
    
;---------------------------------------------------- SIB-index    
index2:
    mov     ax,'2'
    jmp     set_index
    
index4:
    mov     ax,'4'
    jmp     set_index
          
index8:
    mov     ax,'8'
    jmp     set_index
    
set_index:    
    lea     di,_index
    stosb
    call    display_index
    jmp     cont_sib
    
;---------------------------------------------------- exit    
exit:
    mov     ah,4ch
    int     21h
end start