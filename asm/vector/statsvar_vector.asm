;asm de implementacion para array vectorial
	
	global sum_array
	global compute_stats
	global normalize_array

	section .text

sum_array: 
	xor eax, eax             	 ;Inicializa, pone en 0
	vxorps ymm0, ymm0, ymm0  	 ;Pone los 8 carriles de ymm0 en 0

	mov ecx, esi             	 ;Mueve lo que hay en esi a ecx
	and ecx, ~7		 	 ;Pone en bajo 3 bits lsb para redondear abajo x8
	test ecx, ecx		 	 ;Revisa si el contador ecx llega a 0
	jle .sum_reduce	 		 ;Salta a reduccion horizontal

.sum_vec_loop: ;Loop para cargar vectores
	cmp eax, ecx		  	 ;Indice del bucle - N(redondeado) 	
	jge .sum_reduce		  	 ;Si eax >= ecx jump a .sum_reduce
	vmovups ymm1,[rdi + rax*4]	 ;Carga 8 floats unaligned
	vaddps ymm0, ymm0, ymm1		 ;Suma de 8 floats a la vez ymm0 = ymm0 + ymm1
	add eax, 8			 ;Suma 8 al N para que vaya al siguiente float
	jmp .sum_vec_loop
 
.sum_reduce: ;Reduccion horizontal
	vextractf128 xmm2,ymm0, 1	;Saque 4 msb de ymmo y los agrega en xmm2
	vaddps xmm0, xmm0, xmm2		;xmmo[i] = xmmo[i] + xmm2[i]
	vhaddps xmm0, xmm0, xmm0	;Suma horizontal dentro de 128 bits
	vhaddps xmm0, xmm0, xmm0 	;Finalizacion del loop y queda un escalar con suma de all en xmm0[0]

.sum_scalar_tail: ;Suma elementos de manera individual 
	cmp eax, esi	   		;Si el indice del bucle ya llego o paso N
	jge .sum_done			;Pase a tag sum_done 
	vmovss xmm1, [rdi + rax*4]	;Carga UN float en xmm1
	vaddss xmm0, xmm0, xmm1		;xmm0 = xmm0 + xmm1
	inc eax                         ;eax++
	jmp .sum_scalar_tail		;Repite el bucle

.sum_done:
	vzeroupper   			;Evita penalizacion de transicion en AVX a SSE (pone en 0 la mitad alta de ymm0)
	ret				;return a driver

;------------------------------------------------------------------------------------------------------------------------
;FUNCION DE PROM,VAR,MAX,MIN
;-----------------------------------------------------------------------------------------------------------------------

compute_stats:

	push rbx
	push rbp			;push de registros para almacenar variables
	push r12			;usando callee-saved registers
	push r13
	push r14
	push r15
	sub rsp, 8 			;realinar rsp a 16B: 6 pushes dejan 8 mod 16, el call exige 0
 	
	mov rbx, rdi 			;Array de valores
	mov r12d, esi 			;Contador(n)
	mov r13, rdx			;Promedio
	mov r14, rcx			;var
	mov r15, r8			;min
	mov rbp, r9			;max (rpb es callee-saved)

	test r12d, r12d			;Cuando el contador llega a zero entonces pasa a la tag...
	jle .stats_zero 		;...zero_case 
	
;Pasada 1:Calculo del promedio
	
	mov rdi, rbx
	mov esi, r12d
	call sum_array			;Retorna la suma en xmm0

	vcvtsi2ss xmm3,xmm3,r12d	;Convierto el N (registro de proposito general) a xmm3
	vdivss xmm6, xmm0, xmm3 	;sum_array/N
	vmovss[r13], xmm6			;Muevo al registro de promedio r13

