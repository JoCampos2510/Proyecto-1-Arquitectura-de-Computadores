;asm de implementacion para array vectorial
	
	global sum_array
	global compute_stats
	global normalize_array

	section .text

sum_array: 
	xor eax, eax             	 ;Inicializa, pone en 0
	vxorps ymm0, ymm0, ymm0  	 ;Pone los tres carriles de ymm0 en 0

	mov ecx, esi             	 ;Mueve lo que hay en ecx a es

	mov ecx, esi             	 ;Mueve lo que hay en ecx a esi
	and ecx, ~7		 	 ;Pone en bajo 3 bits lsb para redondear abajo x8
	test ecx, ecx		 	 ;Revisa si el contador ecx llega a 0
	jle .sum_reduce	 		 ;Salta a reduccion horizontal

.sum_vec_loop ;Loop para cargar vectores
	cmp eax, ecx		  	 ;Indice del bucle - N(redondeado) 	
	jge .sum_reduce		  	 ;Si eax >= ecx jump a .sum_reduce
	vmovups ymm1,[rdi + rax*4]	 ;Carga 8 floats unaligned
	vaddps ymm0, ymm0, ymm1		 ;Suma de 8 floats a la vez ymm0 = ymm0 + ymm1
	add eax, 8			 ;Suma 8 al N para que vaya al siguiente float
	jmp .sum_vec_loop
 
.sum_reduce ;Reduccion horizontal
	vextractf128 xmm2,ymm0, 1	;Saque 4 msb de ymmo y los agrega en xmm2
	vaddps xmm0, xmm0, xmm2		;xmmo[i] = xmmo[i] + xmm2[i]
	vhaddps xmm0, xmm0, xmm0	;Suma horizontal dentro de 128 bits
	vhaddps xmm0, xmm0, xmm0 	;Finalizacion del loop y queda un escalar con suma de all en xmm0[0]

.sum_scalar_tail ;Suma elementos de manera individual 
	cmp eax, esi	   		;Si el indice del bucle ya llego o paso N
	jge .sum_done			;Pase a tag sum_done 
	vmovss xmm1, [rdi + rax*4]	;Carga UN float en xmm1
	vaddss xmm0, xmm0, xmm1		;xmm0 = xmm0 + xmm1
	inc eax                         ;eax++
	jmp .sum_escalar_tail		;Repite el bucle

.sum_done
	vzeroupper   			;Evita penalizacion de transicion en AVX a SSE (pone en 0 la mitad alta de ymm0)
	ret				;return a driver

compute_stats:

	push rbx			;push de registros para almacenar variables
	push r12			;usando callee-saved registers
	push r13
	push r14
	push r15
 	
	mov rbx, rdi 			;Array de valores
	mov r12d, esi 			;Contador(n)
	mov r13, rdx			;Promedio
	mov r14, rcx			;var
	mov r15, r8			;min
	mov r10, r9			;max (Usamos  r10 que es caller-saved pero al no llamar a nadie no se borra)

	test r12d, r12d
	jle .zero_case 			 
