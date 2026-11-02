# Experimento didatico de ILP para llvm-mca-18 (x86-64, sintaxe AT&T)
# Dois blocos de 8 instrucoes ADD de 32 bits.
# Sem acessos a memoria ou desvios condicionais.

.text

# Oito cadeias independentes: destinos diferentes.
# LLVM-MCA-BEGIN independentes
    addl %ebx,  %eax
    addl %edx,  %ecx
    addl %r9d,  %r8d
    addl %r11d, %r10d
    addl %r13d, %r12d
    addl %r15d, %r14d
    addl %ebp,  %esi
    addl %ebx,  %edi
# LLVM-MCA-END

# Uma cadeia de dependencia verdadeira (RAW):
# cada instrucao precisa do novo valor de EAX da anterior.
# LLVM-MCA-BEGIN dependentes
    addl %ebx, %eax
    addl %ebx, %eax
    addl %ebx, %eax
    addl %ebx, %eax
    addl %ebx, %eax
    addl %ebx, %eax
    addl %ebx, %eax
    addl %ebx, %eax
# LLVM-MCA-END