;Pasada 2:Calculo de varianza, min, max en un solo recorrido
	
	vbroadcastss ymm7, xmm6 	;Hago un boradcast del promedio y lo guardo en ymm7
	vxorps ymm4, ymm4, ymm4		;Pongo ymm4 en 0 
	vbroadcastss ymm5, [rbx]		;Hago un broadcast de arr[0] en ymm5 
	vmovaps ymm8, ymm5 		;copio ymm5 en ymm8 
	
	xor eax, eax			;Pone eax en 0 
	mov ecx, r12d		 	;Mueve N hacia ecx
	and ecx, ~7		        ;Pone en bajo 3 bits lsb para redondear abajo x8

.stats_loop: 
	cmp eax, ecx			;Si eax es mayor o igual a ecx....
	jge .stats_reduce		;....salte a .stats_reduce

	;Calculo varianza
	vmovups ymm1, [rbx + rax*4]	;8 floats del array
	vsubps ymm2, ymm1, ymm7		;ymm2 = ymm1 - ymm7 
	vmulps ymm2, ymm2, ymm2		;ymm2 = ymm2*ymm2
	vaddps ymm4, ymm4, ymm2 	;ymm4 = ymm4 + ymm2 
	
	;Calculo de min y max
	vminps ymm5, ymm5, ymm1
	vmaxps ymm8, ymm8, ymm1	

	add eax, 8			;Paso al siguiente float
	jmp .stats_loop

.stats_reduce: 
	
	;Reduccion de la suma de cuadrados
	vextractf128 xmm2, ymm4, 1
	vaddps xmm4, xmm4, xmm2
	vhaddps xmm4, xmm4, xmm4
	vhaddps xmm4, xmm4, xmm4

	;Reduccion del minimo 
	vextractf128 xmm2, ymm5, 1     ;Copia la mitad alta de ymm5 a xmm2 
	vminps xmm5, xmm5, xmm2	       ;En xmm5 saca el minimo entre xmm5 y xmm2 
	vmovhlps xmm2, xmm2, xmm5      ;Muevo a xmm2 mitad alta de xmm5; 
	vminps xmm5, xmm5, xmm2        ;Comparo otra vez (solo me importa la mitad baja)
	vshufps xmm2, xmm5, xmm5, 0x55 ;Pongo en xmm2 el valor de xmm5[0]
	vminss xmm5, xmm5, xmm2	       ;Saco el valor minimo de xmm5

	;Reduccion del maximo
	vextractf128 xmm2, ymm8, 1     ;Saco la mitad alta de ymm8 y la almaceno en xmm2
	vmaxps xmm8, xmm8, xmm2	       ;Comparo ambas mitades y almaceno los valores mas altos en xmm8	
	vmovhlps xmm2, xmm2, xmm8      ;Guardo en xmm2 [xmm8[2],xmm8[3],xmm2[2],cmm2[3]] 
	vmaxps xmm8, xmm8, xmm2	       ;Saco los 4 valores mas altos entre xmm8 y xmm2
	vshufps xmm2, xmm8, xmm8,0x55  ;Replica el valor de xmm8[1] en los 4 indices de xmm2       
	vmaxss xmm8, xmm8, xmm2	       ;Saco el maximo entre los ultimos dos numeros que quedaban

.stats_tail: 	
	cmp eax, r12d		       ;cuando el contador eax sea mayor o igual a N
	jge .stats_done                ;salta a tag .stats_done
	vmovss xmm1, [rbx + rax*4]     ;Cargo un solo float en xmm1

	;Tail para suma de cuadrados
	vsubss xmm2, xmm1, xmm6        ;xmm2 = xmm1 - xmm6
	vmulss xmm2, xmm2, xmm2        ;xmm2*xmm2
	vaddss xmm4, xmm4, xmm2	       ;xmm4 = xmm4 + xmm2

	;Tail para max y min
	vminss xmm5, xmm5, xmm1	       ;Min entre xmm5 y xmm1
	vmaxss xmm8, xmm8, xmm1	       ;Min entre xmm8 y xmm1

	inc eax
	jmp .stats_tail

