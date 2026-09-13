; AHORA SI, AQUI ES DONDE APRENDO A USAR ESTA MICA
    global sum_array
    global compute_stats
    global normalize_array

    section .text

; ---------------------------------------------------------------
; float sum_array(const float *arr, int n)
;   rdi = arr, esi = n -> retorna la suma en xmm0
;
; IMPLEMENTADA COMO EJEMPLO. Fijense especialmente en:
;   (1) como se calcula cuantos elementos entran en bucles de 8
;       ("and ecx, ~7" redondea n hacia abajo al multiplo de 8),
;   (2) la REDUCCION HORIZONTAL para pasar de 8 sumas parciales
;       (un YMM) a un unico escalar,
;   (3) el BUCLE ESCALAR DE CIERRE para el remanente (n % 8 != 0).
; Reutilicen este mismo patron en compute_stats y normalize_array.
; ---------------------------------------------------------------
sum_array:
    xor     eax, eax               ; eax = i = 0
    vxorps  ymm0, ymm0, ymm0       ; ymm0 = acumulador vectorial (8 carriles) = 0

    mov     ecx, esi
    and     ecx, ~7                ; ecx = n redondeado hacia abajo, multiplo de 8
    test    ecx, ecx
    jle     .sum_reduce

.sum_vec_loop:
    cmp     eax, ecx
    jge     .sum_reduce
    vmovups ymm1, [rdi + rax*4]    ; carga 8 floats (unaligned: siempre valido)
    vaddps  ymm0, ymm0, ymm1       ; acumula por carril
    add     eax, 8
    jmp     .sum_vec_loop

.sum_reduce
    ; --- reduccion horizontal: 8 carriles de ymm0 -> un escalar ---
    vextractf128 xmm2, ymm0, 1     ; xmm2 = mitad alta (carriles 4-7)
    vaddps  xmm0, xmm0, xmm2       ; xmm0 = 4 sumas parciales (carriles 0-3 + 4-7)
    vhaddps xmm0, xmm0, xmm0       ; suma horizontal dentro de 128 bits
    vhaddps xmm0, xmm0, xmm0       ; xmm0[0] = suma total de los 8 carriles originales

.sum_scalar_tail:
    ; --- elementos sobrantes (n % 8), uno a la vez ---
    cmp     eax, esi
    jge     .sum_done
    vmovss  xmm1, [rdi + rax*4]
    vaddss  xmm0, xmm0, xmm1
    inc     eax
    jmp     .sum_scalar_tail

.sum_done:
    vzeroupper                     ; evita penalizacion de transicion AVX/SSE
    ret

compute_stats:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    ; Guardar los 6 argumentos en registros callee-saved
    mov     rbx, rdi                ; arr
    mov     r12, esi               ; n
    mov     r13, rdx                ; mean*
    mov     r14, rcx                ; var*
    mov     r15, r8                 ; min*
    mov     r10, r9                 ; max*   (r10 es caller-saved pero
                                    ;  no llamamos a nadie, asi que sirve)

    test    r12d, r12d
    jle     .zero_case

; ---- PASADA 1: suma inline (evita el call y el spill de registros) ----
    xor     eax, eax
    vxorps  ymm0, ymm0, ymm0
    mov     ecx, r12d
    and     ecx, ~7
.s_loop:
    cmp     eax, ecx
    jge     .s_red
    vaddps  ymm0, ymm0, [rbx + rax*4]
    add     eax, 8
    jmp     .s_loop
.s_red:
    vextractf128 xmm2, ymm0, 1
    vaddps  xmm0, xmm0, xmm2
    vhaddps xmm0, xmm0, xmm0
    vhaddps xmm0, xmm0, xmm0
.s_tail:
    cmp     eax, r12d
    jge     .s_done
    vaddss  xmm0, xmm0, [rbx + rax*4]
    inc     eax
    jmp     .s_tail
.s_done:
    vcvtsi2ss xmm3, xmm3, r12d      ; xmm3 = (float)n
    vdivss  xmm6, xmm0, xmm3        ; xmm6 = mean
    vmovss  [r13], xmm6

; ---- PASADA 2: varianza + min + max en un solo recorrido ----
    vbroadcastss ymm7, xmm6         ; ymm7 = [mean] x8
    vxorps  ymm4, ymm4, ymm4        ; ymm4 = acumulador de cuadrados
    vbroadcastss ymm5, [rbx]        ; ymm5 = min, init con arr[0]
    vmovaps ymm8, ymm5              ; ymm8 = max, init con arr[0]

    xor     eax, eax
    mov     ecx, r12d
    and     ecx, ~7

.v_loop:
    cmp     eax, ecx
    jge     .v_red
    vmovups ymm1, [rbx + rax*4]     ; 8 floats de arr
    vsubps  ymm2, ymm1, ymm7        ; d = x - mean
    vmulps  ymm2, ymm2, ymm2        ; d^2
    vaddps  ymm4, ymm4, ymm2        ; acumula por carril
    vminps  ymm5, ymm5, ymm1        ; min corriente
    vmaxps  ymm8, ymm8, ymm1        ; max corriente
    add     eax, 8
    jmp     .v_loop

