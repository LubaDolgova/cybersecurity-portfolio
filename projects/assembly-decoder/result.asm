.model small
.386
.code
    org 100h
start:
    aad
    
    bt ax,12h
    bt eax,12h
    
    aad
        
    bt bx,12h
    bt word ptr[si],12h
    bt word ptr[si+12h],12h
    bt word ptr[si+1234h],12h
    bt word ptr[eax],12h
    bt word ptr[eax+12h],12h
    bt word ptr[eax+1234h],12h
    bt word ptr[eax+ebx],12h
    bt word ptr[eax+4*ebx+12h],12h
    bt word ptr[eax+2*ebx+1234h],12h
    bt word ptr ss:[si],12h
    bt word ptr cs:[si+12h],12h
    bt word ptr es:[si+1234h],12h
    bt word ptr ss:[eax],12h
    bt word ptr cs:[eax+12h],12h
    bt word ptr es:[eax+1234h],12h
    bt word ptr ss:[eax+ebx],12h
    bt word ptr es:[eax+4*ebx+12h],12h
    bt word ptr es:[eax+2*ebx+1234h],12h
    
    aad
    
    bt bx,12h
    bt word ptr[si],12h
    bt word ptr[si+12h],12h
    bt word ptr[si+1234h],12h
    bt word ptr[eax],12h
    bt word ptr[eax+12h],12h
    bt word ptr[eax+1234h],12h
    bt word ptr[eax+ebx],12h
    bt word ptr[eax+4*ebx+12h],12h
    bt word ptr[eax+2*ebx+1234h],12h
    bt word ptr ss:[si],12h
    bt word ptr cs:[si+12h],12h
    bt word ptr es:[si+1234h],12h
    bt word ptr ss:[eax],12h
    bt word ptr cs:[eax+12h],12h
    bt word ptr es:[eax+1234h],12h
    bt word ptr ss:[eax+ebx],12h
    bt word ptr es:[eax+4*ebx+12h],12h
    bt word ptr es:[eax+2*ebx+1234h],12h
    
    aad
    
    bt ebx,12h
    bt dword ptr[si],12h
    bt dword ptr[si+12h],12h
    bt dword ptr[si+1234h],12h
    bt dword ptr[eax],12h
    bt dword ptr[eax+12h],12h
    bt dword ptr[eax+1234h],12h
    bt dword ptr[eax+ebx],12h
    bt dword ptr[eax+4*ebx+12h],12h
    bt dword ptr[eax+2*ebx+1234h],12h
    bt dword ptr ss:[si],12h
    bt dword ptr cs:[si+12h],12h
    bt dword ptr es:[si+1234h],12h
    bt dword ptr ss:[eax],12h
    bt dword ptr cs:[eax+12h],12h
    bt dword ptr es:[eax+1234h],12h
    bt dword ptr ss:[eax+ebx],12h
    bt dword ptr es:[eax+4*ebx+12h],12h
    bt dword ptr es:[eax+2*ebx+1234h],12h
    
    aad
    
    bt eax,12h
    bt dword ptr[si],12h
    bt dword ptr[si+12h],12h
    bt dword ptr[si+1234h],12h
    bt dword ptr[eax],12h
    bt dword ptr[eax+12h],12h
    bt dword ptr[eax+1234h],12h
    bt dword ptr[eax+ebx],12h
    bt dword ptr[eax+4*ebx+12h],12h
    bt dword ptr[eax+2*ebx+1234h],12h
    bt dword ptr ss:[si],12h
    bt dword ptr cs:[si+12h],12h
    bt dword ptr es:[si+1234h],12h
    bt dword ptr ss:[eax],12h
    bt dword ptr cs:[eax+12h],12h
    bt dword ptr es:[eax+1234h],12h
    bt dword ptr ss:[eax+ebx],12h
    bt dword ptr es:[eax+4*ebx+12h],12h
    bt dword ptr es:[eax+2*ebx+1234h],12h
  
    aad
    
    bt word ptr[si],cx
    bt word ptr[si+12h],cx
    bt word ptr[si+1234h],cx
    bt word ptr[eax],cx
    bt word ptr[eax+12h],cx
    bt word ptr[eax+1234h],cx
    bt word ptr[eax+ebx],cx
    bt word ptr[eax+4*ebx+12h],cx
    bt word ptr[eax+2*ebx+1234h],cx
    bt word ptr ss:[si],cx
    bt word ptr cs:[si+12h],cx
    bt word ptr es:[si+1234h],cx
    bt word ptr ss:[eax],cx
    bt word ptr cs:[eax+12h],cx
    bt word ptr es:[eax+1234h],cx
    bt word ptr ss:[eax+ebx],cx
    bt word ptr es:[eax+4*ebx+12h],cx
    bt word ptr es:[eax+2*ebx+1234h],cx
    
    aad
    
    bt dword ptr[si],ebx
    bt dword ptr[si+12h],ebx
    bt dword ptr[si+1234h],ebx
    bt dword ptr[eax],ebx
    bt dword ptr[eax+12h],ebx
    bt dword ptr[eax+1234h],ebx
    bt dword ptr[eax+ebx],ebx
    bt dword ptr[eax+4*ebx+12h],ebx
    bt dword ptr[eax+2*ebx+1234h],ebx
    bt dword ptr ss:[si],ebx
    bt dword ptr cs:[si+12h],ebx
    bt dword ptr es:[si+1234h],ebx
    bt dword ptr ss:[eax],ebx
    bt dword ptr cs:[eax+12h],ebx
    bt dword ptr es:[eax+1234h],ebx
    bt dword ptr ss:[eax+ebx],ebx
    bt dword ptr es:[eax+4*ebx+12h],ebx
    bt dword ptr es:[eax+2*ebx+1234h],ebx

    aad
    
    rcl al,1
    rcl byte ptr[si],1
    rcl byte ptr[si+12h],1
    rcl byte ptr[si+1234h],1
    rcl byte ptr[eax],1
    rcl byte ptr[eax+12h],1
    rcl byte ptr[eax+12345678h],1
    rcl byte ptr[eax+ebx],1
    rcl byte ptr[eax+2*ebx+12h],1
    rcl byte ptr[eax+4*ebx+12345678h],1
    rcl byte ptr ss:[si],1
    rcl byte ptr cs:[si+12h],1
    rcl byte ptr es:[si+1234h],1
    rcl byte ptr ss:[eax],1
    rcl byte ptr cs:[eax+12h],1
    rcl byte ptr es:[eax+12345678h],1
    rcl byte ptr ss:[eax+2*ebx],1
    rcl byte ptr cs:[eax+1*ebx+12h],1
    rcl byte ptr es:[eax+4*ebx+12345678h],1
    
    aad
    
    rcl al,cl
    rcl byte ptr[si],cl
    rcl byte ptr[si+12h],cl
    rcl byte ptr[si+1234h],cl
    rcl byte ptr[eax],cl
    rcl byte ptr[eax+12h],cl
    rcl byte ptr[eax+1234h],cl
    rcl byte ptr[eax+4*ebx],cl
    rcl byte ptr[eax+2*ebx+12h],cl
    rcl byte ptr[eax+ebx+1234h],cl
    rcl byte ptr ss:[si],cl
    rcl byte ptr ds:[si+12h],cl
    rcl byte ptr es:[si+1234h],cl
    rcl byte ptr ss:[eax],cl
    rcl byte ptr ds:[eax+12h],cl
    rcl byte ptr es:[eax+1234h],cl
    rcl byte ptr ss:[eax+2*ebx],1
    rcl byte ptr cs:[eax+8*ebx+12h],1
    rcl byte ptr es:[eax+ebx+12345678h],1
    
    aad
    
    rcl al,12h
    rcl byte ptr[si],12h
    rcl byte ptr[si+12h],12h
    rcl byte ptr[si+1234h],12h
    rcl byte ptr[eax],12h
    rcl byte ptr[eax+12h],12h
    rcl byte ptr[eax+1234h],12h
    rcl byte ptr[eax+ebx],12h
    rcl byte ptr[eax+4*ebx+12h],12h
    rcl byte ptr[eax+2*ebx+1234h],12h
    rcl byte ptr ss:[si],12h
    rcl byte ptr cs:[si+12h],12h
    rcl byte ptr es:[si+1234h],12h
    rcl byte ptr ss:[eax],12h
    rcl byte ptr cs:[eax+12h],12h
    rcl byte ptr es:[eax+1234h],12h
    rcl byte ptr ss:[eax+ebx],12h
    rcl byte ptr es:[eax+4*ebx+12h],12h
    rcl byte ptr es:[eax+2*ebx+1234h],12h
    
    aad
    
    rcl ax,1
    rcl word ptr[si],1
    rcl word ptr[si+12h],1
    rcl word ptr[si+1234h],1
    rcl word ptr[eax],1
    rcl word ptr[eax+12h],1
    rcl word ptr[eax+12345678h],1
    rcl word ptr[eax+ebx],1
    rcl word ptr[eax+2*ebx+12h],1
    rcl word ptr[eax+4*ebx+12345678h],1
    rcl word ptr ss:[si],1
    rcl word ptr cs:[si+12h],1
    rcl word ptr es:[si+1234h],1
    rcl word ptr ss:[eax],1
    rcl word ptr cs:[eax+12h],1
    rcl word ptr es:[eax+12345678h],1
    rcl word ptr ss:[eax+2*ebx],1
    rcl word ptr cs:[eax+1*ebx+12h],1
    rcl word ptr es:[eax+4*ebx+12345678h],1
    
    aad
    
    rcl ax,cl
    rcl word ptr[si],cl
    rcl word ptr[si+12h],cl
    rcl word ptr[si+1234h],cl
    rcl word ptr[eax],cl
    rcl word ptr[eax+12h],cl
    rcl word ptr[eax+1234h],cl
    rcl word ptr[eax+4*ebx],cl
    rcl word ptr[eax+2*ebx+12h],cl
    rcl word ptr[eax+ebx+1234h],cl
    rcl word ptr ss:[si],cl
    rcl word ptr ds:[si+12h],cl
    rcl word ptr es:[si+1234h],cl
    rcl word ptr ss:[eax],cl
    rcl word ptr ds:[eax+12h],cl
    rcl word ptr es:[eax+1234h],cl
    rcl word ptr ss:[eax+2*ebx],1
    rcl word ptr cs:[eax+8*ebx+12h],1
    rcl word ptr es:[eax+ebx+12345678h],1
    
    aad
    
    rcl ax,12h
    rcl word ptr[si],12h
    rcl word ptr[si+12h],12h
    rcl word ptr[si+1234h],12h
    rcl word ptr[eax],12h
    rcl word ptr[eax+12h],12h
    rcl word ptr[eax+1234h],12h
    rcl word ptr[eax+ebx],12h
    rcl word ptr[eax+4*ebx+12h],12h
    rcl word ptr[eax+2*ebx+1234h],12h
    rcl word ptr ss:[si],12h
    rcl word ptr cs:[si+12h],12h
    rcl word ptr es:[si+1234h],12h
    rcl word ptr ss:[eax],12h
    rcl word ptr cs:[eax+12h],12h
    rcl word ptr es:[eax+1234h],12h
    rcl word ptr ss:[eax+ebx],12h
    rcl word ptr es:[eax+4*ebx+12h],12h
    rcl word ptr es:[eax+2*ebx+1234h],12h
    
    aad
    
    rcl eax,1
    rcl dword ptr[si],1
    rcl dword ptr[si+12h],1
    rcl dword ptr[si+1234h],1
    rcl dword ptr[eax],1
    rcl dword ptr[eax+12h],1
    rcl dword ptr[eax+12345678h],1
    rcl dword ptr[eax+ebx],1
    rcl dword ptr[eax+2*ebx+12h],1
    rcl dword ptr[eax+4*ebx+12345678h],1
    rcl dword ptr ss:[si],1
    rcl dword ptr cs:[si+12h],1
    rcl dword ptr es:[si+1234h],1
    rcl dword ptr ss:[eax],1
    rcl dword ptr cs:[eax+12h],1
    rcl dword ptr es:[eax+12345678h],1
    rcl dword ptr ss:[eax+2*ebx],1
    rcl dword ptr cs:[eax+1*ebx+12h],1
    rcl dword ptr es:[eax+4*ebx+12345678h],1
    
    aad
    
    rcl eax,cl
    rcl dword ptr[si],cl
    rcl dword ptr[si+12h],cl
    rcl dword ptr[si+1234h],cl
    rcl dword ptr[eax],cl
    rcl dword ptr[eax+12h],cl
    rcl dword ptr[eax+1234h],cl
    rcl dword ptr[eax+4*ebx],cl
    rcl dword ptr[eax+2*ebx+12h],cl
    rcl dword ptr[eax+ebx+1234h],cl
    rcl dword ptr ss:[si],cl
    rcl dword ptr ds:[si+12h],cl
    rcl dword ptr es:[si+1234h],cl
    rcl dword ptr ss:[eax],cl
    rcl dword ptr ds:[eax+12h],cl
    rcl dword ptr es:[eax+1234h],cl
    rcl dword ptr ss:[eax+2*ebx],1
    rcl dword ptr cs:[eax+8*ebx+12h],1
    rcl dword ptr es:[eax+ebx+12345678h],1
    
    aad
    
    rcl eax,12h
    rcl dword ptr[si],12h
    rcl dword ptr[si+12h],12h
    rcl dword ptr[si+1234h],12h
    rcl dword ptr[eax],12h
    rcl dword ptr[eax+12h],12h
    rcl dword ptr[eax+1234h],12h
    rcl dword ptr[eax+ebx],12h
    rcl dword ptr[eax+4*ebx+12h],12h
    rcl dword ptr[eax+2*ebx+1234h],12h
    rcl dword ptr ss:[si],12h
    rcl dword ptr cs:[si+12h],12h
    rcl dword ptr es:[si+1234h],12h
    rcl dword ptr ss:[eax],12h
    rcl dword ptr cs:[eax+12h],12h
    rcl dword ptr es:[eax+1234h],12h
    rcl dword ptr ss:[eax+ebx],12h
    rcl dword ptr es:[eax+4*ebx+12h],12h
    rcl dword ptr es:[eax+2*ebx+1234h],12h
    

end start