.stats_zero: 
	vxorps xmm0, xmm0, xmm0       ;Pongo en 0 el registro xmm0
	vmovss [r13], xmm0            ;Copio los 0s al registro
	vmovss [r14], xmm0            ;Copio los 0s al registro
	vmovss [r15], xmm0            ;Copio los 0s al registro
	vmovss [rbp], xmm0            ;Copio los 0s al registro
	jmp .done

.stats_done: 
	vdivss xmm4, xmm4, xmm3	      ;var = sumaCuadrados/N
	vmovss [r14], xmm4	      ;Muevo resultado de xmm4 a r14 
	vmovss [r15], xmm5	      ;Muevo resultado de xmm5 a r15 
	vmovss [rbp], xmm8	      ;Muevo resultado de xmm8 a rbp 
	jmp .done

.done:
	add rsp, 8		      ;*****
	pop r15			      ;Hacer pop ***Falta comentar porque en este orden
	pop r14                       ;y buscar rbx
	pop r13
	pop r12
	pop rbp
	pop rbx

	vzeroupper
	ret

;------------------------------------------------------------------------------------------------------------------------
;FUNCION PARA NORMALIZAR ARRAY
;-----------------------------------------------------------------------------------------------------------------------

normalize_array: 
	test	edx, edx	;Si es menor o igual a 0
	jle .done 
	
	;Guardo el promedio y la stdev a xmm0 y xmm1 respectivamente
	vmovaps xmm4, xmm0	     ;Guardo promedio desde xmm0 hacia xmm4
	vmovaps xmm5, xmm1	     ;Guardo stddev a xmm1

	vxorps xmm2,xmm2,xmm2        ;Inicializo en 0
	vucomiss xmm5, xmm2	     ;Comparo xmm5 con xmm2
	jp .broadcast		     ;Si stddev es NaN salta a tag .broadcast
	je .copy		     ;Sistddev==0 salta a tag copy_loop

.broadcast: 
	vbroadcastss ymm2, xmm4      ;Pone los 8 carriles de ymm2 con el promedio
	vbroadcastss ymm3, xmm5	     ;Pone los 8 carriles de ymm3 con la stddev

	xor eax, eax		     ;Inicializo eax en 0
	mov ecx, edx 		     ;Pongo edx (N) en ecx
	and ecx, ~7		     ;Pone en bajo 3 bits lsb para redondear abajo x8
	
.loop: 
	cmp eax, ecx 		     ;Cuando el contador supere N pase a....
	jge .tail		     ;... la tag .tail

	vmovups ymm1, [rdi + rax*4]   ;Cargo 8 floats
	vsubps ymm1, ymm1, ymm2      ;ymm1 = in[i] - promedio
	vdivps ymm1, ymm1, ymm3      ; /stddev
	vmovups [rsi + rax*4], ymm1  ;guardo 8 floats en out(ymm1)
	add eax, 8		     ;Paso de float
	jmp .loop

.tail: 
	cmp eax, edx		     ;Caundo el contador supere el numero de elementos del arreglo...
	jge .done                    ;...significa que termino y paso a .done

	vmovss xmm1, [rdi + rax*4]   ;Cargo 1 float
	vsubss xmm1, xmm1, xmm4      ;xmm1 = in - promedio
	vdivss xmm1, xmm1, xmm5      ; /stddev
	vmovss [rsi + rax*4], xmm1   ;guardo el float en out (xmm1)
	inc eax
	jmp .tail

.copy:
	xor eax, eax 		     ;Pone eax en 0

.copy_next:
	cmp eax, edx		     ;Cuando el contador sea mayor o igual a los elementos del arreglo...
	jge .done 		     ;...salta a done 

	vmovss xmm1,[rdi +rax*4]     ;Carga float en in
	vmovss [rsi + rax*4], xmm1   ;Lo copia en out
	inc eax
	jmp .copy_next

.done:
	vzeroupper
	ret  