.v_red:
    ; --- reduccion de la suma de cuadrados ---
    vextractf128 xmm2, ymm4, 1
    vaddps  xmm4, xmm4, xmm2
    vhaddps xmm4, xmm4, xmm4
    vhaddps xmm4, xmm4, xmm4

    ; --- reduccion del minimo (no existe vhminps) ---
    vextractf128 xmm2, ymm5, 1
    vminps  xmm5, xmm5, xmm2        ; 8 -> 4
    vmovhlps xmm2, xmm2, xmm5
    vminps  xmm5, xmm5, xmm2        ; 4 -> 2
    vshufps xmm2, xmm5, xmm5, 0x55
    vminss  xmm5, xmm5, xmm2        ; 2 -> 1

    ; --- reduccion del maximo ---
    vextractf128 xmm2, ymm8, 1
    vmaxps  xmm8, xmm8, xmm2
    vmovhlps xmm2, xmm2, xmm8
    vmaxps  xmm8, xmm8, xmm2
    vshufps xmm2, xmm8, xmm8, 0x55
    vmaxss  xmm8, xmm8, xmm2

.v_tail:
    cmp     eax, r12d
    jge     .v_done
    vmovss  xmm1, [rbx + rax*4]
    vsubss  xmm2, xmm1, xmm6
    vmulss  xmm2, xmm2, xmm2
    vaddss  xmm4, xmm4, xmm2
    vminss  xmm5, xmm5, xmm1
    vmaxss  xmm8, xmm8, xmm1
    inc     eax
    jmp     .v_tail

.v_done:
    vdivss  xmm4, xmm4, xmm3        ; var = sum_sq / n  (poblacional)
    vmovss  [r14], xmm4
    vmovss  [r15], xmm5
    vmovss  [r10], xmm8
    jmp     .done

.zero_case:
    vxorps  xmm0, xmm0, xmm0
    vmovss  [r13], xmm0
    vmovss  [r14], xmm0
    vmovss  [r15], xmm0
    vmovss  [r10], xmm0

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    vzeroupper
    ret

; ---------------------------------------------------------------
; void normalize_array(const float *in, float *out, int n,
;                       float mean, float stddev)
;   rdi = in, rsi = out, edx = n, xmm0 = mean, xmm1 = stddev
;   out[i] = (in[i] - mean) / stddev
;   Caso borde: si stddev == 0.0
;   copia in[i] en out[i] tal cual.
; ---------------------------------------------------------------
normalize_array:
    test    edx, edx
    jle     .done                   ; n <= 0 -> no hay nada que hacer

    ; Preservar los argumentos flotantes antes de reutilizar xmm0/xmm1
    vmovaps xmm4, xmm0              ; xmm4 = mean   (para el bucle escalar)
    vmovaps xmm5, xmm1              ; xmm5 = stddev

    ; Caso borde: stddev == 0.0 -> copia directa (evita division por cero)
    vxorps   xmm2, xmm2, xmm2
    vucomiss xmm5, xmm2
    jp       .broadcast             ; NaN -> camino normal (no es == 0)
    je       .copy_loop             ; stddev == 0 -> solo copiar

.broadcast:
    vbroadcastss ymm2, xmm4         ; ymm2 = [mean]   x8 carriles
    vbroadcastss ymm3, xmm5         ; ymm3 = [stddev] x8 carriles

    xor     eax, eax                ; i = 0
    mov     ecx, edx
    and     ecx, ~7                 ; ecx = n truncado a multiplo de 8

.vec_loop:
    cmp     eax, ecx
    jge     .tail
    vmovups ymm1, [rdi + rax*4]     ; carga 8 floats de in
    vsubps  ymm1, ymm1, ymm2        ; in[i] - mean   (8 a la vez)
    vdivps  ymm1, ymm1, ymm3        ; / stddev       (8 a la vez)
    vmovups [rsi + rax*4], ymm1     ; guarda 8 floats en out
    add     eax, 8
    jmp     .vec_loop

.tail:
    ; Remanente (n % 8), un elemento por iteracion
    cmp     eax, edx
    jge     .done
    vmovss  xmm1, [rdi + rax*4]
    vsubss  xmm1, xmm1, xmm4
    vdivss  xmm1, xmm1, xmm5
    vmovss  [rsi + rax*4], xmm1
    inc     eax
    jmp     .tail

.copy_loop:
    xor     eax, eax
.copy_next:
    cmp     eax, edx
    jge     .done
    vmovss  xmm1, [rdi + rax*4]
    vmovss  [rsi + rax*4], xmm1
    inc     eax
    jmp     .copy_next

.done:
    vzeroupper                      ; evita penalizacion de transicion AVX/SSE
    ret
