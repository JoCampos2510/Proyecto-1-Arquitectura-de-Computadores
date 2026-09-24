global sum_array
global compute_stats
global normalize_array

section .text


sum_array:
    xor     eax, eax             ; i = 0
    pxor    xmm0, xmm0           ; acumulador = 0.0

.loop:
    cmp     eax, esi             ; compara i con n
    jge     .done                ; si i >= n, salir

    movss   xmm1, [rdi + rax*4]  ; xmm1 = arr[i]
    addss   xmm0, xmm1           ; acumulador += arr[i]

    inc     eax                  ; i = i + 1
    jmp     .loop                ; repetir

.done:
    ret                           ; resultado en xmm0


normalize_array:
    xor     eax, eax              ; i = 0
    xorps   xmm3, xmm3            ; xmm3 = 0.0 (constante)
    comiss  xmm1, xmm3            ; ¿stddev == 0?
    je      .loop_zero_std        ; si sí, camino especial

.loop:
    cmp     eax, edx
    jge     .done

    movss   xmm2, [rdi + rax*4]   ; in[i]
    subss   xmm2, xmm0            ; in[i] - mean
    divss   xmm2, xmm1            ; / stddev
    movss   [rsi + rax*4], xmm2   ; out[i] = resultado

    inc     eax
    jmp     .loop

.loop_zero_std:
    cmp     eax, edx
    jge     .done
    movss   [rsi + rax*4], xmm3   ; out[i] = 0.0 directamente
    inc     eax
    jmp     .loop_zero_std

.done:
    ret



compute_stats:
    test    esi, esi              ; ¿n == 0?
    jne     .valid_n
    pxor    xmm0, xmm0
    movss   [rdx], xmm0           ; *mean = 0
    movss   [rcx], xmm0           ; *var  = 0
    movss   [r8], xmm0            ; *min  = 0
    movss   [r9], xmm0            ; *max  = 0
    ret

.valid_n:
    ; --- Primer pase: suma, min, max ---
    xor     eax, eax
    pxor    xmm0, xmm0            ; suma = 0.0
    movss   xmm1, [rdi]           ; min = arr[0]
    movss   xmm2, [rdi]           ; max = arr[0]

.loop1:
    cmp     eax, esi
    jge     .after_loop1

    movss   xmm3, [rdi + rax*4]   ; arr[i]
    addss   xmm0, xmm3            ; suma += arr[i]

    comiss  xmm3, xmm1
    jae     .skip_min
    movss   xmm1, xmm3            ; min = arr[i]
.skip_min:
    comiss  xmm3, xmm2
    jbe     .skip_max
    movss   xmm2, xmm3            ; max = arr[i]
.skip_max:

    inc     eax
    jmp     .loop1

.after_loop1:
    movss   [r8], xmm1            ; *min
    movss   [r9], xmm2            ; *max

    cvtsi2ss xmm4, esi            ; (float) n
    divss   xmm0, xmm4            ; mean = suma / n
    movss   [rdx], xmm0           ; *mean

    ; --- Segundo pase: varianza ---
    xor     eax, eax
    pxor    xmm5, xmm5            ; suma_sq_diff = 0.0

.loop2:
    cmp     eax, esi
    jge     .after_loop2

    movss   xmm3, [rdi + rax*4]   ; arr[i]
    subss   xmm3, xmm0            ; arr[i] - mean
    mulss   xmm3, xmm3            ; al cuadrado
    addss   xmm5, xmm3

    inc     eax
    jmp     .loop2

.after_loop2:
    divss   xmm5, xmm4            ; var = suma_sq_diff / n
    movss   [rcx], xmm5           ; *var
    ret